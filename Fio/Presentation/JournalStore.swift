import Foundation
import Observation
import FioKit

/// The presentation-side face of the journal. Views read snapshots of the
/// domain from here and never touch persistence or the model directly.
@MainActor
@Observable
final class JournalStore {
    // Mutated only by the store's scoped extensions. Views consume snapshots.
    var timeline: [TimelineDay] = []
    var reviews: [WeekReview] = []
    var topics: [Topic] = []
    /// Entries the observer is currently reading, for the subtle indicator.
    var annotatingEntryIDs: Set<UUID> = []
    var isDreaming = false
    var isComposingReviews = false
    var isLoaded = false
    var loadErrorMessage: String?
    var maintenanceErrorMessage: String?
    var hasTopicMaintenanceError = false
    var hasReviewMaintenanceError = false
    var isReviewSnapshotReady = false
    var daysWithEntries: Set<Date> = []
    var usageStatistics = UsageStatistics.calculate(entries: [])
    var isUsageStatisticsReady = false

    let calendar = JournalCalendar()

    let entryRepository: EntryRepository
    let reviewRepository: ReviewRepository
    let topicRepository: TopicRepository
    let topicDiscoveryService: TopicDiscoveryService
    let recordEntry: RecordEntryUseCase
    let annotateEntry: AnnotateEntryUseCase
    let amendContext: AmendEntryContextUseCase
    let replaceTranscript: ReplaceEntryTranscriptUseCase
    let replaceReflection: ReplaceEntryReflectionUseCase
    let deleteEntry: DeleteEntryUseCase
    let composeReviews: ComposeDueReviewsUseCase
    let migrateLegacyTags: MigrateLegacyTagsUseCase
    let replaceEntryTopics: ReplaceEntryTopicsUseCase
    let saveDreamSuggestions: SaveDreamSuggestionsUseCase
    let resolveTopicSuggestion: ResolveTopicSuggestionUseCase
    let removeEntryFromTopics: RemoveEntryFromTopicsUseCase
    let reconcileTopicMemberships: ReconcileTopicMembershipsUseCase
    let refreshLock = AsyncMutationLock()
    let reviewMutationLock = AsyncMutationLock()
    let topicMutationLock = AsyncMutationLock()
    var entries: [Entry] = []
    var entriesByID: [UUID: Entry] = [:]
    var acceptedTopicsCache: [Topic] = []
    var acceptedTopicsByEntryID: [UUID: [Topic]] = [:]
    var searchDocuments: [SearchDocument] = []
    var pendingReflectionStyles: [UUID: ReflectionStyle] = [:]
    var didMigrateLegacyTags = false
    var entrySnapshotRevision = 0
    var usageStatisticsTask: Task<Void, Never>?
    var usageStatisticsCalculationTask: Task<UsageStatistics?, Never>?
    var usageStatisticsGeneration = 0

    init(
        entryRepository: EntryRepository,
        reviewRepository: ReviewRepository,
        topicRepository: TopicRepository,
        reflectionService: ReflectionService,
        weekSummaryService: WeekSummaryService,
        topicDiscoveryService: TopicDiscoveryService
    ) {
        self.entryRepository = entryRepository
        self.reviewRepository = reviewRepository
        self.topicRepository = topicRepository
        self.topicDiscoveryService = topicDiscoveryService
        recordEntry = RecordEntryUseCase(entries: entryRepository)
        annotateEntry = AnnotateEntryUseCase(entries: entryRepository, reflector: reflectionService)
        amendContext = AmendEntryContextUseCase(entries: entryRepository)
        replaceTranscript = ReplaceEntryTranscriptUseCase(entries: entryRepository)
        replaceReflection = ReplaceEntryReflectionUseCase(entries: entryRepository)
        deleteEntry = DeleteEntryUseCase(entries: entryRepository)
        composeReviews = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: reviewRepository,
            summarizer: weekSummaryService,
            policy: ReviewPolicy(calendar: calendar)
        )
        migrateLegacyTags = MigrateLegacyTagsUseCase(
            entries: entryRepository,
            topics: topicRepository
        )
        replaceEntryTopics = ReplaceEntryTopicsUseCase(
            entries: entryRepository,
            topics: topicRepository
        )
        saveDreamSuggestions = SaveDreamSuggestionsUseCase(
            entries: entryRepository,
            topics: topicRepository
        )
        resolveTopicSuggestion = ResolveTopicSuggestionUseCase(topics: topicRepository)
        removeEntryFromTopics = RemoveEntryFromTopicsUseCase(topics: topicRepository)
        reconcileTopicMemberships = ReconcileTopicMembershipsUseCase(
            entries: entryRepository,
            topics: topicRepository
        )
    }

    // MARK: - Reading

    func refresh() async {
        await refreshLock.acquire()
        await PerformanceRecorder.measure("journal_refresh") {
            do {
                try await loadAndApplyStableEntrySnapshot()
                loadErrorMessage = nil
                isLoaded = true
            } catch {
                isLoaded = false
                loadErrorMessage = String(
                    localized: "Fio could not open your journal. Your entries remain on this iPhone."
                )
                if !didMigrateLegacyTags {
                    // A failed migration remains retryable on the next refresh.
                    didMigrateLegacyTags = false
                }
                return
            }
            await refreshAuxiliarySnapshots()
            prepareUsageStatistics()
        }
        await refreshLock.release()
    }

    func entry(withID id: UUID) -> Entry? {
        entriesByID[id]
    }

    func review(withID id: UUID) -> WeekReview? {
        reviews.first { $0.id == id }
    }

    var latestReview: WeekReview? { reviews.first }

    var acceptedTopics: [Topic] {
        acceptedTopicsCache
    }

    var pendingTopicSuggestion: Topic? {
        topics
            .filter { $0.status == .suggested && $0.entryIDs.count >= 2 }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func topic(withID id: UUID) -> Topic? {
        topics.first { $0.id == id }
    }

    func topics(forEntryID id: UUID) -> [Topic] {
        acceptedTopicsByEntryID[id] ?? []
    }

    func topicSuggestions(forEntryID id: UUID) -> [Topic] {
        topics.filter { $0.status == .suggested && $0.contains(entryID: id) }
    }

    func entries(forTopicID id: UUID) -> [Entry] {
        guard let topic = topic(withID: id) else { return [] }
        return topic.entryIDs
            .compactMap { entriesByID[$0] }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Searches a pre-normalized, in-memory index. All matching stays on-device.
    func searchEntries(matching query: String, topicID: UUID? = nil) -> [Entry] {
        let terms = normalizedSearchText(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let topicEntryIDs: Set<UUID>?
        if let topicID {
            guard let topic = topic(withID: topicID) else { return [] }
            topicEntryIDs = Set(topic.entryIDs)
        } else {
            topicEntryIDs = nil
        }
        guard !terms.isEmpty || topicEntryIDs != nil else { return [] }

        return searchDocuments.compactMap { document in
            guard topicEntryIDs?.contains(document.entry.id) ?? true else { return nil }
            return terms.allSatisfy(document.content.contains) ? document.entry : nil
        }
    }

    func prepareUsageStatistics() {
        usageStatisticsTask?.cancel()
        usageStatisticsCalculationTask?.cancel()
        usageStatisticsGeneration &+= 1
        let generation = usageStatisticsGeneration
        let snapshot = entries
        let revision = entrySnapshotRevision
        if snapshot.isEmpty {
            usageStatistics = UsageStatistics.calculate(
                entries: [],
                calendar: calendar
            )
            isUsageStatisticsReady = true
            return
        }

        usageStatisticsTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let calendar = calendar
            let calculation = Task.detached(priority: .utility) {
                UsageStatistics.calculateUnlessCancelled(
                    entries: snapshot,
                    calendar: calendar
                )
            }
            usageStatisticsCalculationTask = calculation
            let statistics = await PerformanceRecorder.measure(
                "usage_statistics_build"
            ) {
                await calculation.value
            }
            guard !Task.isCancelled,
                  generation == usageStatisticsGeneration,
                  entrySnapshotRevision == revision,
                  let statistics else {
                return
            }
            usageStatisticsCalculationTask = nil
            usageStatistics = statistics
            isUsageStatisticsReady = true
        }
    }
}
