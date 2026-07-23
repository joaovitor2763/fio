import Foundation

/// Turns a finished recording into a stored entry.
/// Empty transcripts are dropped silently — nothing was said, nothing is kept.
public struct RecordEntryUseCase {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    /// - Parameter replacing: when set, the new entry replaces that one
    ///   (the "Re-record" path). The old entry is only removed once the
    ///   new one is safely stored.
    @discardableResult
    public func execute(
        transcriptText: String,
        duration: TimeInterval,
        replacing replacedID: UUID? = nil,
        at date: Date = .now
    ) async throws -> Entry? {
        let transcript = Transcript(transcriptText)
        guard !transcript.isEmpty else { return nil }

        let entry = Entry(createdAt: date, duration: duration, transcript: transcript)
        try await entries.save(entry)
        if let replacedID, replacedID != entry.id {
            try await entries.deleteEntry(withID: replacedID)
        }
        return entry
    }
}
