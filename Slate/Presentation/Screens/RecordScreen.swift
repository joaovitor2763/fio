import SwiftUI
import SlateKit

/// Full-screen recorder: waveform, clock, pause, done. Speak; Slate writes.
struct RecordScreen: View {
    /// When set, the new entry replaces this one (the "Re-record" path).
    var replacingEntryID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
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

                Text(Formatting.clock(session.elapsed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
        .onChange(of: session.elapsed) { _, _ in
            if session.isOutOfTime {
                Task { await saveAndDismiss() }
            }
        }
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
                    .foregroundStyle(session.isNearlyOutOfTime ? Theme.secondaryText : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!session.budget.canExtend)
            .animation(.easeInOut(duration: 0.3), value: session.isNearlyOutOfTime)
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
                    .contentTransition(.symbolEffect(.replace))
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
                    .overlay {
                        if isSaving {
                            ProgressView().tint(.black)
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

        let duration = session.elapsed
        let transcriptText = await session.finish()

        await store.finishRecording(
            transcriptText: transcriptText,
            duration: duration,
            replacing: replacingEntryID
        )
        dismiss()
    }
}
