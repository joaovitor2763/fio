import XCTest
@testable import FioKit

final class UsageStatisticsTests: XCTestCase {
    func testTotalsAndPeakHour() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 21, 8), duration: 60, words: 10),
            makeEntry(createdAt: date(2026, 7, 21, 8, 30), duration: 120, words: 20),
            makeEntry(createdAt: date(2026, 7, 22, 19), duration: 30, words: 5),
        ]

        let statistics = UsageStatistics.calculate(
            entries: entries,
            calendar: utc,
            now: date(2026, 7, 23)
        )

        XCTAssertEqual(statistics.recordingCount, 3)
        XCTAssertEqual(statistics.totalWords, 35)
        XCTAssertEqual(statistics.totalDuration, 210)
        XCTAssertEqual(statistics.activeDayCount, 2)
        XCTAssertEqual(statistics.longestRecording, 120)
        XCTAssertEqual(statistics.peakHour, 8)
        XCTAssertEqual(statistics.hourlyRecordingCounts[8], 2)
    }

    func testCurrentStreakAllowsTodayToBeUnused() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 20)),
            makeEntry(createdAt: date(2026, 7, 21)),
            makeEntry(createdAt: date(2026, 7, 22)),
        ]

        let statistics = UsageStatistics.calculate(
            entries: entries,
            calendar: utc,
            now: date(2026, 7, 23)
        )

        XCTAssertEqual(statistics.currentStreak, 3)
        XCTAssertEqual(statistics.longestStreak, 3)
    }

    func testLongestStreakSurvivesAGap() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 10)),
            makeEntry(createdAt: date(2026, 7, 11)),
            makeEntry(createdAt: date(2026, 7, 12)),
            makeEntry(createdAt: date(2026, 7, 21)),
            makeEntry(createdAt: date(2026, 7, 22)),
        ]

        let statistics = UsageStatistics.calculate(
            entries: entries,
            calendar: utc,
            now: date(2026, 7, 23)
        )

        XCTAssertEqual(statistics.currentStreak, 2)
        XCTAssertEqual(statistics.longestStreak, 3)
    }

    func testEmptyJournalHasZeroStatistics() {
        let statistics = UsageStatistics.calculate(
            entries: [],
            calendar: utc,
            now: date(2026, 7, 23)
        )

        XCTAssertEqual(statistics.recordingCount, 0)
        XCTAssertEqual(statistics.currentStreak, 0)
        XCTAssertEqual(statistics.longestStreak, 0)
        XCTAssertNil(statistics.peakHour)
    }
}
