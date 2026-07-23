import Foundation

/// Slate's notion of time: weeks run Monday through Sunday,
/// and the review lands on Sunday.
public struct JournalCalendar: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// Monday 00:00 of the week containing `date`.
    public func weekStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(date)
    }

    public func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: startOfDay(date), duration: 7 * 24 * 3600)
    }

    /// The seven days of the week containing `date`, Monday first.
    public func weekDays(containing date: Date) -> [Date] {
        let start = weekStart(containing: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Monday = 0 … Sunday = 6.
    public func weekdayIndex(of date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    public func isSunday(_ date: Date) -> Bool {
        weekdayIndex(of: date) == 6
    }

    public func dayNumber(of date: Date) -> Int {
        calendar.component(.day, from: date)
    }
}
