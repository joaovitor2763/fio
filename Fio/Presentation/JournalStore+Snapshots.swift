import Foundation
import FioKit

extension JournalStore {
    func withRefreshMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await refreshLock.acquire()
        do {
            let result = try await operation()
            await refreshLock.release()
            return result
        } catch {
            await refreshLock.release()
            throw error
        }
    }

    /// Re-fetches if a suspended read overlaps a local mutation. Applying the
    /// snapshot is then synchronous on MainActor, so older data cannot replace
    /// a save or delete that completed while persistence was being read.
    func loadAndApplyStableEntrySnapshot() async throws {
        while true {
            let revision = entrySnapshotRevision
            let loadedEntries = try await PerformanceRecorder.measure(
                "entries_fetch"
            ) {
                try await entryRepository.allEntries()
            }
            guard revision == entrySnapshotRevision else { continue }
            PerformanceRecorder.measureSync("snapshot_build") {
                applyEntrySnapshot(loadedEntries)
            }
            return
        }
    }

    func applyEntrySnapshot(_ loadedEntries: [Entry]) {
        entries = loadedEntries
        // Search remains useful even if optional topic maintenance fails.
        // Topic names are added by applyTopics when that snapshot is ready.
        rebuildEntryReadModels(prepareStatistics: false)
    }

    func upsertEntry(_ entry: Entry, removing removedID: UUID? = nil) {
        PerformanceRecorder.measureSync("entry_snapshot_update") {
            if let removedID {
                entries.removeAll { $0.id == removedID }
            }
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            rebuildEntryReadModels()
        }
    }

    func removeEntryFromSnapshot(_ entryID: UUID) {
        PerformanceRecorder.measureSync("entry_snapshot_update") {
            entries.removeAll { $0.id == entryID }
            rebuildEntryReadModels()
        }
    }

    func rebuildEntryReadModels(
        rebuildSearchIndex: Bool = true,
        prepareStatistics: Bool = true
    ) {
        entrySnapshotRevision &+= 1
        isUsageStatisticsReady = false
        usageStatisticsTask?.cancel()
        usageStatisticsCalculationTask?.cancel()
        entriesByID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.id, $0) }
        )
        timeline = TimelineBuilder.days(from: entries, calendar: calendar)
        daysWithEntries = Set(timeline.map(\.day))
        if rebuildSearchIndex {
            rebuildSearchDocuments()
        }
        if prepareStatistics {
            prepareUsageStatistics()
        }
    }

    func reloadTopics() async throws {
        try await withTopicMutation {
            let loadedTopics = try await PerformanceRecorder.measure(
                "topics_reload"
            ) {
                try await topicRepository.allTopics()
            }
            applyTopics(loadedTopics)
        }
    }

    func applyTopics(_ loadedTopics: [Topic]) {
        topics = loadedTopics.sorted {
            if $0.status != $1.status {
                return $0.status == .suggested
            }
            return $0.updatedAt > $1.updatedAt
        }
        acceptedTopicsCache = loadedTopics
            .filter { $0.status == .accepted }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        acceptedTopicsByEntryID = Dictionary(
            grouping: acceptedTopicsCache.flatMap { topic in
                topic.entryIDs.map { ($0, topic) }
            },
            by: \.0
        )
        .mapValues { pairs in pairs.map(\.1) }

        rebuildSearchDocuments()
    }

    func replaceTopicEntryReferenceInSnapshot(from oldID: UUID, to newID: UUID) {
        let updatedTopics = topics.map { topic in
            topic.replacingEntryReference(from: oldID, to: newID)
        }
        applyTopics(updatedTopics)
    }

    func rebuildSearchDocuments() {
        let topicNamesByEntry = acceptedTopicsByEntryID.mapValues {
            $0.map(\.name)
        }
        searchDocuments = entries
            .sorted { $0.createdAt > $1.createdAt }
            .map {
                SearchDocument(
                    entry: $0,
                    topicNames: topicNamesByEntry[$0.id] ?? []
                )
            }
    }

    func withTopicMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await PerformanceRecorder.measure("topic_lock_acquire") {
            await topicMutationLock.acquire()
        }
        do {
            let result = try await PerformanceRecorder.measure(
                "topic_mutation_operation",
                operation: operation
            )
            await PerformanceRecorder.measure("topic_lock_release") {
                await topicMutationLock.release()
            }
            return result
        } catch {
            await PerformanceRecorder.measure("topic_lock_release") {
                await topicMutationLock.release()
            }
            throw error
        }
    }

    func withReviewMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await reviewMutationLock.acquire()
        do {
            let result = try await operation()
            await reviewMutationLock.release()
            return result
        } catch {
            await reviewMutationLock.release()
            throw error
        }
    }

}
