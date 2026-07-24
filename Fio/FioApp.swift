import SwiftUI
import SwiftData
import BackgroundTasks
import FioKit

/// Composition root: wires the SwiftData and Apple Intelligence adapters
/// into the domain's ports. Nothing else in the app knows about both sides.
@main
struct FioApp: App {
    private let container: ModelContainer
    @State private var store: JournalStore
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(InterfaceLanguage.storageKey) private var interfaceLanguage = InterfaceLanguage.english.rawValue

    init() {
        do {
            container = try ModelContainer(
                for: EntryRecord.self,
                ReviewRecord.self,
                TopicRecord.self
            )
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        let context = container.mainContext
        let topicRepository = SwiftDataTopicRepository(context: context)
        let journalStore = JournalStore(
            entryRepository: SwiftDataEntryRepository(context: context),
            reviewRepository: SwiftDataReviewRepository(context: context),
            topicRepository: topicRepository,
            reflectionService: AppleIntelligenceReflectionService(),
            weekSummaryService: AppleIntelligenceWeekSummaryService(),
            topicDiscoveryService: AppleIntelligenceTopicDiscoveryService()
        )
        _store = State(initialValue: journalStore)

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DreamScheduler.identifier,
            using: nil
        ) { task in
            let work = Task { @MainActor in
                await journalStore.runDreamIfNeeded()
                DreamScheduler.schedule()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = {
                work.cancel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, selectedLanguage.locale)
                .preferredColorScheme(selectedAppearance.colorScheme)
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    private var selectedLanguage: InterfaceLanguage {
        InterfaceLanguage(rawValue: interfaceLanguage) ?? .english
    }
}
