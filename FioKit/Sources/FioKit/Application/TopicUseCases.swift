import Foundation

public struct MigrateLegacyTagsUseCase: Sendable {
    private let entries: EntryRepository
    private let topics: TopicRepository

    public init(entries: EntryRepository, topics: TopicRepository) {
        self.entries = entries
        self.topics = topics
    }

    public func execute(entries providedEntries: [Entry]? = nil) async throws {
        let allEntries: [Entry]
        if let providedEntries {
            allEntries = providedEntries
        } else {
            allEntries = try await entries.allEntries()
        }
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
