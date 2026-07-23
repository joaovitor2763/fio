import XCTest
@testable import SlateKit

final class JournalCalendarTests: XCTestCase {
    func testWeekStartIsMonday() {
        // Wednesday July 15th 2026 -> Monday July 13th 00:00.
        let monday = utc.weekStart(containing: date(2026, 7, 15))
        XCTAssertEqual(monday, date(2026, 7, 13, 0, 0))
    }

    func testWeekStartOfAMondayIsItself() {
        XCTAssertEqual(utc.weekStart(containing: date(2026, 7, 13, 8, 45)), date(2026, 7, 13, 0, 0))
    }

    func testSundayBelongsToThePrecedingMonday() {
        XCTAssertEqual(utc.weekStart(containing: date(2026, 7, 19, 23, 59)), date(2026, 7, 13, 0, 0))
    }

    func testWeekdayIndexMondayThroughSunday() {
        XCTAssertEqual(utc.weekdayIndex(of: date(2026, 7, 13)), 0) // Monday
        XCTAssertEqual(utc.weekdayIndex(of: date(2026, 7, 16)), 3) // Thursday
        XCTAssertEqual(utc.weekdayIndex(of: date(2026, 7, 19)), 6) // Sunday
    }

    func testIsSunday() {
        XCTAssertTrue(utc.isSunday(date(2026, 7, 19)))
        XCTAssertFalse(utc.isSunday(date(2026, 7, 18)))
    }

    func testWeekDaysReturnsSevenConsecutiveDays() {
        let days = utc.weekDays(containing: date(2026, 7, 15))
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(2026, 7, 13, 0, 0))
        XCTAssertEqual(days.last, date(2026, 7, 19, 0, 0))
    }
}
