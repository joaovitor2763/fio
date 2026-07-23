import SwiftUI
import SwiftData

/// Full-screen recorder: waveform, clock, pause, done. Speak; Slate writes.
struct RecordScreen: View {
    /// When set, the new entry replaces this one (the "Re-record" path).
    var replacing: JournalEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session = RecordingSession()
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

                Text(session.elapsed.clock)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 22)

                addTimeButton
                    .padding(.top, 14)

                Spacer()

                controls
                    .padding(.bottom, 36)
            }

            if case .failed(let message) = session.phase {
                failureView(message)
            }
        }
        .task { await session.start() }
        .onChange(of: session.elapsed) { _, elapsed in
            if elapsed >= session.timeLimit {
                Task { await saveAndDismiss() }
            }
        }
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var addTimeButton: some View {
        if session.phase == .recording || session.phase == .paused {
            Button {
                session.addThirtySeconds()
            } label: {
                Text("Add 30 seconds")
                    .font(.footnote)
                    .foregroundStyle(session.remaining <= 45 ? Theme.secondaryText : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
        } else {
            Text(" ").font(.footnote)
        }
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
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(session.phase == .paused ? "Resume" : "Pause")

            Button {
                Task { await saveAndDismiss() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.white))
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

        let duration = session.elapsed
        let transcript = await session.finish()

        guard !transcript.isEmpty else {
            dismiss()
            return
        }

        let entry = JournalEntry(duration: duration, transcript: transcript)
        context.insert(entry)
        if let replacing {
            context.delete(replacing)
        }
        try? context.save()
        dismiss()

        // The observer reads the entry after the recorder is gone;
        // the timeline updates in place when it has something to say.
        Task { await Reflector.annotate(entry) }
    }
}

/// Tight vertical bars mirrored around the midline, newest on the right.
struct WaveformView: View {
    let levels: [Float]
    let isLive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: 3, height: max(4, CGFloat(level) * 80))
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isLive ? 1 : 0.5)
        .animation(.linear(duration: 0.1), value: levels)
    }
}
