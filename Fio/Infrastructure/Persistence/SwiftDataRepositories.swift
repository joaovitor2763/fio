import Foundation
import SwiftData
import FioKit

/// SwiftData-backed adapter for the domain's EntryRepository port.
@MainActor
final class SwiftDataEntryRepository: EntryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allEntries() async throws -> [Entry] {
        let descriptor = FetchDescriptor<EntryRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor).map(\.asDomain)
    }

    func entry(withID id: UUID) async throws -> Entry? {
        try record(withID: id)?.asDomain
    }

    func save(_ entry: Entry) async throws {
        if let existing = try record(withID: entry.id) {
            existing.apply(entry)
        } else {
            context.insert(EntryRecord(from: entry))
        }
        try context.save()
    }

    func saveReflection(
        _ reflection: Reflection,
        forEntryID id: UUID,
        ifUnchangedFrom expectedEntry: Entry
    ) async throws -> Bool {
        guard let existing = try record(withID: id),
              existing.asDomain == expectedEntry else {
            return false
        }

        existing.headline = reflection.headline
        existing.observations = reflection.observations
        existing.tags = reflection.tags
        try context.save()
        return true
    }

    func deleteEntry(withID id: UUID) async throws {
        guard let existing = try record(withID: id) else { return }
        context.delete(existing)
        try context.save()
    }

    private func record(withID id: UUID) throws -> EntryRecord? {
        var descriptor = FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// SwiftData-backed adapter for the domain's ReviewRepository port.
@MainActor
final class SwiftDataReviewRepository: ReviewRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allReviews() async throws -> [WeekReview] {
        let descriptor = FetchDescriptor<ReviewRecord>(sortBy: [SortDescriptor(\.weekStart)])
        return try context.fetch(descriptor).map(\.asDomain)
    }

    func save(_ review: WeekReview) async throws {
        let id = review.id
        var descriptor = FetchDescriptor<ReviewRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.apply(review)
        } else {
            context.insert(ReviewRecord(from: review))
        }
        try context.save()
    }
}

/// SwiftData-backed adapter for durable topics and Dream suggestions.
@MainActor
final class SwiftDataTopicRepository: TopicRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allTopics() async throws -> [Topic] {
        let descriptor = FetchDescriptor<TopicRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.asDomain)
    }

    func save(_ topic: Topic) async throws {
        if let existing = try record(withID: topic.id) {
            existing.apply(topic)
        } else {
            context.insert(TopicRecord(from: topic))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteTopic(withID id: UUID) async throws {
        guard let existing = try record(withID: id) else { return }
        context.delete(existing)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func replaceAll(with topics: [Topic]) async throws {
        let existingRecords = try context.fetch(FetchDescriptor<TopicRecord>())
        let desiredIDs = Set(topics.map(\.id))
        var recordsByID = Dictionary(
            uniqueKeysWithValues: existingRecords.map { ($0.id, $0) }
        )

        for record in existingRecords where !desiredIDs.contains(record.id) {
            context.delete(record)
            recordsByID.removeValue(forKey: record.id)
        }
        for topic in topics {
            if let existing = recordsByID[topic.id] {
                existing.apply(topic)
            } else {
                context.insert(TopicRecord(from: topic))
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func record(withID id: UUID) throws -> TopicRecord? {
        var descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
