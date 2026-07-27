import SwiftUI
import SwiftData
import BackgroundTasks
import FioKit

/// Composition root: wires the SwiftData and Apple Intelligence adapters
/// into the domain's ports. Nothing else in the app knows about both sides.
@main
struct FioApp: App {
    private let container: ModelContainer?
    @State private var store: JournalStore?
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(InterfaceLanguage.storageKey) private var interfaceLanguage = InterfaceLanguage.english.rawValue

    init() {
        PerformanceRecorder.beginLaunch()
        let persistentContainer: ModelContainer
        do {
            persistentContainer = try ModelContainer(
                for: EntryRecord.self,
                ReviewRecord.self,
                TopicRecord.self
            )
        } catch {
            container = nil
            _store = State(initialValue: nil)
            return
        }
        container = persistentContainer
        let context = persistentContainer.mainContext
#if DEBUG
        PerformanceFixture.seedIfRequested(in: context)
#endif
        let topicRepository = SwiftDataTopicRepository(context: context)
        let journalStore = JournalStore(
            entryRepository: SwiftDataEntryRepository(context: context),
            reviewRepository: SwiftDataReviewRepository(context: context),
            topicRepository: topicRepository,
            backupService: JournalBackupService(context: context),
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
            Group {
                if let store {
                    RootView()
                        .environment(store)
                } else {
                    JournalUnavailableView()
                }
            }
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

private struct JournalUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)

            Text("Fio could not open your journal")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            Text("Your entries remain on this iPhone. Close and reopen Fio to try again.")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
