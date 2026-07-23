import SwiftUI
import FioKit

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecorder = false
    @State private var showTextEntry = false
    @State private var isRecordButtonPressed = false
    @State private var isTextEntryArmed = false
    @State private var holdActivationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            TimelineScreen()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .entry(let id):
                        EntryDetailScreen(entryID: id)
                    case .review(let id):
                        if let review = store.review(withID: id) {
                            ReviewScreen(review: review)
                        }
                    case .reviewList:
                        ReviewListScreen()
                    case .insights:
                        InsightsScreen()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomActions
                        .padding(.bottom, 8)
                }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen()
        }
        .fullScreenCover(isPresented: $showTextEntry) {
            TextEntryScreen()
        }
        .task {
            async let preloadAssets: Void = RecordingSession.preloadTranscriptionAssets()
            await store.refresh()
            await store.composeDueReviews()
            await preloadAssets
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.composeDueReviews() }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 42) {
            NavigationLink(value: Route.insights) {
                secondaryAction(systemName: "person.crop.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fio profile and insights")

            recordButton

            NavigationLink(value: Route.reviewList) {
                secondaryAction(systemName: "book.pages")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Weekly reviews")
        }
        .frame(maxWidth: .infinity)
    }

    private var recordButton: some View {
        Image(systemName: isTextEntryArmed ? "pencil.tip" : "mic.fill")
                .font(.title2)
                .foregroundStyle(Theme.primaryControlForeground)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.primaryControlBackground))
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isRecordButtonPressed ? 0.94 : 1)
        .glassEffect(.regular.interactive(), in: .circle)
        .contentShape(Circle())
        .gesture(recordButtonGesture)
        .sensoryFeedback(.impact(weight: .medium), trigger: isTextEntryArmed) { old, new in
            !old && new
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Record an entry")
        .accessibilityHint("Touch and hold to write instead")
        .accessibilityAction {
            showRecorder = true
        }
        .accessibilityAction(named: "Write an entry") {
            showTextEntry = true
        }
    }

    private var recordButtonGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isRecordButtonPressed else { return }

                withAnimation(.easeOut(duration: 0.12)) {
                    isRecordButtonPressed = true
                }

                holdActivationTask?.cancel()
                holdActivationTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled, isRecordButtonPressed else { return }

                    withAnimation(.spring(duration: 0.22, bounce: 0.25)) {
                        isTextEntryArmed = true
                    }
                }
            }
            .onEnded { value in
                holdActivationTask?.cancel()
                holdActivationTask = nil

                let stayedNearButton =
                    abs(value.translation.width) < 72 &&
                    abs(value.translation.height) < 72
                let shouldWrite = isTextEntryArmed && stayedNearButton

                withAnimation(.easeOut(duration: 0.14)) {
                    isRecordButtonPressed = false
                    isTextEntryArmed = false
                }

                guard stayedNearButton else { return }
                if shouldWrite {
                    showTextEntry = true
                } else {
                    showRecorder = true
                }
            }
    }

    private func secondaryAction(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.secondaryText.opacity(0.72))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
