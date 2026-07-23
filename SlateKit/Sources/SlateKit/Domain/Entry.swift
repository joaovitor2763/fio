import Foundation

/// One spoken journal entry — the aggregate root of the journal.
public struct Entry: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var duration: TimeInterval
    public var transcript: Transcript
    public var reflection: Reflection
    /// A correction the author added later ("Not what you meant? Add context").
    public var authorContext: String

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        duration: TimeInterval,
        transcript: Transcript,
        reflection: Reflection = .silent,
        authorContext: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.reflection = reflection
        self.authorContext = authorContext
    }

    /// The line shown on the timeline: the observer's headline when it spoke,
    /// the author's own opening words when it stayed silent.
    public var timelineLine: String {
        if !reflection.headline.isEmpty { return reflection.headline }
        let preview = transcript.preview()
        return preview.isEmpty ? "A quiet entry." : preview
    }

    /// Everything the observer wrote, headline first, for the entry screen.
    public var displayObservations: [String] {
        var lines: [String] = []
        if !reflection.headline.isEmpty { lines.append(reflection.headline) }
        lines.append(contentsOf: reflection.observations)
        return lines
    }
}
