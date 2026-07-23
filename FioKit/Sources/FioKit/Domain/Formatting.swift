import Foundation

/// The few time formats Fio shows, kept here so they are testable.
public enum Formatting {
    /// "1:53" — the running clock on the record screen.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "1m 34s" — the duration style on timeline cards.
    public static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return minutes == 0 ? "\(seconds)s" : "\(minutes)m \(seconds)s"
    }

    /// 13 -> "th", 21 -> "st", 12 -> "th"
    public static func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// "Mon July 13th, 2026" — the entry screen title.
    public static func entryTitle(
        for date: Date,
        calendar: JournalCalendar = JournalCalendar(),
        locale: Locale = .current
    ) -> String {
        let base = Date.FormatStyle(
            locale: locale,
            calendar: calendar.calendar,
            timeZone: calendar.calendar.timeZone
        )
        let weekday = date.formatted(base.weekday(.abbreviated))
        let month = date.formatted(base.month(.wide))
        let day = calendar.dayNumber(of: date)
        let year = calendar.calendar.component(.year, from: date)
        return "\(weekday) \(month) \(day)\(ordinalSuffix(day)), \(year)"
    }
}
