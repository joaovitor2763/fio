import Foundation
import FoundationModels
import FioKit

@Generable
private struct DreamTopicOutput {
    @Guide(
        description: """
        Contextual topics that are central in at least two different numbered \
        journal entries. Return an empty list when no strong recurrence exists.
        """,
        .maximumCount(3)
    )
    var topics: [DreamTopicItem]
}

@Generable
private struct DreamTopicItem {
    @Guide(description: """
    A short, specific topic name in the entries' language. Describe the \
    shared context, such as "Limites no trabalho", never a repeated function \
    word or a generic word such as "hoje", "coisa", or "trabalho".
    """)
    var name: String

    @Guide(
        description: """
        The numbers of the distinct entries where this same contextual topic \
        is central. Include at least two valid entry numbers.
        """,
        .maximumCount(8)
    )
    var entryNumbers: [Int]
}

struct AppleIntelligenceTopicDiscoveryService: TopicDiscoveryService {
    private static let maximumEntries = 6
    /// UTF-8 bytes are a conservative upper bound for tokenizer units because
    /// every token must consume at least one encoded byte. Keeping the entire
    /// authored input below this value reserves ample room in the 4,096-token
    /// context for the generated schema and response.
    private static let inputUTF8Budget = 2_600
    private static let vocabularyUTF8Budget = 360
    private static let maximumResponseTokens = 500
    private static let instructions = """
    You find durable threads across a private journal. Compare meanings, \
    situations, people, projects, habits, or relationships across whole \
    entries. Never count repeated words. A word appearing multiple times \
    is not evidence of a topic. Suggest a topic only when the same \
    contextual idea is central in at least two distinct entries. Names \
    must be specific noun phrases in the entries' language. Never output \
    articles, pronouns, conjunctions, prepositions, negations, auxiliary \
    verbs, or generic standalone words as topics. Silence is preferable \
    to a weak connection.
    """

    func discoverTopics(
        in entries: [Entry],
        existingTopics: [Topic]
    ) async -> [TopicCandidate]? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let selectedEntries = Array(entries
            .filter { $0.transcript.isSubstantial }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(Self.maximumEntries))
        guard selectedEntries.count >= 2 else { return [] }

        let acceptedNames = existingTopics
            .filter { $0.status == .accepted }
            .map(\.name)
            .prefix(12)
            .joined(separator: ", ")
            .prefixUTF8(maxBytes: Self.vocabularyUTF8Budget)
        let vocabulary = acceptedNames.isEmpty
            ? "There are no accepted topics yet."
            : """
              Existing accepted topics: \(acceptedNames).
              Reuse an existing name exactly when it describes the same context.
              """

        let promptLead = """
        \(vocabulary)

        Find at most three strong recurring contextual topics in these \
        numbered entries. Different wording may express the same topic. Do \
        not invent context that the entries do not contain.

        """
        let separatorBytes = max(0, selectedEntries.count - 1) * 2
        let availableEntryBytes = max(
            0,
            Self.inputUTF8Budget
                - Self.instructions.utf8.count
                - promptLead.utf8.count
                - separatorBytes
        )
        let bytesPerEntry = availableEntryBytes / selectedEntries.count
        guard bytesPerEntry >= 120 else { return [] }

        let numberedEntries = selectedEntries
        let entryText = numberedEntries.enumerated().map { index, entry in
            Self.entryBlock(
                for: entry,
                number: index + 1,
                maxBytes: bytesPerEntry
            )
        }
        .joined(separator: "\n\n")

        let session = LanguageModelSession(
            model: model,
            instructions: Self.instructions
        )
        let prompt = promptLead + entryText
        assert(
            Self.instructions.utf8.count + prompt.utf8.count
                <= Self.inputUTF8Budget
        )

        do {
            let output = try await session.respond(
                to: prompt,
                generating: DreamTopicOutput.self,
                options: GenerationOptions(
                    maximumResponseTokens: Self.maximumResponseTokens
                )
            ).content
            return output.topics.compactMap { item in
                let indices = Set(item.entryNumbers.compactMap { number -> Int? in
                    guard (1...numberedEntries.count).contains(number) else {
                        return nil
                    }
                    return number - 1
                })
                guard indices.count >= 2 else { return nil }
                return TopicCandidate(
                    name: item.name,
                    entryIDs: indices.sorted().map { numberedEntries[$0].id }
                )
            }
        } catch {
            return nil
        }
    }

    private static func entryBlock(
        for entry: Entry,
        number: Int,
        maxBytes: Int
    ) -> String {
        let header = """
        Entry \(number), \(entry.createdAt.formatted(date: .abbreviated, time: .omitted)):

        """
        let contentBudget = max(0, maxBytes - header.utf8.count)
        let reflection = entry.displayObservations.joined(separator: " ")
        let reflectionBudget = reflection.isEmpty ? 0 : min(160, contentBudget / 3)
        let reflectionText = reflection.prefixUTF8(maxBytes: reflectionBudget)
        let reflectionLine = reflectionText.isEmpty
            ? ""
            : "\nReflection: \(reflectionText)"
        let transcriptBudget = max(
            0,
            contentBudget - reflectionLine.utf8.count
        )
        let transcript = entry.transcript.text.prefixUTF8(
            maxBytes: transcriptBudget
        )
        return (header + transcript + reflectionLine)
            .prefixUTF8(maxBytes: maxBytes)
    }
}

private extension String {
    func prefixUTF8(maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var result = ""
        var usedBytes = 0
        for character in self {
            let characterBytes = String(character).utf8.count
            guard usedBytes + characterBytes <= maxBytes else { break }
            result.append(character)
            usedBytes += characterBytes
        }
        return result
    }
}
