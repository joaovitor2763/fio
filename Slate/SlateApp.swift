import SwiftUI
import SwiftData
import SlateKit

/// Composition root: wires the SwiftData and Apple Intelligence adapters
/// into the domain's ports. Nothing else in the app knows about both sides.
@main
struct SlateApp: App {
    private let container: ModelContainer
    @State private var store: JournalStore

    init() {
        do {
            container = try ModelContainer(for: EntryRecord.self, ReviewRecord.self)
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        let context = container.mainContext
        _store = State(initialValue: JournalStore(
            entryRepository: SwiftDataEntryRepository(context: context),
            reviewRepository: SwiftDataReviewRepository(context: context),
            reflectionService: AppleIntelligenceReflectionService(),
            weekSummaryService: AppleIntelligenceWeekSummaryService()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
