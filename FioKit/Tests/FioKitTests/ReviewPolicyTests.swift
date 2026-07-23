import XCTest
@testable import FioKit

final class ReviewPolicyTests: XCTestCase {
    let policy = ReviewPolicy(calendar: utc)
    let weekStart = date(2026, 7, 13, 0, 0) // Monday

    func testWeekIsNotReadableMidweek() {
        XCTAssertFalse(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 7, 15)))
        XCTAssertFalse(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 7, 18, 23, 59)))
    }

    func testWeekBecomesReadableOnItsSunday() {
        XCTAssertTrue(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 7, 19, 0, 5)))
        XCTAssertTrue(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 7, 19, 21, 0)))
    }

    func testWeekStaysReadableAfterItEnds() {
        XCTAssertTrue(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 7, 22)))
        XCTAssertTrue(policy.isWeekReadable(weekStart: weekStart, now: date(2026, 9, 1)))
    }

    func testDueWeeksRequiresMinimumEntries() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 13)),
            makeEntry(createdAt: date(2026, 7, 14)),
        ]
        let due = policy.dueWeeks(entries: entries, existingReviewWeekStarts: [], now: date(2026, 7, 22))
        XCTAssertTrue(due.isEmpty)
    }

    func testDueWeeksExcludesUnfinishedWeeks() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 13)),
            makeEntry(createdAt: date(2026, 7, 14)),
            makeEntry(createdAt: date(2026, 7, 15)),
        ]
        XCTAssertTrue(policy.dueWeeks(entries: entries, existingReviewWeekStarts: [], now: date(2026, 7, 16)).isEmpty)
        XCTAssertEqual(policy.dueWeeks(entries: entries, existingReviewWeekStarts: [], now: date(2026, 7, 19)).count, 1)
    }

    func testDueWeeksExcludesAlreadyReviewedWeeks() {
        let entries = [
            makeEntry(createdAt: date(2026, 7, 13)),
            makeEntry(createdAt: date(2026, 7, 14)),
            makeEntry(createdAt: date(2026, 7, 15)),
        ]
        let due = policy.dueWeeks(
            entries: entries,
            existingReviewWeekStarts: [date(2026, 7, 13, 0, 0)],
            now: date(2026, 7, 22)
        )
        XCTAssertTrue(due.isEmpty)
    }

    func testDueWeeksAreOldestFirstWithEntriesInSpokenOrder() {
        let week1 = [
            makeEntry(createdAt: date(2026, 7, 8)),
            makeEntry(createdAt: date(2026, 7, 6)),
            makeEntry(createdAt: date(2026, 7, 7)),
        ]
        let week2 = [
            makeEntry(createdAt: date(2026, 7, 13)),
            makeEntry(createdAt: date(2026, 7, 15)),
            makeEntry(createdAt: date(2026, 7, 14)),
        ]
        let due = policy.dueWeeks(entries: week2 + week1, existingReviewWeekStarts: [], now: date(2026, 7, 22))
        XCTAssertEqual(due.count, 2)
        XCTAssertEqual(due[0].weekStart, date(2026, 7, 6, 0, 0))
        XCTAssertEqual(due[1].weekStart, date(2026, 7, 13, 0, 0))
        XCTAssertEqual(due[0].entries.map(\.createdAt), [date(2026, 7, 6), date(2026, 7, 7), date(2026, 7, 8)])
    }
}
