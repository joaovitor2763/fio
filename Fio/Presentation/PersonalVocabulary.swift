import Foundation
import FioKit

enum PersonalVocabulary {
    static let storageKey = "personalVocabularyRules"
    static let maximumRuleCount = 100

    static var rules: [VocabularyRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode(
                      [VocabularyRule].self,
                      from: data
                  ) else {
                return []
            }
            return Array(decoded.prefix(maximumRuleCount))
        }
        set {
            let trimmed = Array(newValue.prefix(maximumRuleCount))
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func upsert(_ rule: VocabularyRule) {
        var current = rules
        let cleanRule = VocabularyRule(
            id: rule.id,
            source: rule.source,
            replacement: rule.replacement
        )
        guard !VocabularyProcessor.conflicts(
            cleanRule,
            with: current.filter { $0.id != cleanRule.id }
        ) else {
            return
        }
        if let index = current.firstIndex(where: { $0.id == cleanRule.id }) {
            current[index] = cleanRule
        } else if current.count < maximumRuleCount {
            current.append(cleanRule)
        }
        rules = current
    }

    static func remove(id: UUID) {
        rules = rules.filter { $0.id != id }
    }

    static func add(_ suggestion: VocabularySuggestion) {
        guard !containsSource(suggestion.source) else { return }
        upsert(
            VocabularyRule(
                source: suggestion.source,
                replacement: suggestion.replacement
            )
        )
    }

    static func containsSource(_ source: String, excluding id: UUID? = nil) -> Bool {
        let normalized = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        return rules.contains {
            $0.id != id
                && $0.source.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased() == normalized
        }
    }

    static func apply(to text: String) -> VocabularyApplication {
        VocabularyProcessor.apply(to: text, rules: rules)
    }
}
