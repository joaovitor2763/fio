import Foundation

public struct SaveDreamSuggestionsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    @discardableResult
    public func execute(candidates: [TopicCandidate]) async throws -> [Topic] {
        let validEntryIDs = Set(try await entries.allEntries().map(\.id))
        let allTopics = try await topics.allTopics()
        var changed: [Topic] = []

        // Suggestions are an ephemeral reading of the latest corpus. A
        // successful Dream, including an empty result, supersedes the prior
        // pending inbox while accepted and dismissed decisions remain durable.
        let previousSuggestions = allTopics.filter { $0.status == .suggested }
        let durableTopics = allTopics.filter { $0.status != .suggested }

        var processedKeys: Set<String> = []
        for candidate in candidates {
            guard let name = Topic.sanitizedName(candidate.name) else { continue }
            let key = Topic.normalizedName(name)
            let entryIDs = unique(candidate.entryIDs.filter(validEntryIDs.contains))
            guard dreamNameIsMeaningful(name),
                  entryIDs.count >= 2,
                  processedKeys.insert(key).inserted else {
                continue
            }

            guard !durableTopics.contains(where: {
                $0.status == .dismissed && $0.normalizedName == key
            }) else {
                continue
            }

            let accepted = durableTopics.first {
                $0.status == .accepted && $0.normalizedName == key
            }
            if let accepted,
               Set(entryIDs).isSubset(of: Set(accepted.entryIDs)) {
                continue
            }

            var topic = previousSuggestions.first {
                $0.normalizedName == key
            } ?? Topic(
                name: accepted?.name ?? name,
                status: .suggested
            )
            topic.name = accepted?.name ?? name
            topic.entryIDs = entryIDs
            topic.updatedAt = .now
            changed.append(topic)
        }
        let persistedTopics = durableTopics + changed
        try await topics.replaceAll(with: persistedTopics)
        return persistedTopics
    }

    /// Dream suggestions must describe a contextual phrase. Manual topics are
    /// intentionally more permissive because the author is the authority.
    private func dreamNameIsMeaningful(_ name: String) -> Bool {
        let words = Topic.normalizedName(name).split(separator: " ").map(String.init)
        guard words.count >= 2 else { return false }
        let functionWords: Set<String> = [
            "a", "as", "o", "os", "um", "uma", "de", "da", "das", "do", "dos",
            "e", "em", "que", "na", "nas", "no", "nos", "não", "para", "por",
            "the", "a", "an", "and", "of", "in", "on", "not", "to", "for",
            "el", "la", "los", "las", "de", "del", "en", "no", "para", "por",
        ]
        return words.contains { !functionWords.contains($0) && $0.count > 2 }
    }
}
