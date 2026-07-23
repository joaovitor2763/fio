import Foundation

/// Asks the observer to read one stored entry and writes back what it said.
/// Thin entries are never sent; silence leaves the entry untouched.
public struct AnnotateEntryUseCase: Sendable {
    private let entries: EntryRepository
    private let reflector: ReflectionService

    public init(entries: EntryRepository, reflector: ReflectionService) {
        self.entries = entries
        self.reflector = reflector
    }

    @discardableResult
    public func execute(entryID: UUID) async throws -> Entry? {
        guard var entry = try await entries.entry(withID: entryID) else { return nil }
        guard entry.transcript.isSubstantial else { return entry }
        guard let raw = await reflector.reflect(on: entry.transcript) else { return entry }

        let reflection = Reflection.sanitized(
            headline: raw.headline,
            observations: raw.observations,
            tags: raw.tags
        )
        guard !reflection.isSilent else { return entry }

        entry.reflection = reflection
        try await entries.save(entry)
        return entry
    }
}
