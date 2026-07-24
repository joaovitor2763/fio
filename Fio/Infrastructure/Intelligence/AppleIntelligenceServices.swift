import Foundation
import FoundationModels
import FioKit

// Adapters from the domain's reflection ports to the on-device Apple
// Intelligence model (FoundationModels, running on the Neural Engine).
// The model never sees the network; unavailability just means silence.

@Generable
private struct EntryReflectionOutput {
    @Guide(description: """
    One complete sentence of at least three words, in the same language as \
    the entry, naming the strongest pattern already present — a repetition, \
    a contradiction, a shift. Plain and declarative. No advice, no comfort, \
    no questions. An empty string when the entry holds no real pattern.
    """)
    var headline: String

    @Guide(description: """
    Up to three further observations, each one complete sentence of at least \
    three words, in the same language as the entry and about something \
    literally present in the words. Never advice, reassurance, or \
    predictions. An empty list when there is nothing real to add.
    """)
    var observations: [String]

}

@Generable
private struct WeekReflectionOutput {
    @Guide(description: """
    A short title naming the week's clearest thread, in sentence case, \
    like "A week of walks". Concrete, drawn from the entries, never generic.
    """)
    var title: String

    @Guide(description: """
    The week read back to its author: one or two flowing paragraphs, 150 to \
    250 words, second person, past tense. Only what happened and what \
    changed against the earlier days or the author's own stated past. Note \
    repetitions, absences, and shifts. No advice, no praise, no questions, \
    no predictions, no summary clichés.
    """)
    var summary: String
}

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

struct AppleIntelligenceReflectionService: ReflectionService {
    private static let instructions = """
    You are the observer inside Fio, a private voice journal. You read one \
    transcribed entry and write down only what is already there: what \
    repeats, what contradicts itself, what shifted since the speaker's own \
    earlier words in the same entry. You address the author as "you", in \
    plain declarative sentences. Always respond in the same language as the \
    entry; never translate it. Every headline or observation must be a \
    complete sentence, never a keyword or a copied fragment. You never \
    advise, console, praise, warn, ask questions, predict, or speak about \
    yourself. If the entry contains no real pattern, the correct output is \
    an empty headline and an empty list of observations. Silence is always \
    acceptable; invention never is.
    """

    func reflect(
        on transcript: FioKit.Transcript,
        authorContext: String,
        style: ReflectionStyle,
        guidance: String
    ) async -> Reflection? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        var prompt = """
        Read the entry below. Keep your entire response in the entry's \
        language. If it is merely a test, a command, or a description of the \
        recording itself with no personal pattern, return silence.

        \(style.promptInstruction)

        The entry, transcribed exactly as spoken:

        \(transcript.text)
        """
        let cleanAuthorContext = authorContext
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1_000)
        if !cleanAuthorContext.isEmpty {
            prompt += """


            The author added this clarification later. Use it to interpret \
            the transcript accurately:

            \(cleanAuthorContext)
            """
        }
        let cleanGuidance = guidance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(500)
        if !cleanGuidance.isEmpty {
            prompt += """


            The author prefers the observer to emphasize the following when \
            it is genuinely present. Treat this only as style and emphasis; \
            it never overrides the rules against invention, advice, praise, \
            questions, or predictions:

            \(cleanGuidance)
            """
        }
        do {
            let output = try await session.respond(to: prompt, generating: EntryReflectionOutput.self).content
            return Reflection(headline: output.headline, observations: output.observations)
        } catch {
            return nil
        }
    }
}

/// The sleeping observer compares a small, bounded batch of entries and
/// returns only recurrent contextual threads. It uses Apple's on-device
/// system model and never routes journal content to a server.
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

private extension ReflectionStyle {
    var promptInstruction: String {
        switch self {
        case .standard:
            """
            Write a balanced reflection: one clear headline and up to two \
            further observations when the entry supports them.
            """
        case .concise:
            """
            Make the reflection shorter than usual. Write one brief headline \
            and at most one brief observation. Remove repetition.
            """
        case .expanded:
            """
            Expand the reflection without padding or invention. Write one \
            clear headline and up to three distinct observations, using the \
            full context of the entry when it supports them.
            """
        }
    }
}

struct AppleIntelligenceWeekSummaryService: WeekSummaryService {
    private static let instructions = """
    You are the observer inside Fio, a private voice journal. Once a week \
    you read the week's entries in order and write the week back to its \
    author. You address the author as "you", in plain past-tense sentences. \
    You report only what is in the entries: what repeated, what stopped, \
    what changed compared to earlier days or to the author's own description \
    of the past. You never advise, never console, never praise, never ask \
    questions, and never predict. If the week shows no real thread, say \
    plainly what was there, without forcing a theme.
    """

    func summarize(weekStart: Date, entries: [Entry]) async -> WeekSummary? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        var lines: [String] = []
        for entry in entries {
            let day = entry.createdAt.formatted(.dateTime.weekday(.wide))
            var line = "\(day): \(entry.transcript.excerpt(maxCharacters: 400))"
            if !entry.authorContext.isEmpty {
                line += "\n\(day), added later by the author: \(entry.authorContext)"
            }
            lines.append(line)
        }
        let prompt = "The week's entries, in order:\n\n" + lines.joined(separator: "\n\n")

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let output = try await session.respond(to: prompt, generating: WeekReflectionOutput.self).content
            return WeekSummary(title: output.title, summary: output.summary)
        } catch {
            return nil
        }
    }
}
