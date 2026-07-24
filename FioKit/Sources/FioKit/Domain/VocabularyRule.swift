import Foundation

/// A deterministic correction for names and terms the speech transcriber
/// regularly gets wrong.
public struct VocabularyRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var source: String
    public var replacement: String

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String
    ) {
        self.id = id
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct VocabularyApplication: Equatable, Sendable {
    public let text: String
    public let appliedCount: Int

    public init(text: String, appliedCount: Int) {
        self.text = text
        self.appliedCount = appliedCount
    }
}

public struct VocabularySuggestion: Equatable, Sendable {
    public let source: String
    public let replacement: String

    public init(source: String, replacement: String) {
        self.source = source
        self.replacement = replacement
    }
}

public enum VocabularyProcessor {
    /// Applies the longest matching term once per source range. Processing all
    /// rules in one pass prevents replacements from cascading into each other.
    public static func apply(
        to text: String,
        rules: [VocabularyRule]
    ) -> VocabularyApplication {
        let validRules = uniqueValidRules(rules)
        guard !text.isEmpty, !validRules.isEmpty else {
            return VocabularyApplication(text: text, appliedCount: 0)
        }

        let alternatives = validRules
            .sorted { $0.source.count > $1.source.count }
            .map { NSRegularExpression.escapedPattern(for: $0.source) }
            .joined(separator: "|")
        let pattern = #"(?<![\p{L}\p{M}\p{N}_])(?:\#(alternatives))(?![\p{L}\p{M}\p{N}_])"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        ) else {
            return VocabularyApplication(text: text, appliedCount: 0)
        }

        let rulesBySource = Dictionary(
            uniqueKeysWithValues: validRules.map {
                (normalizedSource($0.source), $0)
            }
        )
        let original = text as NSString
        let protectedRangesBySource = Dictionary(
            uniqueKeysWithValues: validRules.map {
                let containsItsSource = normalizedSource($0.source)
                    != normalizedSource($0.replacement)
                    && containsWholeTerm($0.source, in: $0.replacement)
                return (
                    normalizedSource($0.source),
                    wholeTermRanges(
                        of: $0.replacement,
                        in: text,
                        caseInsensitive: containsItsSource
                    )
                )
            }
        )
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: original.length)
        )
        let corrected = NSMutableString(string: text)
        var appliedCount = 0

        for match in matches.reversed() {
            let matchedText = original.substring(with: match.range)
            let sourceKey = normalizedSource(matchedText)
            guard let rule = rulesBySource[sourceKey],
                  !protectedRangesBySource[sourceKey, default: []].contains(where: {
                      NSLocationInRange(match.range.location, $0)
                          && NSMaxRange(match.range) <= NSMaxRange($0)
                  }),
                  matchedText != rule.replacement else {
                continue
            }
            corrected.replaceCharacters(in: match.range, with: rule.replacement)
            appliedCount += 1
        }

        return VocabularyApplication(
            text: corrected as String,
            appliedCount: appliedCount
        )
    }

    /// Suggests a reusable rule only for one compact edit of up to three
    /// words. Larger rewrites stay private to the entry and do not prompt.
    public static func suggestion(
        from original: String,
        to edited: String,
        existingRules: [VocabularyRule]
    ) -> VocabularySuggestion? {
        let originalWords = words(in: original)
        let editedWords = words(in: edited)
        guard originalWords != editedWords else { return nil }

        var prefixCount = 0
        while prefixCount < min(originalWords.count, editedWords.count),
              originalWords[prefixCount] == editedWords[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < originalWords.count - prefixCount,
              suffixCount < editedWords.count - prefixCount,
              originalWords[originalWords.count - 1 - suffixCount]
                == editedWords[editedWords.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let originalEnd = originalWords.count - suffixCount
        let editedEnd = editedWords.count - suffixCount
        let sourceWords = Array(originalWords[prefixCount..<originalEnd])
        let replacementWords = Array(editedWords[prefixCount..<editedEnd])
        guard (1...3).contains(sourceWords.count),
              (1...3).contains(replacementWords.count) else {
            return nil
        }

        let source = cleanSuggestion(sourceWords.joined(separator: " "))
        let replacement = cleanSuggestion(replacementWords.joined(separator: " "))
        guard isValid(source: source, replacement: replacement),
              !existingRules.contains(where: {
                  normalizedSource($0.source) == normalizedSource(source)
              }),
              !conflicts(
                  VocabularyRule(source: source, replacement: replacement),
                  with: existingRules
              ) else {
            return nil
        }

        return VocabularySuggestion(source: source, replacement: replacement)
    }

    public static func isValid(source: String, replacement: String) -> Bool {
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanSource.isEmpty
            && !cleanReplacement.isEmpty
            && cleanSource != cleanReplacement
            && cleanSource.count <= 80
            && cleanReplacement.count <= 80
    }

    /// Cross-matching rules are ambiguous across repeated processing:
    /// "alpha → beta" cannot coexist with "beta → gamma".
    public static func conflicts(
        _ candidate: VocabularyRule,
        with existingRules: [VocabularyRule]
    ) -> Bool {
        guard isValid(
            source: candidate.source,
            replacement: candidate.replacement
        ) else {
            return false
        }
        return existingRules.contains { existing in
            containsWholeTerm(candidate.source, in: existing.replacement)
                || containsWholeTerm(existing.source, in: candidate.replacement)
        }
    }

    private static func uniqueValidRules(
        _ rules: [VocabularyRule]
    ) -> [VocabularyRule] {
        var seen: Set<String> = []
        return rules.compactMap { rule in
            guard isValid(source: rule.source, replacement: rule.replacement) else {
                return nil
            }
            let key = normalizedSource(rule.source)
            guard seen.insert(key).inserted else { return nil }
            return VocabularyRule(
                id: rule.id,
                source: rule.source,
                replacement: rule.replacement
            )
        }
    }

    private static func normalizedSource(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
    }

    /// Exact replacement output is protected on later passes. This keeps
    /// rules such as "NY → New York, NY" and cross-matching rule sets
    /// idempotent without cascading changes.
    private static func wholeTermRanges(
        of term: String,
        in text: String,
        caseInsensitive: Bool
    ) -> [NSRange] {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = #"(?<![\p{L}\p{M}\p{N}_])(?:\#(escaped))(?![\p{L}\p{M}\p{N}_])"#
        let options: NSRegularExpression.Options = caseInsensitive
            ? [.caseInsensitive, .useUnicodeWordBoundaries]
            : []
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return []
        }
        let length = (text as NSString).length
        return expression
            .matches(in: text, range: NSRange(location: 0, length: length))
            .map(\.range)
    }

    private static func containsWholeTerm(
        _ term: String,
        in text: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = #"(?<![\p{L}\p{M}\p{N}_])(?:\#(escaped))(?![\p{L}\p{M}\p{N}_])"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        ) else {
            return false
        }
        let length = (text as NSString).length
        return expression.firstMatch(
            in: text,
            range: NSRange(location: 0, length: length)
        ) != nil
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func cleanSuggestion(_ text: String) -> String {
        text.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
    }
}
