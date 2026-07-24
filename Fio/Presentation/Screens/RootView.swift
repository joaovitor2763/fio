import SwiftUI
import FioKit

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigationNamespace
    @State private var showRecorder = false
    @State private var showTextEntry = false
    @State private var isRecordButtonPressed = false
    @State private var isTextEntryArmed = false
    @State private var utilityDestination: UtilityDestination?
    @State private var holdActivationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            timelineNavigation
                .accessibilityHidden(utilityDestination != nil)
                .allowsHitTesting(utilityDestination == nil)

            if let utilityDestination {
                utilityScreen(utilityDestination)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen()
        }
        .fullScreenCover(isPresented: $showTextEntry) {
            TextEntryScreen()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: utilityDestination) { oldValue, newValue in
            oldValue == nil && newValue != nil
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

    private var timelineNavigation: some View {
        NavigationStack {
            TimelineScreen(navigationNamespace: navigationNamespace)
                .navigationDestination(for: Route.self) { route in
                    routeScreen(route)
                }
                .safeAreaInset(edge: .bottom) {
                    if utilityDestination == nil {
                        bottomActions
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 42) {
            Button {
                presentUtility(.insights)
            } label: {
                secondaryAction(systemName: "person.crop.circle")
            }
            .buttonStyle(UtilityActionButtonStyle())
            .accessibilityLabel("Fio profile and insights")

            recordButton

            Button {
                presentUtility(.reviews)
            } label: {
                secondaryAction(systemName: "book.pages")
            }
            .buttonStyle(UtilityActionButtonStyle())
            .accessibilityLabel("Weekly reviews")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func utilityScreen(_ destination: UtilityDestination) -> some View {
        NavigationStack {
            switch destination {
            case .insights:
                InsightsScreen()
                    .toolbar { utilityCloseToolbar }
            case .reviews:
                ReviewListScreen(navigationNamespace: navigationNamespace)
                    .toolbar { utilityCloseToolbar }
                    .navigationDestination(for: Route.self) { route in
                        routeScreen(route)
                    }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func routeScreen(_ route: Route) -> some View {
        switch route {
        case .entry(let id):
            EntryDetailScreen(entryID: id)
                .contextualNavigationTransition(
                    sourceID: route,
                    in: navigationNamespace,
                    reduceMotion: reduceMotion
                )
        case .review(let id, _):
            if let review = store.review(withID: id) {
                ReviewScreen(review: review)
                    .contextualNavigationTransition(
                        sourceID: route,
                        in: navigationNamespace,
                        reduceMotion: reduceMotion
                    )
            }
        }
    }

    @ToolbarContentBuilder
    private var utilityCloseToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismissUtility()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
    }

    private func presentUtility(_ destination: UtilityDestination) {
        withAnimation(reduceMotion ? Motion.quick : Motion.standard) {
            utilityDestination = destination
        }
    }

    private func dismissUtility() {
        withAnimation(reduceMotion ? Motion.quick : Motion.standard) {
            utilityDestination = nil
        }
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

                withAnimation(Motion.quick) {
                    isRecordButtonPressed = true
                }

                holdActivationTask?.cancel()
                holdActivationTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled, isRecordButtonPressed else { return }

                    withAnimation(Motion.contextual) {
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

                withAnimation(Motion.quick) {
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

private enum UtilityDestination: Equatable {
    case insights
    case reviews
}
