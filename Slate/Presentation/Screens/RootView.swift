import SwiftUI
import SlateKit

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecorder = false

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
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    recordButton
                        .padding(.bottom, 8)
                }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen()
        }
        .task {
            await store.refresh()
            await store.composeDueReviews()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.composeDueReviews() }
        }
    }

    private var recordButton: some View {
        Button {
            showRecorder = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .sensoryFeedback(.impact(weight: .medium), trigger: showRecorder) { _, new in new }
        .accessibilityLabel("Record an entry")
    }
}
