import XCTest
@testable import SlateKit

final class RecordEntryUseCaseTests: XCTestCase {
    func testStoresANewEntry() async throws {
        let repository = InMemoryEntryRepository()
        let useCase = RecordEntryUseCase(entries: repository)

        let entry = try await useCase.execute(
            transcriptText: "Planning the day",
            duration: 58,
            at: date(2026, 7, 14, 7, 30)
        )

        XCTAssertNotNil(entry)
        XCTAssertEqual(repository.storage.count, 1)
        XCTAssertEqual(repository.storage.first?.transcript.text, "Planning the day")
        XCTAssertEqual(repository.storage.first?.duration, 58)
        XCTAssertTrue(repository.storage.first!.reflection.isSilent)
    }

    func testDropsEmptyTranscriptSilently() async throws {
        let repository = InMemoryEntryRepository()
        let useCase = RecordEntryUseCase(entries: repository)

        let entry = try await useCase.execute(transcriptText: "   \n ", duration: 4)

        XCTAssertNil(entry)
        XCTAssertTrue(repository.storage.isEmpty)
    }

    func testReRecordReplacesTheOldEntry() async throws {
        let repository = InMemoryEntryRepository()
        let old = makeEntry()
        try await repository.save(old)
        let useCase = RecordEntryUseCase(entries: repository)

        let entry = try await useCase.execute(
            transcriptText: "What I actually meant to say",
            duration: 70,
            replacing: old.id
        )

        XCTAssertEqual(repository.storage.map(\.id), [entry!.id])
    }

    func testFailedReRecordKeepsTheOldEntry() async throws {
        let repository = InMemoryEntryRepository()
        let old = makeEntry()
        try await repository.save(old)
        let useCase = RecordEntryUseCase(entries: repository)

        let entry = try await useCase.execute(transcriptText: "", duration: 0, replacing: old.id)

        XCTAssertNil(entry)
        XCTAssertEqual(repository.storage.map(\.id), [old.id])
    }
}

final class AnnotateEntryUseCaseTests: XCTestCase {
    func testWritesSanitizedReflectionBack() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry(words: 40)
        try await repository.save(entry)
        let reflector = StubReflectionService(result: Reflection(
            headline: "  You keep calling everyone's work urgent.  ",
            observations: ["You said urgent five times.", "", "You never said what can wait."],
            tags: ["Saying Yes", "saying yes", "The Figma Review"]
        ))
        let useCase = AnnotateEntryUseCase(entries: repository, reflector: reflector)

        let annotated = try await useCase.execute(entryID: entry.id)

        XCTAssertEqual(annotated?.reflection.headline, "You keep calling everyone's work urgent.")
        XCTAssertEqual(annotated?.reflection.observations.count, 2)
        XCTAssertEqual(annotated?.reflection.tags, ["Saying Yes", "The Figma Review"])
        XCTAssertEqual(repository.storage.first?.reflection, annotated?.reflection)
    }

    func testThinEntriesAreNeverSentToTheObserver() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry(words: 5)
        try await repository.save(entry)
        let reflector = StubReflectionService(result: Reflection(headline: "Should not appear."))
        let useCase = AnnotateEntryUseCase(entries: repository, reflector: reflector)

        let result = try await useCase.execute(entryID: entry.id)

        XCTAssertEqual(reflector.callCount, 0)
        XCTAssertTrue(result!.reflection.isSilent)
    }

    func testObserverSilenceLeavesEntryUntouched() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry(words: 40)
        try await repository.save(entry)
        let useCase = AnnotateEntryUseCase(
            entries: repository,
            reflector: StubReflectionService(result: nil)
        )

        let result = try await useCase.execute(entryID: entry.id)

        XCTAssertTrue(result!.reflection.isSilent)
        XCTAssertEqual(repository.saveCount, 1) // only the initial save
    }

    func testEmptyModelOutputIsNotPersisted() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry(words: 40)
        try await repository.save(entry)
        let useCase = AnnotateEntryUseCase(
            entries: repository,
            reflector: StubReflectionService(result: Reflection(headline: "  ", observations: ["  "], tags: []))
        )

        _ = try await useCase.execute(entryID: entry.id)

        XCTAssertEqual(repository.saveCount, 1)
        XCTAssertTrue(repository.storage.first!.reflection.isSilent)
    }

    func testMissingEntryReturnsNil() async throws {
        let useCase = AnnotateEntryUseCase(
            entries: InMemoryEntryRepository(),
            reflector: StubReflectionService()
        )
        let result = try await useCase.execute(entryID: UUID())
        XCTAssertNil(result)
    }
}

final class AmendEntryContextUseCaseTests: XCTestCase {
    func testStoresTrimmedContext() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry()
        try await repository.save(entry)
        let useCase = AmendEntryContextUseCase(entries: repository)

        let amended = try await useCase.execute(entryID: entry.id, context: "  I meant the other meeting.  ")

        XCTAssertEqual(amended?.authorContext, "I meant the other meeting.")
        XCTAssertEqual(repository.storage.first?.authorContext, "I meant the other meeting.")
    }
}

final class DeleteEntryUseCaseTests: XCTestCase {
    func testRemovesTheEntry() async throws {
        let repository = InMemoryEntryRepository()
        let entry = makeEntry()
        try await repository.save(entry)

        try await DeleteEntryUseCase(entries: repository).execute(entryID: entry.id)

        XCTAssertTrue(repository.storage.isEmpty)
    }
}

final class ComposeDueReviewsUseCaseTests: XCTestCase {
    private func makeWeekOfEntries() -> [Entry] {
        [
            makeEntry(createdAt: date(2026, 7, 13, 8, 0), duration: 120),  // Monday
            makeEntry(createdAt: date(2026, 7, 15, 8, 0), duration: 60),   // Wednesday
            makeEntry(createdAt: date(2026, 7, 18, 8, 0), duration: 180),  // Saturday
        ]
    }

    func testComposesAReviewForACompletedWeek() async throws {
        let entryRepository = InMemoryEntryRepository()
        for entry in makeWeekOfEntries() { try await entryRepository.save(entry) }
        let reviewRepository = InMemoryReviewRepository()
        let summarizer = StubWeekSummaryService(result: WeekSummary(
            title: "A week of walks",
            summary: "You walked a lot this week."
        ))
        let useCase = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: reviewRepository,
            summarizer: summarizer,
            policy: ReviewPolicy(calendar: utc)
        )

        let created = try await useCase.execute(now: date(2026, 7, 19, 20, 0)) // that Sunday

        XCTAssertEqual(created.count, 1)
        let review = created[0]
        XCTAssertEqual(review.title, "A week of walks")
        XCTAssertEqual(review.weekStart, date(2026, 7, 13, 0, 0))
        XCTAssertEqual(review.dailyMinutes, [2.0, 0, 1.0, 0, 0, 3.0, 0])
        XCTAssertEqual(reviewRepository.storage.count, 1)
    }

    func testDoesNothingMidweek() async throws {
        let entryRepository = InMemoryEntryRepository()
        for entry in makeWeekOfEntries() { try await entryRepository.save(entry) }
        let useCase = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: InMemoryReviewRepository(),
            summarizer: StubWeekSummaryService(result: WeekSummary(title: "T", summary: "S")),
            policy: ReviewPolicy(calendar: utc)
        )

        let created = try await useCase.execute(now: date(2026, 7, 16))

        XCTAssertTrue(created.isEmpty)
    }

    func testIsIdempotentAcrossRuns() async throws {
        let entryRepository = InMemoryEntryRepository()
        for entry in makeWeekOfEntries() { try await entryRepository.save(entry) }
        let reviewRepository = InMemoryReviewRepository()
        let useCase = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: reviewRepository,
            summarizer: StubWeekSummaryService(result: WeekSummary(title: "T", summary: "S")),
            policy: ReviewPolicy(calendar: utc)
        )

        _ = try await useCase.execute(now: date(2026, 7, 20))
        _ = try await useCase.execute(now: date(2026, 7, 21))

        XCTAssertEqual(reviewRepository.storage.count, 1)
    }

    func testSilentSummarizerCreatesNothing() async throws {
        let entryRepository = InMemoryEntryRepository()
        for entry in makeWeekOfEntries() { try await entryRepository.save(entry) }
        let reviewRepository = InMemoryReviewRepository()
        let useCase = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: reviewRepository,
            summarizer: StubWeekSummaryService(result: nil),
            policy: ReviewPolicy(calendar: utc)
        )

        let created = try await useCase.execute(now: date(2026, 7, 20))

        XCTAssertTrue(created.isEmpty)
        XCTAssertTrue(reviewRepository.storage.isEmpty)
    }

    func testEmptyTitleGetsTheFallback() async throws {
        let entryRepository = InMemoryEntryRepository()
        for entry in makeWeekOfEntries() { try await entryRepository.save(entry) }
        let useCase = ComposeDueReviewsUseCase(
            entries: entryRepository,
            reviews: InMemoryReviewRepository(),
            summarizer: StubWeekSummaryService(result: WeekSummary(title: "", summary: "Something happened.")),
            policy: ReviewPolicy(calendar: utc)
        )

        let created = try await useCase.execute(now: date(2026, 7, 20))

        XCTAssertEqual(created.first?.title, ComposeDueReviewsUseCase.fallbackTitle)
    }
}
