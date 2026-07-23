import Foundation
import XCTest
@testable import FioKit

// All date math in tests runs in UTC so results are identical on any machine.
let utc = JournalCalendar(timeZone: TimeZone(identifier: "UTC")!)

/// July 2026 matches the design mock: Monday July 13th, Sunday July 19th.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return utc.calendar.date(from: components)!
}

func makeEntry(
    id: UUID = UUID(),
    createdAt: Date = date(2026, 7, 13),
    duration: TimeInterval = 90,
    words: Int = 30,
    reflection: Reflection = .silent
) -> Entry {
    let text = (0..<words).map { "word\($0)" }.joined(separator: " ")
    return Entry(
        id: id,
        createdAt: createdAt,
        duration: duration,
        transcript: Transcript(text),
        reflection: reflection
    )
}

// MARK: - Port fakes

final class InMemoryEntryRepository: EntryRepository, @unchecked Sendable {
    private(set) var storage: [Entry] = []
    private(set) var saveCount = 0

    func allEntries() async throws -> [Entry] { storage }

    func entry(withID id: UUID) async throws -> Entry? {
        storage.first { $0.id == id }
    }

    func save(_ entry: Entry) async throws {
        saveCount += 1
        if let index = storage.firstIndex(where: { $0.id == entry.id }) {
            storage[index] = entry
        } else {
            storage.append(entry)
        }
    }

    func deleteEntry(withID id: UUID) async throws {
        storage.removeAll { $0.id == id }
    }
}

final class InMemoryReviewRepository: ReviewRepository, @unchecked Sendable {
    private(set) var storage: [WeekReview] = []

    func allReviews() async throws -> [WeekReview] { storage }

    func save(_ review: WeekReview) async throws {
        if let index = storage.firstIndex(where: { $0.id == review.id }) {
            storage[index] = review
        } else {
            storage.append(review)
        }
    }
}

final class StubReflectionService: ReflectionService, @unchecked Sendable {
    var result: Reflection?
    private(set) var callCount = 0

    init(result: Reflection? = nil) {
        self.result = result
    }

    func reflect(on transcript: Transcript) async -> Reflection? {
        callCount += 1
        return result
    }
}

final class StubWeekSummaryService: WeekSummaryService, @unchecked Sendable {
    var result: WeekSummary?
    private(set) var callCount = 0

    init(result: WeekSummary? = nil) {
        self.result = result
    }

    func summarize(weekStart: Date, entries: [Entry]) async -> WeekSummary? {
        callCount += 1
        return result
    }
}
