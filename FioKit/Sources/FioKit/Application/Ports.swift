import Foundation

// The application layer talks to the outside world only through these ports.
// The iOS app plugs in SwiftData and Apple Intelligence; the tests plug in
// in-memory fakes. Neither side leaks into the domain.

/// Persistence for journal entries. `save` upserts by ID.
public protocol EntryRepository: Sendable {
    func allEntries() async throws -> [Entry]
    func entry(withID id: UUID) async throws -> Entry?
    func save(_ entry: Entry) async throws
    func deleteEntry(withID id: UUID) async throws
}

/// Persistence for weekly reviews. `save` upserts by ID.
public protocol ReviewRepository: Sendable {
    func allReviews() async throws -> [WeekReview]
    func save(_ review: WeekReview) async throws
}

/// The observer. Returns nil when it is unavailable or has nothing to say;
/// the raw output is sanitized by the use case, not trusted as-is.
public protocol ReflectionService: Sendable {
    func reflect(on transcript: Transcript) async -> Reflection?
}

public struct WeekSummary: Equatable, Sendable {
    public var title: String
    public var summary: String

    public init(title: String, summary: String) {
        self.title = title
        self.summary = summary
    }
}

/// The Sunday read-back writer. Returns nil when unavailable or silent.
public protocol WeekSummaryService: Sendable {
    func summarize(weekStart: Date, entries: [Entry]) async -> WeekSummary?
}
