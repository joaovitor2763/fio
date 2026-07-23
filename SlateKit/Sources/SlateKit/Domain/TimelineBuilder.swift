import Foundation

/// One day on the timeline, newest entries first.
public struct TimelineDay: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public let day: Date
    public let entries: [Entry]

    public init(day: Date, entries: [Entry]) {
        self.day = day
        self.entries = entries
    }
}

public enum TimelineBuilder {
    /// Groups entries into days, newest day first, newest entry first within a day.
    public static func days(from entries: [Entry], calendar: JournalCalendar) -> [TimelineDay] {
        Dictionary(grouping: entries) { calendar.startOfDay($0.createdAt) }
            .sorted { $0.key > $1.key }
            .map { TimelineDay(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }
}
