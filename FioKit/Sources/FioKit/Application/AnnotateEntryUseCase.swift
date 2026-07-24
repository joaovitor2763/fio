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
    public func execute(
        entryID: UUID,
        style: ReflectionStyle = .standard,
        guidance: String = ""
    ) async throws -> Entry? {
        guard let entry = try await entries.entry(withID: entryID) else { return nil }
        guard entry.transcript.isSubstantial else { return entry }
        guard let raw = await reflector.reflect(
            on: entry.transcript,
            authorContext: entry.authorContext,
            style: style,
            guidance: guidance
        ) else { return entry }

        let reflection = Reflection.sanitized(
            headline: raw.headline,
            observations: raw.observations,
            tags: raw.tags
        )
        guard !reflection.isSilent else { return entry }

        // The repository makes this comparison and write atomically. A manual
        // edit made while the model was reading must always win.
        guard try await entries.saveReflection(
            reflection,
            forEntryID: entryID,
            ifUnchangedFrom: entry
        ) else {
            return try await entries.entry(withID: entryID)
        }

        var annotated = entry
        annotated.reflection = reflection
        return annotated
    }
}
