import Foundation
import SwiftData

/// One spoken entry. The transcript is the source of truth; everything else
/// is the on-device model's reading of it, and may legitimately be empty.
@Model
final class JournalEntry {
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String

    /// One sentence the model wrote back — the line shown on the timeline.
    /// Empty when the model had nothing real to say.
    var headline: String
    /// Further observations, shown as bullets on the entry screen.
    var observations: [String]
    /// Short topic tags, e.g. "The Morning Run".
    var tags: [String]
    /// Optional correction the author added ("Not what you meant? Add context").
    var userContext: String

    init(
        createdAt: Date = .now,
        duration: TimeInterval,
        transcript: String,
        headline: String = "",
        observations: [String] = [],
        tags: [String] = [],
        userContext: String = ""
    ) {
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.headline = headline
        self.observations = observations
        self.tags = tags
        self.userContext = userContext
    }

    /// What the timeline shows when the model stayed silent.
    var timelineLine: String {
        if !headline.isEmpty { return headline }
        let words = transcript.split(separator: " ")
        guard !words.isEmpty else { return "A quiet entry." }
        let prefix = words.prefix(14).joined(separator: " ")
        return words.count > 14 ? prefix + "…" : prefix
    }

    /// Everything the observer wrote for this entry, headline first.
    var allObservations: [String] {
        var lines: [String] = []
        if !headline.isEmpty { lines.append(headline) }
        lines.append(contentsOf: observations.filter { !$0.isEmpty })
        return lines
    }
}
