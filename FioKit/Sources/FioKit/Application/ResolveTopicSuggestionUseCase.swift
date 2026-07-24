import Foundation

public struct TopicAcceptanceResult: Sendable {
    public let acceptedTopic: Topic
    public let topics: [Topic]
}

public struct ResolveTopicSuggestionUseCase: Sendable {
    private let topics: TopicRepository

    public init(topics: TopicRepository) {
        self.topics = topics
    }

    @discardableResult
    public func accept(
        topicID: UUID,
        renamedTo rawName: String? = nil
    ) async throws -> TopicAcceptanceResult? {
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
            let persisted = reconcilingSuggestions(in: replacement)
            try await topics.replaceAll(with: persisted)
            return TopicAcceptanceResult(
                acceptedTopic: merged,
                topics: persisted
            )
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
            let persisted = reconcilingSuggestions(in: replacement)
            try await topics.replaceAll(with: persisted)
            return TopicAcceptanceResult(
                acceptedTopic: topic,
                topics: persisted
            )
        } else {
            try await topics.save(topic)
            let persisted = allTopics.map {
                $0.id == topic.id ? topic : $0
            }
            return TopicAcceptanceResult(
                acceptedTopic: topic,
                topics: persisted
            )
        }
    }

    @discardableResult
    public func dismiss(topicID: UUID) async throws -> [Topic] {
        var allTopics = try await topics.allTopics()
        guard let index = allTopics.firstIndex(where: { $0.id == topicID }) else {
            return allTopics
        }
        var topic = allTopics[index]
        topic.status = .dismissed
        topic.updatedAt = .now
        try await topics.save(topic)
        allTopics[index] = topic
        return allTopics
    }
}
