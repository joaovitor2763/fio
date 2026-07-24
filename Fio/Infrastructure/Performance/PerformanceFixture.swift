#if DEBUG
import Foundation
import SwiftData
import FioKit

/// Creates deterministic local data only when explicitly requested through
/// `FIO_PERFORMANCE_FIXTURE_ENTRIES`. It never runs in normal app launches.
@MainActor
enum PerformanceFixture {
    static func seedIfRequested(in context: ModelContext) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawCount = environment["FIO_PERFORMANCE_FIXTURE_ENTRIES"],
              let entryCount = Int(rawCount),
              entryCount > 0 else {
            return
        }

        if environment["FIO_PERFORMANCE_FIXTURE_RESET"] == "1" {
            reset(in: context)
        }

        let existingCount = (try? context.fetchCount(FetchDescriptor<EntryRecord>())) ?? 0
        guard existingCount == 0 else { return }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var entryIDs: [UUID] = []
        entryIDs.reserveCapacity(entryCount)

        for index in 0..<entryCount {
            let id = deterministicUUID(index: index, namespace: 1)
            entryIDs.append(id)
            let createdAt = calendar.date(
                byAdding: .minute,
                value: -(index * 47),
                to: now
            ) ?? now
            let transcript = (0..<80)
                .map { "journal-\(index)-word-\($0)" }
                .joined(separator: " ")
            let reflection = Reflection(
                headline: "Reflection \(index)",
                observations: [
                    "A representative observation for entry \(index).",
                    "A second detail keeps the search index realistic.",
                ],
                tags: index.isMultiple(of: 8) ? ["Legacy \(index % 12)"] : []
            )
            let entry = Entry(
                id: id,
                createdAt: createdAt,
                duration: TimeInterval(45 + index % 240),
                transcript: Transcript(transcript),
                reflection: reflection,
                authorContext: index.isMultiple(of: 5)
                    ? "Context added after entry \(index)."
                    : ""
            )
            context.insert(EntryRecord(from: entry))
        }

        let topicCount = max(12, min(120, entryCount / 20))
        for topicIndex in 0..<topicCount {
            let memberships = stride(
                from: topicIndex,
                to: entryIDs.count,
                by: topicCount
            )
            .prefix(40)
            .map { entryIDs[$0] }
            let topic = Topic(
                id: deterministicUUID(index: topicIndex, namespace: 2),
                name: "Recurring topic \(topicIndex)",
                entryIDs: memberships,
                createdAt: now.addingTimeInterval(TimeInterval(-topicIndex * 3_600)),
                updatedAt: now.addingTimeInterval(TimeInterval(-topicIndex * 60))
            )
            context.insert(TopicRecord(from: topic))
        }

        try? context.save()
    }

    private static func reset(in context: ModelContext) {
        do {
            for record in try context.fetch(FetchDescriptor<EntryRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ReviewRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<TopicRecord>()) {
                context.delete(record)
            }
            try context.save()
        } catch {
            context.rollback()
        }
    }

    static func runOperationsIfRequested(store: JournalStore) async {
        guard ProcessInfo.processInfo.environment[
            "FIO_PERFORMANCE_OPERATIONS"
        ] == "1" else {
            return
        }

        for index in 0..<30 {
            PerformanceRecorder.measureSync("search_query") {
                _ = store.searchEntries(matching: "journal \(index)")
            }
            PerformanceRecorder.measureSync("usage_statistics") {
                _ = store.usageStatistics
            }
        }

        guard let entryID = store.timeline.first?.entries.first?.id else { return }
        for index in 0..<20 {
            await store.saveContext(
                "Performance context \(index)",
                forEntryID: entryID
            )
        }
    }

    private static func deterministicUUID(index: Int, namespace: UInt8) -> UUID {
        let suffix = UInt64(index)
        let tuple: uuid_t = (
            namespace, 0, 0, 0, 0, 0, 0, 0,
            UInt8((suffix >> 56) & 0xff),
            UInt8((suffix >> 48) & 0xff),
            UInt8((suffix >> 40) & 0xff),
            UInt8((suffix >> 32) & 0xff),
            UInt8((suffix >> 24) & 0xff),
            UInt8((suffix >> 16) & 0xff),
            UInt8((suffix >> 8) & 0xff),
            UInt8(suffix & 0xff)
        )
        return UUID(uuid: tuple)
    }
}
#endif
