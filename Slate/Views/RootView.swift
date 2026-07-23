import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecorder = false

    var body: some View {
        NavigationStack {
            TimelineScreen()
                .safeAreaInset(edge: .bottom) {
                    recordButton
                        .padding(.bottom, 8)
                }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen()
        }
        .task {
            await WeekComposer.composePendingReviews(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await WeekComposer.composePendingReviews(in: context) }
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
        .accessibilityLabel("Record an entry")
    }
}
