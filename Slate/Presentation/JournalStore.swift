import Foundation
import Observation
import SlateKit

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
    private let deleteEntry: DeleteEntryUseCase
    private let composeReviews: ComposeDueReviewsUseCase

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

    // MARK: - Writing

    /// Stores the entry immediately so the timeline updates at once, then
    /// lets the observer read it in the background.
    func finishRecording(transcriptText: String, duration: TimeInterval, replacing replacedID: UUID? = nil) async {
        guard let entry = try? await recordEntry.execute(
            transcriptText: transcriptText,
            duration: duration,
            replacing: replacedID
        ) else { return }
        await refresh()

        annotatingEntryIDs.insert(entry.id)
        Task {
            _ = try? await annotateEntry.execute(entryID: entry.id)
            annotatingEntryIDs.remove(entry.id)
            await refresh()
        }
    }

    func delete(entryID: UUID) async {
        try? await deleteEntry.execute(entryID: entryID)
        await refresh()
    }

    func saveContext(_ text: String, forEntryID id: UUID) async {
        _ = try? await amendContext.execute(entryID: id, context: text)
        await refresh()
    }

    /// Called on launch and whenever the app comes to the foreground.
    func composeDueReviews() async {
        _ = try? await composeReviews.execute()
        await refresh()
    }
}
