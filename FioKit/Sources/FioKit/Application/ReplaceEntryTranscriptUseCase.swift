import Foundation

/// Replaces only the transcription of a preserved entry.
/// Its reflection is cleared so it can be regenerated from the corrected text.
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
        entry.reflection = .silent
        try await entries.save(entry)
        return entry
    }
}
