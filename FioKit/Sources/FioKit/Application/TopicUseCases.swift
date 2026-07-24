import Foundation

/// Converts the old model-owned string tags into durable accepted topics.
/// It is intentionally idempotent so it can run during every launch.
public struct MigrateLegacyTagsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    public func execute() async throws {
        let allEntries = try await entries.allEntries()
        var allTopics = try await topics.allTopics()
        var hasChanges = false

        for entry in allEntries {
            for legacyName in entry.reflection.tags {
                guard let name = Topic.sanitizedName(legacyName) else { continue }
                let key = Topic.normalizedName(name)
                guard !key.isEmpty else { continue }

                if let index = allTopics.firstIndex(where: {
                    $0.status == .accepted && $0.normalizedName == key
                }) {
                    var topic = allTopics[index]
                    if !topic.entryIDs.contains(entry.id) {
                        topic.entryIDs.append(entry.id)
                        topic.entryIDs = unique(topic.entryIDs)
                        topic.updatedAt = .now
                        allTopics[index] = topic
                        hasChanges = true
                    }
                } else {
                    let topic = Topic(name: name, entryIDs: [entry.id])
                    allTopics.append(topic)
                    hasChanges = true
                }
            }
        }

        if hasChanges {
            try await topics.replaceAll(with: allTopics)
        }
    }
}

/// Replaces the accepted topics attached to one entry while preserving the
/// global topic vocabulary and all pending Dream suggestions.
public struct ReplaceEntryTopicsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    @discardableResult
    public func execute(entryID: UUID, names: [String]) async throws -> [Topic]? {
        guard try await entries.entry(withID: entryID) != nil else { return nil }

        var desired: [(name: String, key: String)] = []
        var desiredKeys: Set<String> = []
        for rawName in names {
            guard let name = Topic.sanitizedName(rawName) else { continue }
            let key = Topic.normalizedName(name)
            guard !key.isEmpty, desiredKeys.insert(key).inserted else { continue }
            desired.append((name, key))
        }

        var allTopics = try await topics.allTopics()

        for index in allTopics.indices where
            allTopics[index].status == .accepted
                && allTopics[index].entryIDs.contains(entryID)
                && !desiredKeys.contains(allTopics[index].normalizedName) {
            allTopics[index].entryIDs.removeAll { $0 == entryID }
            allTopics[index].updatedAt = .now
        }

        var result: [Topic] = []
        for item in desired {
            if let index = allTopics.firstIndex(where: {
                $0.status == .accepted && $0.normalizedName == item.key
            }) {
                var topic = allTopics[index]
                topic.entryIDs = unique(topic.entryIDs + [entryID])
                topic.updatedAt = .now
                allTopics[index] = topic
                result.append(topic)
            } else {
                let topic = Topic(name: item.name, entryIDs: [entryID])
                allTopics.append(topic)
                result.append(topic)
            }
        }

        let acceptedMemberships = allTopics.reduce(
            into: [String: Set<UUID>]()
        ) { memberships, topic in
            guard topic.status == .accepted else { return }
            memberships[topic.normalizedName, default: []]
                .formUnion(topic.entryIDs)
        }
        allTopics.removeAll { topic in
            guard topic.status == .suggested,
                  let memberships = acceptedMemberships[topic.normalizedName] else {
                return false
            }
            return Set(topic.entryIDs).isSubset(of: memberships)
        }
        try await topics.replaceAll(with: allTopics)
        return result
    }
}

/// Replaces the pending suggestion inbox after a completed local Dream.
/// Accepted topics are author-owned: the model may propose new connections,
/// but it never mutates accepted membership without explicit confirmation.
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
        try await topics.replaceAll(with: durableTopics + changed)
        return changed
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

public struct ResolveTopicSuggestionUseCase: Sendable {
    private let topics: TopicRepository

    public init(topics: TopicRepository) {
        self.topics = topics
    }

    @discardableResult
    public func accept(topicID: UUID, renamedTo rawName: String? = nil) async throws -> Topic? {
        let allTopics = try await topics.allTopics()
        guard let index = allTopics.firstIndex(where: { $0.id == topicID }) else { return nil }
        var topic = allTopics[index]
        let originalStatus = topic.status
        let originalKey = topic.normalizedName

        if let rawName {
            guard let name = Topic.sanitizedName(rawName) else { return nil }
            topic.name = name
        }
        topic.status = .accepted
        topic.updatedAt = .now

        if let duplicate = allTopics.first(where: {
            $0.id != topic.id
                && $0.status == .accepted
                && $0.normalizedName == topic.normalizedName
        }) {
            var merged = duplicate
            merged.entryIDs = unique(merged.entryIDs + topic.entryIDs)
            merged.updatedAt = .now
            let replacement = allTopics.compactMap { existing -> Topic? in
                if existing.id == topic.id {
                    return nil
                }
                if existing.id == merged.id {
                    return merged
                }
                if originalStatus == .accepted,
                   existing.status == .suggested,
                   existing.normalizedName == originalKey {
                    var suggestion = existing
                    suggestion.name = merged.name
                    suggestion.updatedAt = .now
                    return suggestion
                }
                return existing
            }
            try await topics.replaceAll(
                with: reconcilingSuggestions(in: replacement)
            )
            return merged
        }

        if originalStatus == .accepted {
            let replacement = allTopics.map { existing -> Topic in
                if existing.id == topic.id {
                    return topic
                }
                if existing.status == .suggested,
                   existing.normalizedName == originalKey {
                    var suggestion = existing
                    suggestion.name = topic.name
                    suggestion.updatedAt = .now
                    return suggestion
                }
                return existing
            }
            try await topics.replaceAll(
                with: reconcilingSuggestions(in: replacement)
            )
        } else {
            try await topics.save(topic)
        }
        return topic
    }

    public func dismiss(topicID: UUID) async throws {
        let allTopics = try await topics.allTopics()
        guard var topic = allTopics.first(where: { $0.id == topicID }) else { return }
        topic.status = .dismissed
        topic.updatedAt = .now
        try await topics.save(topic)
    }
}

public struct RemoveEntryFromTopicsUseCase: Sendable {
    private let topics: TopicRepository

    public init(topics: TopicRepository) {
        self.topics = topics
    }

    public func execute(entryID: UUID) async throws {
        var allTopics = try await topics.allTopics()
        for index in allTopics.indices where allTopics[index].entryIDs.contains(entryID) {
            var topic = allTopics[index]
            topic.entryIDs.removeAll { $0 == entryID }
            topic.updatedAt = .now
            if topic.status == .suggested && topic.entryIDs.count < 2 {
                allTopics[index].entryIDs = []
            } else {
                allTopics[index] = topic
            }
        }
        allTopics.removeAll {
            $0.status == .suggested && $0.entryIDs.isEmpty
        }
        try await topics.replaceAll(with: allTopics)
    }
}

/// Repairs topic references after interrupted multi-record operations. It runs
/// on refresh, making deletion cleanup retryable without a server or queue.
public struct ReconcileTopicMembershipsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    public func execute() async throws {
        let validEntryIDs = Set(try await entries.allEntries().map(\.id))
        var allTopics = try await topics.allTopics()
        for index in allTopics.indices {
            var topic = allTopics[index]
            let validMemberships = topic.entryIDs.filter(validEntryIDs.contains)
            if topic.status == .suggested && validMemberships.count < 2 {
                allTopics[index].entryIDs = []
            } else if validMemberships != topic.entryIDs {
                topic.entryIDs = validMemberships
                topic.updatedAt = .now
                allTopics[index] = topic
            }
        }
        allTopics.removeAll {
            $0.status == .suggested && $0.entryIDs.isEmpty
        }
        try await topics.replaceAll(with: allTopics)
    }
}

private func unique(_ ids: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return ids.filter { seen.insert($0).inserted }
}

private func reconcilingSuggestions(in topics: [Topic]) -> [Topic] {
    let durableTopics = topics.filter { $0.status != .suggested }
    let dismissedKeys = Set(
        durableTopics
            .filter { $0.status == .dismissed }
            .map(\.normalizedName)
    )
    let acceptedByKey = durableTopics.reduce(
        into: [String: Topic]()
    ) { accepted, topic in
        guard topic.status == .accepted else { return }
        if var existing = accepted[topic.normalizedName] {
            existing.entryIDs = unique(existing.entryIDs + topic.entryIDs)
            accepted[topic.normalizedName] = existing
        } else {
            accepted[topic.normalizedName] = topic
        }
    }

    var suggestionsByKey: [String: Topic] = [:]
    var suggestionOrder: [String] = []
    for suggestion in topics where suggestion.status == .suggested {
        let key = suggestion.normalizedName
        guard !dismissedKeys.contains(key) else { continue }
        if var existing = suggestionsByKey[key] {
            existing.entryIDs = unique(existing.entryIDs + suggestion.entryIDs)
            existing.updatedAt = max(existing.updatedAt, suggestion.updatedAt)
            suggestionsByKey[key] = existing
        } else {
            var canonical = suggestion
            canonical.name = acceptedByKey[key]?.name ?? suggestion.name
            suggestionsByKey[key] = canonical
            suggestionOrder.append(key)
        }
    }

    let suggestions = suggestionOrder.compactMap { key -> Topic? in
        guard let suggestion = suggestionsByKey[key] else { return nil }
        if let accepted = acceptedByKey[key],
           Set(suggestion.entryIDs).isSubset(of: Set(accepted.entryIDs)) {
            return nil
        }
        return suggestion
    }
    return durableTopics + suggestions
}
