import Foundation

public struct ReconcileTopicMembershipsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    @discardableResult
    public func execute(
        validEntryIDs providedEntryIDs: Set<UUID>? = nil
    ) async throws -> [Topic] {
        let validEntryIDs: Set<UUID>
        if let providedEntryIDs {
            validEntryIDs = providedEntryIDs
        } else {
            validEntryIDs = Set(try await entries.allEntries().map(\.id))
        }
        let allTopics = try await topics.allTopics()
        let repairedTopics = repairedSnapshot(
            allTopics,
            validEntryIDs: validEntryIDs
        )
        if repairedTopics != allTopics {
            try await topics.replaceAll(with: repairedTopics)
        }
        return repairedTopics
    }

    /// Produces a safe read-only view when persistence maintenance fails.
    /// Callers may display this snapshot without committing the repair.
    public func repairedSnapshot(
        _ topics: [Topic],
        validEntryIDs: Set<UUID>,
        updatedAt: Date = .now
    ) -> [Topic] {
        var repairedTopics = topics
        for index in repairedTopics.indices {
            var topic = repairedTopics[index]
            let validMemberships = topic.entryIDs.filter(validEntryIDs.contains)
            if topic.status == .suggested && validMemberships.count < 2 {
                repairedTopics[index].entryIDs = []
            } else if validMemberships != topic.entryIDs {
                topic.entryIDs = validMemberships
                topic.updatedAt = updatedAt
                repairedTopics[index] = topic
            }
        }
        repairedTopics.removeAll {
            $0.status == .suggested && $0.entryIDs.isEmpty
        }
        return repairedTopics
    }
}
