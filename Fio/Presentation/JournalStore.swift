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
    /// Entries the observer is currently reading, for the subtle indicator.
    private(set) var annotatingEntryIDs: Set<UUID> = []
    private(set) var isLoaded = false

    let calendar = JournalCalendar()

    private let entryRepository: EntryRepository
    private let reviewRepository: ReviewRepository
    private let recordEntry: RecordEntryUseCase
    private let annotateEntry: AnnotateEntryUseCase
    private let amendContext: AmendEntryContextUseCase
    private let replaceTranscript: ReplaceEntryTranscriptUseCase
    private let replaceReflection: ReplaceEntryReflectionUseCase
    private let deleteEntry: DeleteEntryUseCase
    private let composeReviews: ComposeDueReviewsUseCase
    private var searchDocuments: [SearchDocument] = []
    private var pendingReflectionStyles: [UUID: ReflectionStyle] = [:]

    init(
        entryRepository: EntryRepository,
        reviewRepository: ReviewRepository,
        reflectionService: ReflectionService,
        weekSummaryService: WeekSummaryService
    ) {
        self.entryRepository = entryRepository
        self.reviewRepository = reviewRepository
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
    }

    // MARK: - Reading

    func refresh() async {
        let entries = (try? await entryRepository.allEntries()) ?? []
        timeline = TimelineBuilder.days(from: entries, calendar: calendar)
        searchDocuments = entries
            .sorted { $0.createdAt > $1.createdAt }
            .map(SearchDocument.init)
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

    var daysWithEntries: Set<Date> { Set(timeline.map(\.day)) }

    /// Searches a pre-normalized, in-memory index. All matching stays on-device.
    func searchEntries(matching query: String) -> [Entry] {
        let terms = normalizedSearchText(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        return searchDocuments.compactMap { document in
            terms.allSatisfy(document.content.contains) ? document.entry : nil
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
        await refresh()

        Task {
            await regenerateReflection(entryID: savedEntry.id)
        }
    }

    func delete(entryID: UUID) async {
        let audioFileName = entry(withID: entryID)?.audioFileName
        do {
            try await deleteEntry.execute(entryID: entryID)
            AudioFileStore.deleteFile(named: audioFileName)
            await refresh()
        } catch {
            return
        }
    }

    func saveContext(_ text: String, forEntryID id: UUID) async {
        _ = try? await amendContext.execute(entryID: id, context: text)
        await refresh()
    }

    func saveTranscript(_ text: String, forEntryID id: UUID) async throws {
        guard try await replaceTranscript.execute(
            entryID: id,
            transcriptText: text
        ) != nil else {
            throw JournalStoreError.transcriptionUnavailable
        }
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
        await refresh()
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

}

private struct SearchDocument {
    let entry: Entry
    let content: String

    init(entry: Entry) {
        self.entry = entry
        content = normalizedSearchText(
            [
                entry.transcript.text,
                entry.reflection.headline,
                entry.reflection.observations.joined(separator: " "),
                entry.reflection.tags.joined(separator: " "),
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
