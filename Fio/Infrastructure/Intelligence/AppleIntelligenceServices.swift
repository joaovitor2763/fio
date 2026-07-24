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
