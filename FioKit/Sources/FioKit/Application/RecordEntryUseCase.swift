import Foundation

/// Turns a finished recording into a stored entry.
/// A recording is kept when it has either a transcript or its original audio.
public struct RecordEntryUseCase: Sendable {
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
        audioFileName: String? = nil,
        replacing replacedID: UUID? = nil,
        at date: Date = .now
    ) async throws -> Entry? {
        let transcript = Transcript(transcriptText)
        guard !transcript.isEmpty || audioFileName != nil else { return nil }

        let entry = Entry(
            createdAt: date,
            duration: duration,
            transcript: transcript,
            audioFileName: audioFileName
        )
        if let replacedID, replacedID != entry.id {
            try await entries.replacePreservingReferences(
                replacedID,
                with: entry
            )
        } else {
            try await entries.save(entry)
        }
        return entry
    }
}
