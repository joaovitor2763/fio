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
    private(set) var allEntriesCallCount = 0
    var shouldFailReplacement = false

    func allEntries() async throws -> [Entry] {
        allEntriesCallCount += 1
        return storage
    }

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

    func replacePreservingReferences(
        _ replacedID: UUID,
        with entry: Entry
    ) async throws {
        guard !shouldFailReplacement else {
            throw StubRepositoryError.expectedFailure
        }
        storage.removeAll { $0.id == replacedID || $0.id == entry.id }
        storage.append(entry)
        saveCount += 1
    }

    func saveReflection(
        _ reflection: Reflection,
        forEntryID id: UUID,
        ifUnchangedFrom expectedEntry: Entry
    ) async throws -> Bool {
        guard let index = storage.firstIndex(where: { $0.id == id }),
              storage[index] == expectedEntry else {
            return false
        }
        storage[index].reflection = reflection
        saveCount += 1
        return true
    }

    func deleteEntry(withID id: UUID) async throws {
        storage.removeAll { $0.id == id }
    }
}

enum StubRepositoryError: Error {
    case expectedFailure
}

final class InMemoryReviewRepository: ReviewRepository, @unchecked Sendable {
    private(set) var storage: [WeekReview] = []
    private(set) var allReviewsCallCount = 0

    func allReviews() async throws -> [WeekReview] {
        allReviewsCallCount += 1
        return storage
    }

    func save(_ review: WeekReview) async throws {
        if let index = storage.firstIndex(where: { $0.id == review.id }) {
            storage[index] = review
        } else {
            storage.append(review)
        }
    }
}

final class InMemoryTopicRepository: TopicRepository, @unchecked Sendable {
    private(set) var storage: [Topic] = []
    private(set) var allTopicsCallCount = 0
    private(set) var replaceAllCallCount = 0

    func allTopics() async throws -> [Topic] {
        allTopicsCallCount += 1
        return storage
    }

    func save(_ topic: Topic) async throws {
        if let index = storage.firstIndex(where: { $0.id == topic.id }) {
            storage[index] = topic
        } else {
            storage.append(topic)
        }
    }

    func deleteTopic(withID id: UUID) async throws {
        storage.removeAll { $0.id == id }
    }

    func replaceAll(with topics: [Topic]) async throws {
        replaceAllCallCount += 1
        storage = topics
    }
}

final class StubReflectionService: ReflectionService, @unchecked Sendable {
    var result: Reflection?
    private(set) var callCount = 0
    private(set) var lastAuthorContext = ""
    private(set) var lastStyle: ReflectionStyle?
    private(set) var lastGuidance = ""

    init(result: Reflection? = nil) {
        self.result = result
    }

    func reflect(
        on transcript: Transcript,
        authorContext: String,
        style: ReflectionStyle,
        guidance: String
    ) async -> Reflection? {
        callCount += 1
        lastAuthorContext = authorContext
        lastStyle = style
        lastGuidance = guidance
        return result
    }
}

final class CallbackReflectionService: ReflectionService, @unchecked Sendable {
    let result: Reflection
    let onReflect: @Sendable () async -> Void

    init(result: Reflection, onReflect: @escaping @Sendable () async -> Void) {
        self.result = result
        self.onReflect = onReflect
    }

    func reflect(
        on transcript: Transcript,
        authorContext: String,
        style: ReflectionStyle,
        guidance: String
    ) async -> Reflection? {
        await onReflect()
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
