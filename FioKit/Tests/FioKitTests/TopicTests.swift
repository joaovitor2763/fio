import XCTest
@testable import FioKit

final class TopicTests: XCTestCase {
    func testNormalizationMatchesCaseAccentsAndPunctuation() {
        XCTAssertEqual(
            Topic.normalizedName("  Limítes-no Trabalho! "),
            "limites no trabalho"
        )
    }

    func testSanitizedNameCollapsesWhitespaceAndRejectsLongNames() {
        XCTAssertEqual(
            Topic.sanitizedName("  Projeto   Fio  "),
            "Projeto Fio"
        )
        XCTAssertNil(
            Topic.sanitizedName("um dois três quatro cinco seis sete")
        )
        XCTAssertNil(Topic.sanitizedName("✨ --"))
    }

    func testReplacingEntryReferencePreservesMembershipWithoutDuplicates() {
        let oldID = UUID()
        let newID = UUID()
        let otherID = UUID()
        let topic = Topic(
            name: "Project",
            entryIDs: [oldID, otherID, newID]
        )
        let updateDate = date(2026, 7, 24)

        let replaced = topic.replacingEntryReference(
            from: oldID,
            to: newID,
            updatedAt: updateDate
        )

        XCTAssertEqual(replaced.entryIDs, [newID, otherID])
        XCTAssertEqual(replaced.updatedAt, updateDate)
    }
}

final class ReplaceEntryTopicsUseCaseTests: XCTestCase {
    func testCreatesReusesAndDetachesDurableTopics() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        let useCase = ReplaceEntryTopicsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(
            entryID: first.id,
            names: ["Limites no trabalho"]
        )
        _ = try await useCase.execute(
            entryID: second.id,
            names: ["limítes no trabalho"]
        )

        XCTAssertEqual(topics.storage.count, 1)
        XCTAssertEqual(Set(topics.storage[0].entryIDs), Set([first.id, second.id]))

        _ = try await useCase.execute(entryID: first.id, names: [])

        XCTAssertEqual(topics.storage[0].name, "Limites no trabalho")
        XCTAssertEqual(topics.storage[0].entryIDs, [second.id])
    }

    func testManualTopicDoesNotAcceptPendingOrDismissedConnections() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        let manual = makeEntry(createdAt: date(2026, 7, 15))
        try await entries.save(first)
        try await entries.save(second)
        try await entries.save(manual)
        let topics = InMemoryTopicRepository()
        let suggested = Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [first.id, second.id]
        )
        let dismissed = Topic(
            name: "Rotina de exercícios",
            status: .dismissed,
            entryIDs: [first.id, second.id]
        )
        try await topics.save(suggested)
        try await topics.save(dismissed)
        let useCase = ReplaceEntryTopicsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(
            entryID: manual.id,
            names: ["Limites no trabalho", "Rotina de exercícios"]
        )

        XCTAssertEqual(topics.storage.first { $0.id == suggested.id }?.status, .suggested)
        XCTAssertEqual(topics.storage.first { $0.id == suggested.id }?.entryIDs, [first.id, second.id])
        XCTAssertEqual(topics.storage.first { $0.id == dismissed.id }?.status, .dismissed)
        XCTAssertEqual(topics.storage.first { $0.id == dismissed.id }?.entryIDs, [first.id, second.id])
        let manualTopics = topics.storage.filter {
            $0.status == .accepted && $0.entryIDs == [manual.id]
        }
        XCTAssertEqual(manualTopics.count, 2)
    }

    func testManualMembershipRemovesSuggestionItFullySatisfies() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let accepted = Topic(
            name: "Limites no trabalho",
            entryIDs: [first.id]
        )
        let suggestion = Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [first.id, second.id]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(accepted)
        try await topics.save(suggestion)
        let useCase = ReplaceEntryTopicsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(
            entryID: second.id,
            names: ["Limites no trabalho"]
        )

        XCTAssertFalse(topics.storage.contains { $0.status == .suggested })
        XCTAssertEqual(
            Set(topics.storage.first { $0.status == .accepted }?.entryIDs ?? []),
            Set([first.id, second.id])
        )
    }
}

final class SaveDreamSuggestionsUseCaseTests: XCTestCase {
    func testRejectsWordFrequencyStyleCandidates() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [
            TopicCandidate(name: "não", entryIDs: [first.id, second.id]),
            TopicCandidate(name: "Limites no trabalho", entryIDs: [first.id]),
        ])

        XCTAssertTrue(topics.storage.isEmpty)
    }

    func testCreatesSuggestionOnlyForContextAcrossEntries() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [
            TopicCandidate(
                name: "Limites no trabalho",
                entryIDs: [first.id, second.id]
            ),
        ])

        XCTAssertEqual(topics.storage.count, 1)
        XCTAssertEqual(topics.storage[0].status, .suggested)
        XCTAssertEqual(Set(topics.storage[0].entryIDs), Set([first.id, second.id]))
    }

    func testExistingAcceptedTopicRequiresConfirmationForNewConnections() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        try await topics.save(Topic(
            name: "Limites no trabalho",
            entryIDs: [first.id]
        ))
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [
            TopicCandidate(
                name: "limites no trabalho",
                entryIDs: [first.id, second.id]
            ),
        ])

        XCTAssertEqual(topics.storage.count, 2)
        XCTAssertEqual(
            topics.storage.first { $0.status == .accepted }?.entryIDs,
            [first.id]
        )
        XCTAssertEqual(
            Set(topics.storage.first { $0.status == .suggested }?.entryIDs ?? []),
            Set([first.id, second.id])
        )
    }

    func testDismissedSuggestionBlocksTheSameConnectionFromReturning() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        let dismissed = Topic(
            name: "Limites no trabalho",
            status: .dismissed,
            entryIDs: [first.id]
        )
        let accepted = Topic(name: "Limites no trabalho", entryIDs: [first.id])
        try await topics.save(dismissed)
        try await topics.save(accepted)
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [
            TopicCandidate(
                name: "limites no trabalho",
                entryIDs: [first.id, second.id]
            ),
        ])

        XCTAssertEqual(
            Set(topics.storage.first { $0.id == accepted.id }?.entryIDs ?? []),
            Set([first.id])
        )
        XCTAssertEqual(
            topics.storage.first { $0.id == dismissed.id }?.entryIDs,
            [first.id]
        )
        XCTAssertFalse(topics.storage.contains { $0.status == .suggested })
    }

    func testSuccessfulDreamReplacesStaleSuggestionsEvenWhenEmpty() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let topics = InMemoryTopicRepository()
        try await topics.save(Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [first.id, second.id]
        ))
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [])

        XCTAssertFalse(topics.storage.contains { $0.status == .suggested })
    }

    func testReturnsTheAuthoritativePersistedTopicSnapshot() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let accepted = Topic(name: "Projeto Fio", entryIDs: [first.id])
        let topics = InMemoryTopicRepository()
        try await topics.save(accepted)
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        let persistedTopics = try await useCase.execute(candidates: [
            TopicCandidate(
                name: "Limites no trabalho",
                entryIDs: [first.id, second.id]
            ),
        ])

        XCTAssertEqual(Set(persistedTopics.map(\.id)), Set(topics.storage.map(\.id)))
        XCTAssertTrue(persistedTopics.contains { $0.id == accepted.id })
        XCTAssertTrue(persistedTopics.contains { $0.status == .suggested })
    }

    func testEquivalentDreamKeepsSuggestionIdentityForOpenRoutes() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry()
        let second = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(first)
        try await entries.save(second)
        let existing = Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [first.id, second.id]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(existing)
        let useCase = SaveDreamSuggestionsUseCase(entries: entries, topics: topics)

        _ = try await useCase.execute(candidates: [
            TopicCandidate(
                name: "limites no trabalho",
                entryIDs: [first.id, second.id]
            ),
        ])

        XCTAssertEqual(topics.storage.count, 1)
        XCTAssertEqual(topics.storage[0].id, existing.id)
    }
}

final class MigrateLegacyTagsUseCaseTests: XCTestCase {
    func testMigrationIsIdempotentAndPreservesMembership() async throws {
        let entries = InMemoryEntryRepository()
        let first = makeEntry(reflection: Reflection(
            headline: "You kept returning to the same deadline.",
            tags: ["Projeto Fio"]
        ))
        try await entries.save(first)
        let topics = InMemoryTopicRepository()
        let useCase = MigrateLegacyTagsUseCase(entries: entries, topics: topics)

        try await useCase.execute()
        try await useCase.execute()

        XCTAssertEqual(topics.storage.count, 1)
        XCTAssertEqual(topics.storage[0].name, "Projeto Fio")
        XCTAssertEqual(topics.storage[0].entryIDs, [first.id])
    }

    func testMigrationDoesNotPromoteMatchingDreamSuggestion() async throws {
        let entries = InMemoryEntryRepository()
        let legacyEntry = makeEntry(reflection: Reflection(
            headline: "You kept returning to the same deadline.",
            tags: ["Projeto Fio"]
        ))
        let suggestedEntry = makeEntry(createdAt: date(2026, 7, 14))
        try await entries.save(legacyEntry)
        try await entries.save(suggestedEntry)
        let suggestion = Topic(
            name: "Projeto Fio",
            status: .suggested,
            entryIDs: [legacyEntry.id, suggestedEntry.id]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(suggestion)
        let useCase = MigrateLegacyTagsUseCase(entries: entries, topics: topics)

        try await useCase.execute()

        XCTAssertEqual(
            topics.storage.first { $0.id == suggestion.id }?.status,
            .suggested
        )
        XCTAssertEqual(
            topics.storage.first { $0.status == .accepted }?.entryIDs,
            [legacyEntry.id]
        )
    }
}

final class ResolveTopicSuggestionUseCaseTests: XCTestCase {
    func testRenamingAcceptedTopicKeepsPendingExtensionConnected() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let accepted = Topic(
            name: "Projeto Fio",
            entryIDs: [firstID]
        )
        let suggestion = Topic(
            name: "Projeto Fio",
            status: .suggested,
            entryIDs: [firstID, secondID]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(accepted)
        try await topics.save(suggestion)
        let useCase = ResolveTopicSuggestionUseCase(topics: topics)

        _ = try await useCase.accept(
            topicID: accepted.id,
            renamedTo: "Construção do Fio"
        )

        XCTAssertEqual(
            topics.storage.first { $0.id == suggestion.id }?.name,
            "Construção do Fio"
        )

        _ = try await useCase.accept(topicID: suggestion.id)

        let acceptedTopics = topics.storage.filter { $0.status == .accepted }
        XCTAssertEqual(acceptedTopics.count, 1)
        XCTAssertEqual(
            Set(acceptedTopics[0].entryIDs),
            Set([firstID, secondID])
        )
    }

    func testMergingAcceptedTopicsRemovesCoveredDuplicateSuggestions() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let source = Topic(name: "Projeto Fio", entryIDs: [firstID])
        let destination = Topic(
            name: "Construção do Fio",
            entryIDs: [secondID]
        )
        let sourceSuggestion = Topic(
            name: "Projeto Fio",
            status: .suggested,
            entryIDs: [firstID, secondID]
        )
        let destinationSuggestion = Topic(
            name: "Construção do Fio",
            status: .suggested,
            entryIDs: [firstID, secondID]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(source)
        try await topics.save(destination)
        try await topics.save(sourceSuggestion)
        try await topics.save(destinationSuggestion)
        let useCase = ResolveTopicSuggestionUseCase(topics: topics)

        _ = try await useCase.accept(
            topicID: source.id,
            renamedTo: "Construção do Fio"
        )

        XCTAssertEqual(
            topics.storage.filter { $0.status == .accepted }.count,
            1
        )
        XCTAssertFalse(topics.storage.contains { $0.status == .suggested })
    }
}

final class RemoveEntryFromTopicsUseCaseTests: XCTestCase {
    func testDeletingEntryRemovesSuggestionBelowRecurrenceThreshold() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let accepted = Topic(
            name: "Projeto Fio",
            entryIDs: [firstID, secondID]
        )
        let suggestion = Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [firstID, secondID]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(accepted)
        try await topics.save(suggestion)
        let useCase = RemoveEntryFromTopicsUseCase(topics: topics)

        try await useCase.execute(entryID: firstID)

        XCTAssertNil(topics.storage.first { $0.id == suggestion.id })
        XCTAssertEqual(
            topics.storage.first { $0.id == accepted.id }?.entryIDs,
            [secondID]
        )
    }
}

final class ReconcileTopicMembershipsUseCaseTests: XCTestCase {
    func testRefreshRepairRemovesDanglingMembershipsAndInvalidSuggestions() async throws {
        let entries = InMemoryEntryRepository()
        let existing = makeEntry()
        try await entries.save(existing)
        let missingID = UUID()
        let accepted = Topic(
            name: "Projeto Fio",
            entryIDs: [existing.id, missingID]
        )
        let suggestion = Topic(
            name: "Limites no trabalho",
            status: .suggested,
            entryIDs: [existing.id, missingID]
        )
        let topics = InMemoryTopicRepository()
        try await topics.save(accepted)
        try await topics.save(suggestion)
        let useCase = ReconcileTopicMembershipsUseCase(
            entries: entries,
            topics: topics
        )

        try await useCase.execute()

        XCTAssertEqual(
            topics.storage.first { $0.id == accepted.id }?.entryIDs,
            [existing.id]
        )
        XCTAssertNil(topics.storage.first { $0.id == suggestion.id })
    }

    func testNoOpReconciliationUsesProvidedSnapshotAndDoesNotWrite() async throws {
        let entries = InMemoryEntryRepository()
        let entry = makeEntry()
        try await entries.save(entry)
        let topics = InMemoryTopicRepository()
        let topic = Topic(name: "Stable topic", entryIDs: [entry.id])
        try await topics.save(topic)
        let useCase = ReconcileTopicMembershipsUseCase(
            entries: entries,
            topics: topics
        )

        let result = try await useCase.execute(validEntryIDs: [entry.id])

        XCTAssertEqual(result, [topic])
        XCTAssertEqual(entries.allEntriesCallCount, 0)
        XCTAssertEqual(topics.allTopicsCallCount, 1)
        XCTAssertEqual(topics.replaceAllCallCount, 0)
    }

    func testReadOnlyRepairMakesAFailedMaintenanceSnapshotSafe() {
        let existingID = UUID()
        let missingID = UUID()
        let accepted = Topic(
            name: "Project",
            entryIDs: [existingID, missingID]
        )
        let invalidSuggestion = Topic(
            name: "Maybe",
            status: .suggested,
            entryIDs: [existingID, missingID]
        )
        let useCase = ReconcileTopicMembershipsUseCase(
            entries: InMemoryEntryRepository(),
            topics: InMemoryTopicRepository()
        )

        let repaired = useCase.repairedSnapshot(
            [accepted, invalidSuggestion],
            validEntryIDs: [existingID]
        )

        XCTAssertEqual(repaired.count, 1)
        XCTAssertEqual(repaired.first?.id, accepted.id)
        XCTAssertEqual(repaired.first?.entryIDs, [existingID])
    }
}
