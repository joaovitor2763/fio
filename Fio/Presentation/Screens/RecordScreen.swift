import SwiftUI
import FioKit

/// Full-screen recorder: waveform, clock, pause, done. Speak; Fio writes.
struct RecordScreen: View {
    /// When set, the new entry replaces this one (the "Re-record" path).
    var replacingEntryID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(JournalStore.self) private var store
    @State private var session = RecordingSession()
    @State private var entryDate = Date.now
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer()

                WaveformView(levels: session.levels, isLive: session.phase == .recording)
                    .frame(height: 90)
                    .padding(.horizontal, 36)

                Text(Formatting.clock(session.elapsed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 22)

                Spacer()

                Label(session.transcriptionLanguageName, systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.bottom, 24)

                controls
                    .padding(.bottom, 36)
            }

            if case .failed(let message) = session.phase {
                failureView(message)
            }
        }
        .task { await session.start() }
        .sensoryFeedback(.impact(weight: .light), trigger: session.phase)
        .interactiveDismissDisabled()
    }

    private var topBar: some View {
        HStack {
            Button("Discard") {
                session.cancel()
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.tertiaryText)
            Spacer()
            if replacingEntryID == nil {
                DatePicker(
                    "Entry date",
                    selection: $entryDate,
                    in: Date.distantPast...Date.now,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityLabel("Entry date")
                .accessibilityIdentifier("entry-date-picker")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button {
                session.phase == .paused ? session.resume() : session.pause()
            } label: {
                Image(systemName: session.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.card))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(
                session.phase == .paused
                    ? appLocalized("Resume", locale: locale)
                    : appLocalized("Pause", locale: locale)
            )

            Button {
                Task { await saveAndDismiss() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryControlForeground)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Theme.primaryControlBackground))
                    .overlay {
                        if isSaving {
                            ProgressView().tint(Theme.primaryControlForeground)
                        }
                    }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(isSaving || session.phase == .preparing)
            .accessibilityLabel("Finish entry")
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Close") { dismiss() }
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func saveAndDismiss() async {
        guard !isSaving else { return }
        isSaving = true

        let recording = await session.finish()

        await store.finishRecording(
            transcriptText: recording.transcript,
            duration: recording.duration,
            audioFileName: recording.audioFileName,
            replacing: replacingEntryID,
            applyPersonalVocabulary: true,
            at: entryDate
        )
        dismiss()
    }
}
