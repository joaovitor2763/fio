import Foundation

/// The words as spoken. The transcript is the single source of truth in
/// Slate; everything else is derived from it and may be empty.
public struct Transcript: Equatable, Hashable, Sendable, Codable {
    public let text: String

    public init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { text.isEmpty }

    public var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Below this, the observer is not even asked — there is nothing to read.
    public static let substantialWordCount = 20

    public var isSubstantial: Bool { wordCount >= Self.substantialWordCount }

    /// A short opening used on the timeline when the observer stayed silent.
    public func preview(maxWords: Int = 14) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return "" }
        let prefix = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? prefix + "…" : prefix
    }

    /// A bounded slice for prompt building, cut on a word boundary.
    public func excerpt(maxCharacters: Int = 400) -> String {
        guard text.count > maxCharacters else { return text }
        let hardCut = String(text.prefix(maxCharacters))
        guard let lastSpace = hardCut.lastIndex(where: \.isWhitespace) else { return hardCut + "…" }
        return String(hardCut[..<lastSpace]) + "…"
    }
}
