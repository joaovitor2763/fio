import Foundation
import FoundationModels
import SlateKit

// Adapters from the domain's reflection ports to the on-device Apple
// Intelligence model (FoundationModels, running on the Neural Engine).
// The model never sees the network; unavailability just means silence.

@Generable
private struct EntryReflectionOutput {
    @Guide(description: """
    One sentence in the second person naming the strongest pattern already \
    present in the entry — a repetition, a contradiction, a shift. Plain and \
    declarative. No advice, no comfort, no questions. An empty string when \
    the entry holds no real pattern.
    """)
    var headline: String

    @Guide(description: """
    Up to three further observations, each a single short sentence in the \
    second person, each about something literally present in the words. \
    Never advice, never reassurance, never predictions. An empty list when \
    there is nothing real to add.
    """)
    var observations: [String]

    @Guide(description: """
    Up to three topic tags of at most three words each, in title case, \
    naming concrete subjects the entry keeps returning to, \
    like "The Morning Run" or "Friday Deadline".
    """)
    var tags: [String]
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

struct AppleIntelligenceReflectionService: ReflectionService {
    private static let instructions = """
    You are the observer inside Slate, a private voice journal. You read one \
    transcribed entry and write down only what is already there: what \
    repeats, what contradicts itself, what shifted since the speaker's own \
    earlier words in the same entry. You address the author as "you", in \
    plain declarative sentences. You never advise, never console, never \
    praise, never warn, never ask questions, never predict, and never speak \
    about yourself. If the entry contains no real pattern, the correct \
    output is an empty headline, an empty list of observations, and no tags. \
    Silence is always acceptable; invention never is.
    """

    func reflect(on transcript: Transcript) async -> Reflection? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = "The entry, transcribed exactly as spoken:\n\n\(transcript.text)"
        do {
            let output = try await session.respond(to: prompt, generating: EntryReflectionOutput.self).content
            return Reflection(headline: output.headline, observations: output.observations, tags: output.tags)
        } catch {
            return nil
        }
    }
}

struct AppleIntelligenceWeekSummaryService: WeekSummaryService {
    private static let instructions = """
    You are the observer inside Slate, a private voice journal. Once a week \
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
