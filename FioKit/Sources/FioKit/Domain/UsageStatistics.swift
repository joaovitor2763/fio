import Foundation

/// Private, local-only usage insights derived from journal entries.
public struct UsageStatistics: Equatable, Sendable {
    public let recordingCount: Int
    public let totalWords: Int
    public let totalDuration: TimeInterval
    public let activeDayCount: Int
    public let currentStreak: Int
    public let longestStreak: Int
    public let longestRecording: TimeInterval
    public let peakHour: Int?
    public let hourlyRecordingCounts: [Int]
    public let durationByDay: [Date: TimeInterval]

    public static func calculate(
        entries: [Entry],
        calendar: JournalCalendar = JournalCalendar(),
        now: Date = .now
    ) -> UsageStatistics {
        var totalWords = 0
        var totalDuration: TimeInterval = 0
        var longestRecording: TimeInterval = 0
        var hourlyRecordingCounts = Array(repeating: 0, count: 24)
        var durationByDay: [Date: TimeInterval] = [:]

        for entry in entries {
            totalWords += entry.transcript.wordCount
            totalDuration += entry.duration
            longestRecording = max(longestRecording, entry.duration)

            let hour = calendar.calendar.component(.hour, from: entry.createdAt)
            hourlyRecordingCounts[hour] += 1

            let day = calendar.startOfDay(entry.createdAt)
            durationByDay[day, default: 0] += entry.duration
        }

        let activeDays = durationByDay.keys.sorted()
        let peakHour = hourlyRecordingCounts.max().flatMap { maximum in
            maximum > 0 ? hourlyRecordingCounts.firstIndex(of: maximum) : nil
        }

        return UsageStatistics(
            recordingCount: entries.count,
            totalWords: totalWords,
            totalDuration: totalDuration,
            activeDayCount: activeDays.count,
            currentStreak: currentStreak(
                activeDays: Set(activeDays),
                calendar: calendar,
                now: now
            ),
            longestStreak: longestStreak(
                activeDays: activeDays,
                calendar: calendar
            ),
            longestRecording: longestRecording,
            peakHour: peakHour,
            hourlyRecordingCounts: hourlyRecordingCounts,
            durationByDay: durationByDay
        )
    }

    private static func currentStreak(
        activeDays: Set<Date>,
        calendar: JournalCalendar,
        now: Date
    ) -> Int {
        let today = calendar.startOfDay(now)
        let yesterday = calendar.calendar.date(byAdding: .day, value: -1, to: today)!

        var cursor: Date
        if activeDays.contains(today) {
            cursor = today
        } else if activeDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while activeDays.contains(cursor) {
            count += 1
            cursor = calendar.calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    private static func longestStreak(
        activeDays: [Date],
        calendar: JournalCalendar
    ) -> Int {
        guard let first = activeDays.first else { return 0 }
        var longest = 1
        var current = 1
        var previous = first

        for day in activeDays.dropFirst() {
            let expected = calendar.calendar.date(byAdding: .day, value: 1, to: previous)!
            if calendar.isSameDay(day, expected) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
            previous = day
        }
        return longest
    }
}
