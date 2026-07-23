import Foundation
import FoundationModels
import SwiftData

@Generable
struct WeekReflection {
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

/// On Sunday, Slate reads the week back to you. This composes that read-back
/// for every completed week that has enough entries and no review yet.
@MainActor
enum WeekComposer {
    static let minimumEntries = 3

    static func composePendingReviews(in context: ModelContext) async {
        guard Reflector.isAvailable else { return }

        let entries = (try? context.fetch(
            FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        guard !entries.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<WeeklyReview>())) ?? []

        let calendar = Calendar.mondayFirst
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .weekOfYear, for: entry.createdAt)?.start ?? entry.createdAt
        }

        let now = Date.now
        for (weekStart, weekEntries) in grouped.sorted(by: { $0.key < $1.key }) {
            guard weekEntries.count >= minimumEntries else { continue }
            guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }

            // A week becomes readable on its Sunday, and stays readable after.
            let sunday = week.end.addingTimeInterval(-1)
            let isReadable = week.end <= now || calendar.isDate(now, inSameDayAs: sunday)
            guard isReadable else { continue }

            guard !existing.contains(where: { calendar.isDate($0.weekStart, inSameDayAs: weekStart) }) else {
                continue
            }

            if let review = await compose(weekStart: weekStart, entries: weekEntries, calendar: calendar) {
                context.insert(review)
                try? context.save()
            }
        }
    }

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

    private static func compose(
        weekStart: Date,
        entries: [JournalEntry],
        calendar: Calendar
    ) async -> WeeklyReview? {
        var lines: [String] = []
        for entry in entries {
            let day = entry.createdAt.formatted(.dateTime.weekday(.wide))
            let excerpt = String(entry.transcript.prefix(400))
            var line = "\(day): \(excerpt)"
            if !entry.userContext.isEmpty {
                line += "\n\(day), added later by the author: \(entry.userContext)"
            }
            lines.append(line)
        }
        let prompt = "The week's entries, in order:\n\n" + lines.joined(separator: "\n\n")

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, generating: WeekReflection.self)
            let reflection = response.content
            guard !reflection.summary.isEmpty else { return nil }

            var minutes = [Double](repeating: 0, count: 7)
            for entry in entries {
                let weekdayIndex = (calendar.component(.weekday, from: entry.createdAt) + 5) % 7
                minutes[weekdayIndex] += entry.duration / 60
            }

            let title = reflection.title.isEmpty ? "The week read back" : reflection.title
            return WeeklyReview(
                weekStart: weekStart,
                title: title,
                summary: reflection.summary,
                dailyMinutes: minutes
            )
        } catch {
            return nil
        }
    }
}
