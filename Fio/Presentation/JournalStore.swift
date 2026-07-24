import Foundation
import Observation
import FioKit

/// The presentation-side face of the journal. Views read snapshots of the
/// domain from here and never touch persistence or the model directly.
@MainActor
@Observable
final class JournalStore {
    private(set) var timeline: [TimelineDay] = []
    private(set) var reviews: [WeekReview] = []
    private(set) var topics: [Topic] = []
    /// Entries the observer is currently reading, for the subtle indicator.
    private(set) var annotatingEntryIDs: Set<UUID> = []
    private(set) var isDreaming = false
    private(set) var isLoaded = false

    let calendar = JournalCalendar()

    private let entryRepository: EntryRepository
    private let reviewRepository: ReviewRepository
    private let topicRepository: TopicRepository
    private let topicDiscoveryService: TopicDiscoveryService
    private let recordEntry: RecordEntryUseCase
    private let annotateEntry: AnnotateEntryUseCase
    private let amendContext: AmendEntryContextUseCase
    private let replaceTranscript: ReplaceEntryTranscriptUseCase
    private let replaceReflection: ReplaceEntryReflectionUseCase
    private let deleteEntry: DeleteEntryUseCase
    private let composeReviews: ComposeDueReviewsUseCase
    private let migrateLegacyTags: MigrateLegacyTagsUseCase
    private let replaceEntryTopics: ReplaceEntryTopicsUseCase
    private let saveDreamSuggestions: SaveDreamSuggestionsUseCase
    private let resolveTopicSuggestion: ResolveTopicSuggestionUseCase
    private let removeEntryFromTopics: RemoveEntryFromTopicsUseCase
    private let reconcileTopicMemberships: ReconcileTopicMembershipsUseCase
    private let topicMutationLock = AsyncMutationLock()
    private var searchDocuments: [SearchDocument] = []
    private var pendingReflectionStyles: [UUID: ReflectionStyle] = [:]
    private var didMigrateLegacyTags = false

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
        let entries = (try? await entryRepository.allEntries()) ?? []
        await withTopicMutation {
            if !didMigrateLegacyTags {
                if LegacyTopicMigrationState.isComplete {
                    didMigrateLegacyTags = true
                } else {
                    do {
                        try await migrateLegacyTags.execute()
                        LegacyTopicMigrationState.markComplete()
                        didMigrateLegacyTags = true
                    } catch {
                        // A transient store failure retries on the next refresh.
                    }
                }
            }
            try? await reconcileTopicMemberships.execute()
        }
        let allTopics = (try? await topicRepository.allTopics()) ?? []
        topics = allTopics.sorted {
            if $0.status != $1.status {
                return $0.status == .suggested
            }
            return $0.updatedAt > $1.updatedAt
        }
        timeline = TimelineBuilder.days(from: entries, calendar: calendar)
        let topicNamesByEntry = Dictionary(grouping: allTopics.filter {
            $0.status == .accepted
        }.flatMap { topic in
            topic.entryIDs.map { ($0, topic.name) }
        }, by: \.0)
        .mapValues { pairs in pairs.map(\.1) }
        searchDocuments = entries
            .sorted { $0.createdAt > $1.createdAt }
            .map {
                SearchDocument(
                    entry: $0,
                    topicNames: topicNamesByEntry[$0.id] ?? []
                )
            }
        let allReviews = (try? await reviewRepository.allReviews()) ?? []
        reviews = allReviews.sorted { $0.weekStart > $1.weekStart }
        isLoaded = true
    }

    func entry(withID id: UUID) -> Entry? {
        for day in timeline {
            if let entry = day.entries.first(where: { $0.id == id }) { return entry }
        }
        return nil
    }

    func review(withID id: UUID) -> WeekReview? {
        reviews.first { $0.id == id }
    }

    var latestReview: WeekReview? { reviews.first }

    var acceptedTopics: [Topic] {
        topics
            .filter { $0.status == .accepted }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
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
        acceptedTopics.filter { $0.contains(entryID: id) }
    }

    func topicSuggestions(forEntryID id: UUID) -> [Topic] {
        topics.filter { $0.status == .suggested && $0.contains(entryID: id) }
    }

    func entries(forTopicID id: UUID) -> [Entry] {
        guard let topic = topic(withID: id) else { return [] }
        return topic.entryIDs
            .compactMap(entry(withID:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    var daysWithEntries: Set<Date> { Set(timeline.map(\.day)) }

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

    var usageStatistics: UsageStatistics {
        UsageStatistics.calculate(
            entries: timeline.flatMap(\.entries),
            calendar: calendar
        )
    }

    // MARK: - Writing

    /// Stores the entry immediately so the timeline updates at once, then
    /// lets the observer read it in the background.
    func finishRecording(
        transcriptText: String,
        duration: TimeInterval,
        audioFileName: String?,
        replacing replacedID: UUID? = nil,
        applyPersonalVocabulary: Bool = false
    ) async {
        let replacedAudioFileName = replacedID.flatMap { entry(withID: $0)?.audioFileName }
        let textToSave = applyPersonalVocabulary
            ? PersonalVocabulary.apply(to: transcriptText).text
            : transcriptText

        let savedEntry: Entry
        do {
            guard let saved = try await recordEntry.execute(
                transcriptText: textToSave,
                duration: duration,
                audioFileName: audioFileName,
                replacing: replacedID
            ) else {
                AudioFileStore.deleteFile(named: audioFileName)
                return
            }
            savedEntry = saved
        } catch {
            AudioFileStore.deleteFile(named: audioFileName)
            return
        }

        if replacedAudioFileName != audioFileName {
            AudioFileStore.deleteFile(named: replacedAudioFileName)
        }
        DreamScheduleState.markNeedsAnalysis()
        await refresh()

        Task {
            await regenerateReflection(entryID: savedEntry.id)
        }
    }

    func delete(entryID: UUID) async {
        let audioFileName = entry(withID: entryID)?.audioFileName
        do {
            try await deleteEntry.execute(entryID: entryID)
        } catch {
            return
        }

        // Entry deletion is already committed. Topic cleanup is best-effort,
        // but audio and the in-memory timeline must always follow the entry.
        try? await withTopicMutation {
            try await removeEntryFromTopics.execute(entryID: entryID)
        }
        AudioFileStore.deleteFile(named: audioFileName)
        DreamScheduleState.markNeedsAnalysis()
        await refresh()
    }

    func saveContext(_ text: String, forEntryID id: UUID) async {
        _ = try? await amendContext.execute(entryID: id, context: text)
        DreamScheduleState.markNeedsAnalysis()
        await refresh()
    }

    func saveTranscript(_ text: String, forEntryID id: UUID) async throws {
        guard try await replaceTranscript.execute(
            entryID: id,
            transcriptText: text
        ) != nil else {
            throw JournalStoreError.transcriptionUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        await refresh()
        Task {
            await regenerateReflection(entryID: id)
        }
    }

    func saveReflection(
        headline: String,
        observations: [String],
        forEntryID id: UUID
    ) async throws {
        guard try await replaceReflection.execute(
            entryID: id,
            headline: headline,
            observations: observations
        ) != nil else {
            throw JournalStoreError.entryUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        await refresh()
    }

    func saveTopics(_ names: [String], forEntryID id: UUID) async throws {
        DreamScheduleState.markNeedsAnalysis()
        guard try await withTopicMutation({
            try await replaceEntryTopics.execute(entryID: id, names: names)
        }) != nil else {
            throw JournalStoreError.entryUnavailable
        }
        await refresh()
    }

    @discardableResult
    func acceptTopicSuggestion(
        _ topicID: UUID,
        renamedTo name: String? = nil
    ) async -> Topic? {
        DreamScheduleState.markNeedsAnalysis()
        let accepted = try? await withTopicMutation {
            try await resolveTopicSuggestion.accept(
                topicID: topicID,
                renamedTo: name
            )
        }
        await refresh()
        return accepted
    }

    @discardableResult
    func dismissTopicSuggestion(_ topicID: UUID) async -> Bool {
        DreamScheduleState.markNeedsAnalysis()
        do {
            try await withTopicMutation {
                try await resolveTopicSuggestion.dismiss(topicID: topicID)
            }
            await refresh()
            return true
        } catch {
            return false
        }
    }

    func regenerateReflection(
        entryID: UUID,
        style: ReflectionStyle = .standard
    ) async {
        guard !annotatingEntryIDs.contains(entryID) else {
            pendingReflectionStyles[entryID] = style
            return
        }

        annotatingEntryIDs.insert(entryID)
        var nextStyle: ReflectionStyle? = style
        while let currentStyle = nextStyle {
            _ = try? await annotateEntry.execute(
                entryID: entryID,
                style: currentStyle,
                guidance: ObserverPreferences.guidance
            )
            DreamScheduleState.markNeedsAnalysis()
            await refresh()
            nextStyle = pendingReflectionStyles.removeValue(forKey: entryID)
        }
        annotatingEntryIDs.remove(entryID)
    }

    /// Reprocesses the preserved audio with a different language without
    /// changing the language preference used for future recordings.
    func retranscribe(entryID: UUID, locale: Locale) async throws {
        guard let fileName = entry(withID: entryID)?.audioFileName else {
            throw JournalStoreError.audioUnavailable
        }

        let transcript = try await AudioRetranscriptionService.transcribe(
            fileName: fileName,
            locale: locale
        )
        let correctedTranscript = PersonalVocabulary.apply(to: transcript).text
        guard let updated = try await replaceTranscript.execute(
            entryID: entryID,
            transcriptText: correctedTranscript
        ) else {
            throw JournalStoreError.transcriptionUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        await refresh()

        Task {
            await regenerateReflection(entryID: updated.id)
        }
    }

    /// Called on launch and whenever the app comes to the foreground.
    func composeDueReviews() async {
        _ = try? await composeReviews.execute()
        await refresh()
    }

    /// Opportunistically consolidates recent entries using only the on-device
    /// model. Work is idempotent and safe to resume after background expiry.
    func runDreamIfNeeded() async {
        guard !isDreaming else { return }
        isDreaming = true
        var retryAfterCorpusChange = false
        defer {
            isDreaming = false
            if retryAfterCorpusChange {
                Task { await self.runDreamIfNeeded() }
            }
        }

        let entries = (try? await entryRepository.allEntries()) ?? []
        let substantialEntries = entries.filter { $0.transcript.isSubstantial }
        let latestEntryDate = substantialEntries.map(\.createdAt).max() ?? .distantPast
        guard DreamScheduleState.needsAnalysis(latestEntryDate: latestEntryDate) else {
            return
        }
        let corpusRevision = DreamScheduleState.currentRevision

        if substantialEntries.count < 2 {
            do {
                _ = try await withTopicMutation {
                    try await saveDreamSuggestions.execute(candidates: [])
                }
                guard DreamScheduleState.markAnalyzed(
                    through: latestEntryDate,
                    ifRevisionIs: corpusRevision
                ) else {
                    retryAfterCorpusChange = true
                    return
                }
                await refresh()
            } catch {
                // Leave the revision stale so a later pass retries cleanup.
            }
            return
        }

        let allTopics = (try? await topicRepository.allTopics()) ?? []
        guard let candidates = await topicDiscoveryService.discoverTopics(
            in: substantialEntries,
            existingTopics: allTopics
        ) else {
            return
        }
        guard DreamScheduleState.currentRevision == corpusRevision else {
            retryAfterCorpusChange = true
            return
        }

        do {
            _ = try await withTopicMutation {
                try await saveDreamSuggestions.execute(candidates: candidates)
            }
            guard DreamScheduleState.markAnalyzed(
                through: latestEntryDate,
                ifRevisionIs: corpusRevision
            ) else {
                retryAfterCorpusChange = true
                return
            }
            await refresh()
        } catch {
            // Leave the Dream stale so a later foreground or background pass retries.
        }
    }

    private func withTopicMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await topicMutationLock.acquire()
        do {
            let result = try await operation()
            await topicMutationLock.release()
            return result
        } catch {
            await topicMutationLock.release()
            throw error
        }
    }

}

/// Actor reentrancy alone does not serialize a transaction across suspension
/// points. This FIFO lock protects each complete topic read/modify/commit.
private actor AsyncMutationLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private struct SearchDocument {
    let entry: Entry
    let content: String

    init(entry: Entry, topicNames: [String]) {
        self.entry = entry
        content = normalizedSearchText(
            [
                entry.transcript.text,
                entry.reflection.headline,
                entry.reflection.observations.joined(separator: " "),
                entry.reflection.tags.joined(separator: " "),
                topicNames.joined(separator: " "),
                entry.authorContext,
            ]
            .joined(separator: " ")
        )
    }
}

private func normalizedSearchText(_ text: String) -> String {
    text
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
}

private enum JournalStoreError: LocalizedError {
    case audioUnavailable
    case entryUnavailable
    case transcriptionUnavailable

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            "The original audio is no longer available."
        case .entryUnavailable:
            "This entry is no longer available."
        case .transcriptionUnavailable:
            "Fio could not replace this transcription."
        }
    }
}
