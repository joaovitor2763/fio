import Foundation

/// Removes an entry. It only ever existed on this device,
/// so this removes it everywhere it exists.
public struct DeleteEntryUseCase: Sendable {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    public func execute(entryID: UUID) async throws {
        try await entries.deleteEntry(withID: entryID)
    }
}
