import XCTest
@testable import SlateKit

final class EntryTests: XCTestCase {
    func testTimelineLinePrefersHeadline() {
        let entry = makeEntry(reflection: Reflection(headline: "You kept circling the same worry."))
        XCTAssertEqual(entry.timelineLine, "You kept circling the same worry.")
    }

    func testTimelineLineFallsBackToTranscriptPreview() {
        let entry = Entry(
            createdAt: date(2026, 7, 13),
            duration: 30,
            transcript: Transcript("today was a slow day")
        )
        XCTAssertEqual(entry.timelineLine, "today was a slow day")
    }

    func testTimelineLineForEmptyEverything() {
        let entry = Entry(createdAt: date(2026, 7, 13), duration: 5, transcript: Transcript("   "))
        XCTAssertEqual(entry.timelineLine, "A quiet entry.")
    }

    func testDisplayObservationsPutHeadlineFirst() {
        let entry = makeEntry(reflection: Reflection(
            headline: "First.",
            observations: ["Second.", "Third."]
        ))
        XCTAssertEqual(entry.displayObservations, ["First.", "Second.", "Third."])
    }

    func testDisplayObservationsEmptyWhenSilent() {
        XCTAssertTrue(makeEntry().displayObservations.isEmpty)
    }
}
