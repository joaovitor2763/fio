import SwiftUI
import FioKit
import UIKit

/// One entry: the observer's notes, original audio, and full transcript.
struct EntryDetailScreen: View {
    let entryID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @Environment(\.locale) private var locale
    @AppStorage("hasSeenWeekNote") private var hasSeenWeekNote = false

    @State private var showContextEditor = false
    @State private var showTranscriptEditor = false
    @State private var showReflectionEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showRecorder = false
    @State private var showRetranscriptionLanguages = false
    @State private var isRetranscribing = false
    @State private var updateError: String?
    @State private var transcriptEditorError: String?
    @State private var reflectionEditorError: String?
    @State private var exportPayload: ExportPayload?
    @State private var draftContext = ""
    @State private var draftTranscript = ""
    @State private var draftHeadline = ""
    @State private var draftObservations = ""
    @State private var audioPlayer = AudioPlaybackController()

    private var entry: Entry? { store.entry(withID: entryID) }

    var body: some View {
        Group {
            if let entry {
                content(for: entry)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .background(Theme.background)
        .navigationTitle(entry.map { Formatting.entryTitle(for: $0.createdAt) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .task(id: entry?.audioFileName) {
            if let fileName = entry?.audioFileName {
                audioPlayer.load(fileName: fileName)
            } else {
                audioPlayer.stop()
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private func content(for entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !entry.displayObservations.isEmpty {
                    observationList(for: entry)
                } else if store.annotatingEntryIDs.contains(entry.id) {
                    HStack(spacing: 8) {
                        ReadingDot()
                        Text("Fio is reading this entry.")
                            .font(.footnote)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                } else if entry.transcript.isSubstantial {
                    Button {
                        regenerateReflection(for: entry, style: .standard)
                    } label: {
                        Label("Create reflection", systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if !entry.displayObservations.isEmpty {
                    contextRow(for: entry)
                }

                if !hasSeenWeekNote {
                    weekNoteCard
                }

                if entry.audioFileName != nil {
                    audioPlayerCard
                    retranscriptionAction(for: entry)
                }

                transcriptSection(for: entry)

                if !entry.authorContext.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Added later")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        Text(entry.authorContext)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                footerActions(for: entry)
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .sheet(isPresented: $showContextEditor) { contextEditor(for: entry) }
        .sheet(isPresented: $showTranscriptEditor) { transcriptEditor(for: entry) }
        .sheet(isPresented: $showReflectionEditor) { reflectionEditor(for: entry) }
        .sheet(isPresented: $showRetranscriptionLanguages) {
            RetranscriptionLanguagePicker { locale in
                retranscribe(entry, using: locale)
            }
        }
        .sheet(item: $exportPayload) { payload in
            ActivityShareSheet(items: payload.items)
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen(replacingEntryID: entry.id)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                Task {
                    await store.delete(entryID: entry.id)
                    dismiss()
                }
            }
        } message: {
            Text("It is only stored on this phone, so this removes it everywhere it exists.")
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { updateError != nil },
                set: { if !$0 { updateError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateError ?? "")
        }
    }

    private func observationList(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reflection")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if store.annotatingEntryIDs.contains(entry.id) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.secondaryText)
                } else {
                    reflectionMenu(for: entry)
                }
            }

            ForEach(entry.displayObservations, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text("•").foregroundStyle(Theme.secondaryText)
                    Text(line)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    private func reflectionMenu(for entry: Entry) -> some View {
        Menu {
            Button {
                draftHeadline = entry.reflection.headline
                draftObservations = entry.reflection.observations.joined(separator: "\n")
                showReflectionEditor = true
            } label: {
                Label("Edit reflection", systemImage: "pencil")
            }

            Divider()

            Button {
                regenerateReflection(for: entry, style: .concise)
            } label: {
                Label("Make shorter", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                regenerateReflection(for: entry, style: .expanded)
            } label: {
                Label("Expand", systemImage: "text.append")
            }

            Button {
                regenerateReflection(for: entry, style: .standard)
            } label: {
                Label("Reflect again", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Reflection options")
    }

    private func transcriptSection(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(entry.transcript.isEmpty ? "Add" : "Edit") {
                    draftTranscript = entry.transcript.text
                    showTranscriptEditor = true
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            }

            if entry.transcript.isEmpty {
                Text("Transcription unavailable. The original audio is preserved.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(entry.transcript.text)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.primaryText.opacity(0.92))
                    .textSelection(.enabled)
            }
        }
    }

    private func contextRow(for entry: Entry) -> some View {
        Button {
            draftContext = entry.authorContext
            showContextEditor = true
        } label: {
            Group {
                if entry.authorContext.isEmpty {
                    Label("Not what you meant? Add context", systemImage: "text.badge.plus")
                } else {
                    Label("Edit your added context", systemImage: "text.badge.plus")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.tertiaryText)
        }
        .buttonStyle(.plain)
    }

    private var weekNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This becomes your week.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("On Sunday, Fio reads the week back to you — what repeated, what shifted. You don't have to do anything.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("Got it") {
                withAnimation { hasSeenWeekNote = true }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func footerActions(for entry: Entry) -> some View {
        HStack(spacing: 18) {
            Button {
                showRecorder = true
            } label: {
                if entry.audioFileName == nil {
                    Label("Record instead", systemImage: "mic")
                } else {
                    Label("Re-record", systemImage: "mic")
                }
            }
            Text("·").foregroundStyle(Theme.tertiaryText)
            exportMenu(for: entry)
            Text("·").foregroundStyle(Theme.tertiaryText)
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.tertiaryText)
        .buttonStyle(.plain)
    }

    private func exportMenu(for entry: Entry) -> some View {
        Menu {
            if !entry.transcript.isEmpty {
                Button {
                    exportPayload = ExportPayload(items: [entry.transcript.text])
                } label: {
                    Label("Export text", systemImage: "doc.plaintext")
                }
            }

            if let audioURL = entry.audioFileName.flatMap(AudioFileStore.url(for:)) {
                Button {
                    exportPayload = ExportPayload(items: [audioURL])
                } label: {
                    Label("Export audio", systemImage: "waveform")
                }

                if !entry.transcript.isEmpty {
                    Button {
                        exportPayload = ExportPayload(
                            items: [entry.transcript.text, audioURL]
                        )
                    } label: {
                        Label("Export text and audio", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private var audioPlayerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    audioPlayer.cycleRate()
                } label: {
                    Text(playbackRateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Capsule().fill(Theme.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed \(playbackRateLabel)")
            }

            if let message = audioPlayer.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: 14) {
                    Button {
                        audioPlayer.togglePlayback()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primaryControlForeground)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.primaryControlBackground))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                            ? appLocalized("Pause audio", locale: locale)
                            : appLocalized("Play audio", locale: locale)
                    )

                    VStack(spacing: 6) {
                        AudioScrubber(
                            progress: audioProgress,
                            onSeek: { progress in
                                audioPlayer.seek(to: progress * audioPlayer.duration)
                            }
                        )
                        .disabled(audioPlayer.duration <= 0)

                        HStack {
                            Text(Formatting.clock(audioPlayer.currentTime))
                            Spacer()
                            Text(Formatting.clock(audioPlayer.duration))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func retranscriptionAction(for entry: Entry) -> some View {
        Button {
            showRetranscriptionLanguages = true
        } label: {
            HStack(spacing: 7) {
                if isRetranscribing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.secondaryText)
                } else {
                    Image(systemName: "captions.bubble")
                }
                if isRetranscribing {
                    Text("Transcribing audio…")
                } else {
                    Text("Transcribe again in another language")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(isRetranscribing || entry.audioFileName == nil)
    }

    private func retranscribe(_ entry: Entry, using locale: Locale) {
        showRetranscriptionLanguages = false
        guard !isRetranscribing else { return }
        isRetranscribing = true
        updateError = nil

        Task {
            do {
                try await store.retranscribe(entryID: entry.id, locale: locale)
            } catch {
                updateError = error.localizedDescription
            }
            isRetranscribing = false
        }
    }

    private func regenerateReflection(for entry: Entry, style: ReflectionStyle) {
        Task {
            await store.regenerateReflection(entryID: entry.id, style: style)
        }
    }

    private var audioProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(max(audioPlayer.currentTime / audioPlayer.duration, 0), 1)
    }

    private var playbackRateLabel: String {
        audioPlayer.rate == 1
            ? "1×"
            : "\(String(format: "%g", audioPlayer.rate))×"
    }

    private func transcriptEditor(for entry: Entry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Correct the words below. Saving will regenerate the reflection from the edited transcript.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                TextEditor(text: $draftTranscript)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))

                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Edit transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTranscriptEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await store.saveTranscript(
                                    draftTranscript,
                                    forEntryID: entry.id
                                )
                                showTranscriptEditor = false
                            } catch {
                                transcriptEditorError = error.localizedDescription
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        draftTranscript.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { transcriptEditorError != nil },
                set: { if !$0 { transcriptEditorError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriptEditorError ?? "")
        }
    }

    private func reflectionEditor(for entry: Entry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Headline")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Main observation", text: $draftHeadline, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Further observations")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text("Put each observation on a separate line. Up to three are kept.")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        TextEditor(text: $draftObservations)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: 180)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showReflectionEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let observations = draftObservations
                            .split(whereSeparator: \.isNewline)
                            .map(String.init)
                        Task {
                            do {
                                try await store.saveReflection(
                                    headline: draftHeadline,
                                    observations: observations,
                                    forEntryID: entry.id
                                )
                                showReflectionEditor = false
                            } catch {
                                reflectionEditorError = error.localizedDescription
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { reflectionEditorError != nil },
                set: { if !$0 { reflectionEditorError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reflectionEditorError ?? "")
        }
    }

    private func contextEditor(for entry: Entry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Say what you actually meant. The observer reads this too.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                TextEditor(text: $draftContext)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Add context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContextEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.saveContext(draftContext, forEntryID: entry.id)
                            showContextEditor = false
                        }
                    }
                }
            }
        }
    }
}

private struct ExportPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private struct RetranscriptionLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var availableLocales: [Locale] = []

    let onSelect: (Locale) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if availableLocales.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading languages…")
                        }
                        .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(availableLocales, id: \.self) { locale in
                            Button {
                                onSelect(locale)
                            } label: {
                                HStack {
                                    Text(TranscriptionLanguagePreference.displayName(for: locale))
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Text(TranscriptionLanguagePreference.identifier(for: locale))
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Choose the language spoken in this audio")
                } footer: {
                    Text("Only this entry is changed. Your language for new recordings stays the same.")
                }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Transcribe again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                availableLocales = await TranscriptionLanguagePreference.availableLocales()
            }
        }
    }
}

private struct AudioScrubber: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.card)
                    .frame(height: 3)

                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: width * CGFloat(progress), height: 3)

                Circle()
                    .fill(Theme.primaryText)
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, width * CGFloat(progress) - 4))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(Double(min(max(value.location.x / width, 0), 1)))
                    }
            )
        }
        .frame(height: 20)
        .accessibilityLabel("Audio position")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
