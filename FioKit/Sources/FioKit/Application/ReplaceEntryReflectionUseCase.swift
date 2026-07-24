import Foundation

/// Replaces the observer's text with an explicit correction from the author.
public struct ReplaceEntryReflectionUseCase: Sendable {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    @discardableResult
    public func execute(
        entryID: UUID,
        headline: String,
        observations: [String]
    ) async throws -> Entry? {
        guard var entry = try await entries.entry(withID: entryID) else { return nil }

        entry.reflection = Reflection.sanitized(
            headline: headline,
            observations: observations,
            tags: entry.reflection.tags
        )
        try await entries.save(entry)
        return entry
    }
}
