import Foundation
import FoundationModels

/// What the observer wrote back about one entry.
/// Every field may be empty: silence is a valid, expected output.
@Generable
struct EntryReflection {
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

/// The local model is an observer. It never replies, advises, or comforts.
/// When it has nothing real to say, it says nothing.
enum Reflector {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

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

    /// Reads one entry. Returns nil when the model is unavailable or the
    /// entry is too thin to say anything true about.
    static func reflect(on transcript: String) async -> EntryReflection? {
        guard isAvailable else { return nil }
        guard transcript.split(separator: " ").count >= 20 else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "The entry, transcribed exactly as spoken:\n\n\(transcript)"
        do {
            let response = try await session.respond(to: prompt, generating: EntryReflection.self)
            return response.content
        } catch {
            return nil
        }
    }

    /// Runs reflection for a saved entry and writes the result back onto it.
    @MainActor
    static func annotate(_ entry: JournalEntry) async {
        guard let reflection = await reflect(on: entry.transcript) else { return }
        entry.headline = reflection.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.observations = reflection.observations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        entry.tags = reflection.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }
}
