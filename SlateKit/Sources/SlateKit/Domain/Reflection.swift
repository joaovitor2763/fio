import Foundation

/// What the observer wrote back about one entry. Silence — the empty
/// reflection — is a first-class value, not an error.
public struct Reflection: Equatable, Hashable, Sendable, Codable {
    /// One second-person sentence naming the strongest pattern.
    public var headline: String
    /// Up to `maxObservations` further one-sentence observations.
    public var observations: [String]
    /// Up to `maxTags` short topic tags, e.g. "The Morning Run".
    public var tags: [String]

    public static let maxObservations = 3
    public static let maxTags = 3
    /// A tag longer than this is a sentence pretending to be a tag; drop it.
    public static let maxTagWords = 4

    public init(headline: String = "", observations: [String] = [], tags: [String] = []) {
        self.headline = headline
        self.observations = observations
        self.tags = tags
    }

    public static let silent = Reflection()

    public var isSilent: Bool {
        headline.isEmpty && observations.isEmpty && tags.isEmpty
    }

    /// Enforces the observer's contract on raw model output: trimmed,
    /// deduplicated, capped, and never echoing the headline as an observation.
    public static func sanitized(headline: String, observations: [String], tags: [String]) -> Reflection {
        let cleanHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)

        var seenLines: Set<String> = [cleanHeadline.lowercased()]
        let cleanObservations = observations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenLines.insert($0.lowercased()).inserted }
            .prefix(maxObservations)

        var seenTags: Set<String> = []
        let cleanTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.split(whereSeparator: \.isWhitespace).count <= maxTagWords }
            .filter { seenTags.insert($0.lowercased()).inserted }
            .prefix(maxTags)

        return Reflection(
            headline: cleanHeadline,
            observations: Array(cleanObservations),
            tags: Array(cleanTags)
        )
    }
}
