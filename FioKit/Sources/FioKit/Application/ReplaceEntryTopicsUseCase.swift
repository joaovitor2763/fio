import Foundation

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

        for item in desired {
            if let index = allTopics.firstIndex(where: {
                $0.status == .accepted && $0.normalizedName == item.key
            }) {
                var topic = allTopics[index]
                topic.entryIDs = unique(topic.entryIDs + [entryID])
                topic.updatedAt = .now
                allTopics[index] = topic
            } else {
                let topic = Topic(name: item.name, entryIDs: [entryID])
                allTopics.append(topic)
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
        return allTopics
    }
}

/// Replaces the pending suggestion inbox after a completed local Dream.
/// Accepted topics are author-owned: the model may propose new connections,
/// but it never mutates accepted membership without explicit confirmation.
