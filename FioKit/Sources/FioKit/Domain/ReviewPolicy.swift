import Foundation

/// When a week earns a read-back, and which weeks are owed one.
public struct ReviewPolicy: Sendable {
    /// Fewer entries than this and the week has no shape worth reading back.
    public let minimumEntries: Int
    public let calendar: JournalCalendar

    public init(minimumEntries: Int = 3, calendar: JournalCalendar = JournalCalendar()) {
        self.minimumEntries = minimumEntries
        self.calendar = calendar
    }

    /// A week becomes readable on its own Sunday and stays readable after.
    public func isWeekReadable(weekStart: Date, now: Date) -> Bool {
        let interval = calendar.weekInterval(containing: weekStart)
        if interval.end <= now { return true }
        let sunday = interval.end.addingTimeInterval(-1)
        return calendar.isSameDay(now, sunday)
    }

    public struct DueWeek: Equatable, Sendable {
        public let weekStart: Date
        public let entries: [Entry]
    }

    /// Weeks that have enough entries, are readable, and have no review yet —
    /// oldest first, entries within each week in spoken order.
    public func dueWeeks(
        entries: [Entry],
        existingReviewWeekStarts: [Date],
        now: Date
    ) -> [DueWeek] {
        let grouped = Dictionary(grouping: entries) { calendar.weekStart(containing: $0.createdAt) }
        return grouped
            .filter { $0.value.count >= minimumEntries }
            .filter { isWeekReadable(weekStart: $0.key, now: now) }
            .filter { weekStart, _ in
                !existingReviewWeekStarts.contains { calendar.isSameDay($0, weekStart) }
            }
            .sorted { $0.key < $1.key }
            .map { DueWeek(weekStart: $0.key, entries: $0.value.sorted { $0.createdAt < $1.createdAt }) }
    }
}
