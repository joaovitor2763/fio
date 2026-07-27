import Foundation

/// Replaces only the transcription of a preserved entry.
/// The existing reflection is preserved until the observer explicitly asks
/// for a new one based on the corrected text.
public struct ReplaceEntryTranscriptUseCase: Sendable {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    @discardableResult
    public func execute(entryID: UUID, transcriptText: String) async throws -> Entry? {
        guard var entry = try await entries.entry(withID: entryID) else { return nil }
        let transcript = Transcript(transcriptText)
        guard !transcript.isEmpty else { return nil }

        entry.transcript = transcript
        try await entries.save(entry)
        return entry
    }
}
