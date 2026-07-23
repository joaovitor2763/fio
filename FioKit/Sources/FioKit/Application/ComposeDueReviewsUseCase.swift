import Foundation

/// On Sunday, Fio reads the week back to you. This finds every week that
/// is owed a review and composes it. Weeks the summarizer stays silent on
/// are skipped and retried next time.
public struct ComposeDueReviewsUseCase: Sendable {
    private let entries: EntryRepository
    private let reviews: ReviewRepository
    private let summarizer: WeekSummaryService
    private let policy: ReviewPolicy

    public static let fallbackTitle = "The week read back"

    public init(
        entries: EntryRepository,
        reviews: ReviewRepository,
        summarizer: WeekSummaryService,
        policy: ReviewPolicy = ReviewPolicy()
    ) {
        self.entries = entries
        self.reviews = reviews
        self.summarizer = summarizer
        self.policy = policy
    }

    @discardableResult
    public func execute(now: Date = .now) async throws -> [WeekReview] {
        let allEntries = try await entries.allEntries()
        guard !allEntries.isEmpty else { return [] }
        let existing = try await reviews.allReviews()

        let due = policy.dueWeeks(
            entries: allEntries,
            existingReviewWeekStarts: existing.map(\.weekStart),
            now: now
        )

        var created: [WeekReview] = []
        for week in due {
            guard let summary = await summarizer.summarize(weekStart: week.weekStart, entries: week.entries),
                  !summary.summary.isEmpty
            else { continue }

            let review = WeekReview(
                weekStart: week.weekStart,
                createdAt: now,
                title: summary.title.isEmpty ? Self.fallbackTitle : summary.title,
                summary: summary.summary,
                dailyMinutes: SpeakingWeek.dailyMinutes(entries: week.entries, calendar: policy.calendar)
            )
            try await reviews.save(review)
            created.append(review)
        }
        return created
    }
}
