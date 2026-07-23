import XCTest
@testable import FioKit

final class ReflectionTests: XCTestCase {
    func testSilentReflection() {
        XCTAssertTrue(Reflection.silent.isSilent)
        XCTAssertFalse(Reflection(headline: "You said a thing.").isSilent)
        XCTAssertFalse(Reflection(tags: ["Walks"]).isSilent)
    }

    func testSanitizedTrimsAndDropsEmpties() {
        let reflection = Reflection.sanitized(
            headline: "  You keep circling back to the deadline.  ",
            observations: ["  ", "You named it four times. ", ""],
            tags: [" Friday Deadline ", ""]
        )
        XCTAssertEqual(reflection.headline, "You keep circling back to the deadline.")
        XCTAssertEqual(reflection.observations, ["You named it four times."])
        XCTAssertEqual(reflection.tags, ["Friday Deadline"])
    }

    func testSanitizedCapsCounts() {
        let reflection = Reflection.sanitized(
            headline: "You named a pattern.",
            observations: [
                "This is observation one.",
                "This is observation two.",
                "This is observation three.",
                "This is observation four.",
                "This is observation five.",
            ],
            tags: ["t1", "t2", "t3", "t4"]
        )
        XCTAssertEqual(reflection.observations.count, Reflection.maxObservations)
        XCTAssertEqual(reflection.tags.count, Reflection.maxTags)
    }

    func testSanitizedDropsObservationEchoingHeadline() {
        let reflection = Reflection.sanitized(
            headline: "You slept badly again.",
            observations: ["you slept badly again.", "You walked anyway."],
            tags: []
        )
        XCTAssertEqual(reflection.observations, ["You walked anyway."])
    }

    func testSanitizedDeduplicatesCaseInsensitively() {
        let reflection = Reflection.sanitized(
            headline: "",
            observations: [
                "This is the same line.",
                "this is the same line.",
                "This line is different.",
            ],
            tags: ["Walks", "walks", "Runs"]
        )
        XCTAssertEqual(
            reflection.observations,
            ["This is the same line.", "This line is different."]
        )
        XCTAssertEqual(reflection.tags, ["Walks", "Runs"])
    }

    func testSanitizedDropsSentenceLengthTags() {
        let reflection = Reflection.sanitized(
            headline: "You returned to running.",
            observations: [],
            tags: ["The Morning Run", "this is much too long to be a tag"]
        )
        XCTAssertEqual(reflection.tags, ["The Morning Run"])
    }

    func testSanitizedRejectsFragmentOnlyModelOutput() {
        let reflection = Reflection.sanitized(
            headline: "Recording error",
            observations: ["Tipo", "fala", "gravar"],
            tags: ["Recording", "error"]
        )

        XCTAssertEqual(reflection, .silent)
    }
}
