import Foundation

/// Stores the author's own correction on an entry
/// ("Not what you meant? Add context").
public struct AmendEntryContextUseCase {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    @discardableResult
    public func execute(entryID: UUID, context: String) async throws -> Entry? {
        guard var entry = try await entries.entry(withID: entryID) else { return nil }
        entry.authorContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        try await entries.save(entry)
        return entry
    }
}
