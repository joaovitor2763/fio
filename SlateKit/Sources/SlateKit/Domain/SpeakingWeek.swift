import Foundation

public enum SpeakingWeek {
    /// Minutes spoken per day, Monday through Sunday — the review's sparkline.
    public static func dailyMinutes(entries: [Entry], calendar: JournalCalendar) -> [Double] {
        var minutes = [Double](repeating: 0, count: 7)
        for entry in entries {
            minutes[calendar.weekdayIndex(of: entry.createdAt)] += entry.duration / 60
        }
        return minutes
    }
}
