import Foundation
import FioKit

/// Actor reentrancy alone does not serialize a transaction across suspension
/// points. This FIFO lock protects each complete topic read/modify/commit.
actor AsyncMutationLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

struct SearchDocument {
    let entry: Entry
    let content: String

    init(entry: Entry, topicNames: [String]) {
        self.entry = entry
        content = normalizedSearchText(
            [
                entry.transcript.text,
                entry.reflection.headline,
                entry.reflection.observations.joined(separator: " "),
                entry.reflection.tags.joined(separator: " "),
                topicNames.joined(separator: " "),
                entry.authorContext,
            ]
            .joined(separator: " ")
        )
    }
}

func normalizedSearchText(_ text: String) -> String {
    text
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
}

enum JournalStoreError: LocalizedError {
    case audioUnavailable
    case entryUnavailable
    case transcriptionUnavailable

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            "The original audio is no longer available."
        case .entryUnavailable:
            "This entry is no longer available."
        case .transcriptionUnavailable:
            "Fio could not replace this transcription."
        }
    }
}
