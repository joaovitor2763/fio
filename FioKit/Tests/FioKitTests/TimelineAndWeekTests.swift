import XCTest
@testable import FioKit

final class TimelineBuilderTests: XCTestCase {
    func testGroupsByDayNewestFirst() {
        let older = makeEntry(createdAt: date(2026, 7, 12, 21, 39))
        let morning = makeEntry(createdAt: date(2026, 7, 14, 7, 30))
        let later = makeEntry(createdAt: date(2026, 7, 14, 8, 45))

        let days = TimelineBuilder.days(from: [older, morning, later], calendar: utc)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].day, date(2026, 7, 14, 0, 0))
        XCTAssertEqual(days[0].entries.map(\.id), [later.id, morning.id])
        XCTAssertEqual(days[1].day, date(2026, 7, 12, 0, 0))
    }

    func testEmptyInputMakesEmptyTimeline() {
        XCTAssertTrue(TimelineBuilder.days(from: [], calendar: utc).isEmpty)
    }
}

final class SpeakingWeekTests: XCTestCase {
    func testMinutesLandInWeekdayBuckets() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 13), duration: 90),  // Monday
            makeEntry(createdAt: date(2026, 7, 13), duration: 30),  // Monday
            makeEntry(createdAt: date(2026, 7, 19), duration: 60),  // Sunday
        ]
        let minutes = SpeakingWeek.dailyMinutes(entries: entries, calendar: utc)
        XCTAssertEqual(minutes, [2.0, 0, 0, 0, 0, 0, 1.0])
    }
}

final class FormattingTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(Formatting.clock(0), "0:00")
        XCTAssertEqual(Formatting.clock(113), "1:53")
        XCTAssertEqual(Formatting.clock(605), "10:05")
    }

    func testCompactDuration() {
        XCTAssertEqual(Formatting.compactDuration(58), "58s")
        XCTAssertEqual(Formatting.compactDuration(94), "1m 34s")
        XCTAssertEqual(Formatting.compactDuration(312), "5m 12s")
    }

    func testOrdinalSuffixes() {
        XCTAssertEqual(Formatting.ordinalSuffix(1), "st")
        XCTAssertEqual(Formatting.ordinalSuffix(2), "nd")
        XCTAssertEqual(Formatting.ordinalSuffix(3), "rd")
        XCTAssertEqual(Formatting.ordinalSuffix(4), "th")
        XCTAssertEqual(Formatting.ordinalSuffix(11), "th")
        XCTAssertEqual(Formatting.ordinalSuffix(12), "th")
        XCTAssertEqual(Formatting.ordinalSuffix(13), "th")
        XCTAssertEqual(Formatting.ordinalSuffix(21), "st")
        XCTAssertEqual(Formatting.ordinalSuffix(113), "th")
    }

    func testEntryTitleMatchesTheDesign() {
        let title = Formatting.entryTitle(
            for: date(2026, 7, 13, 8, 45),
            calendar: utc,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(title, "Mon July 13th, 2026")
    }
}
