import Foundation

public struct RemoveEntryFromTopicsUseCase: Sendable {
    private let topics: TopicRepository

    public init(topics: TopicRepository) {
        self.topics = topics
    }

    @discardableResult
    public func execute(entryID: UUID) async throws -> [Topic] {
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
        return allTopics
    }
}

/// Repairs topic references after interrupted multi-record operations. It runs
/// on refresh, making deletion cleanup retryable without a server or queue.
