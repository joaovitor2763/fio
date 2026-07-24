import XCTest
@testable import FioKit

final class VocabularyProcessorTests: XCTestCase {
    func testAppliesWholeTermsCaseInsensitively() {
        let result = VocabularyProcessor.apply(
            to: "O g4s conversa com o open claw.",
            rules: [
                VocabularyRule(source: "G4S", replacement: "G4OS"),
                VocabularyRule(source: "open claw", replacement: "OpenClaw"),
            ]
        )

        XCTAssertEqual(result.text, "O G4OS conversa com o OpenClaw.")
        XCTAssertEqual(result.appliedCount, 2)
    }

    func testDoesNotReplaceInsideAnotherWord() {
        let result = VocabularyProcessor.apply(
            to: "O AG4S continua igual.",
            rules: [VocabularyRule(source: "G4S", replacement: "G4OS")]
        )

        XCTAssertEqual(result.text, "O AG4S continua igual.")
        XCTAssertEqual(result.appliedCount, 0)
    }

    func testDoesNotCascadeRules() {
        let result = VocabularyProcessor.apply(
            to: "alpha",
            rules: [
                VocabularyRule(source: "alpha", replacement: "beta"),
                VocabularyRule(source: "beta", replacement: "gamma"),
            ]
        )

        XCTAssertEqual(result.text, "beta")
        XCTAssertEqual(result.appliedCount, 1)
    }

    func testDoesNotReapplySourceContainedInReplacement() {
        let rules = [
            VocabularyRule(source: "NY", replacement: "New York, NY"),
        ]
        let firstPass = VocabularyProcessor.apply(
            to: "A reunião foi em NY.",
            rules: rules
        )
        let secondPass = VocabularyProcessor.apply(
            to: firstPass.text,
            rules: rules
        )

        XCTAssertEqual(firstPass.text, "A reunião foi em New York, NY.")
        XCTAssertEqual(secondPass.text, firstPass.text)
        XCTAssertEqual(secondPass.appliedCount, 0)

        let lowercaseExistingResult = VocabularyProcessor.apply(
            to: "A reunião foi em new york, ny.",
            rules: rules
        )
        XCTAssertEqual(
            lowercaseExistingResult.text,
            "A reunião foi em new york, ny."
        )
        XCTAssertEqual(lowercaseExistingResult.appliedCount, 0)
    }

    func testCaseOnlyCorrectionStillApplies() {
        let result = VocabularyProcessor.apply(
            to: "Vamos usar openclaw.",
            rules: [
                VocabularyRule(
                    source: "openclaw",
                    replacement: "OpenClaw"
                ),
            ]
        )

        XCTAssertEqual(result.text, "Vamos usar OpenClaw.")
        XCTAssertEqual(result.appliedCount, 1)
    }

    func testFreshSourceStillAppliesWhenItMatchesAnotherReplacement() {
        let result = VocabularyProcessor.apply(
            to: "beta",
            rules: [
                VocabularyRule(source: "alpha", replacement: "beta"),
                VocabularyRule(source: "beta", replacement: "gamma"),
            ]
        )

        XCTAssertEqual(result.text, "gamma")
        XCTAssertEqual(result.appliedCount, 1)
    }

    func testDetectsCrossMatchingRules() {
        XCTAssertTrue(
            VocabularyProcessor.conflicts(
                VocabularyRule(source: "beta", replacement: "gamma"),
                with: [
                    VocabularyRule(source: "alpha", replacement: "beta"),
                ]
            )
        )
        XCTAssertFalse(
            VocabularyProcessor.conflicts(
                VocabularyRule(source: "delta", replacement: "epsilon"),
                with: [
                    VocabularyRule(source: "alpha", replacement: "beta"),
                ]
            )
        )
    }

    func testPrefersLongestOverlappingTerm() {
        let result = VocabularyProcessor.apply(
            to: "open claw",
            rules: [
                VocabularyRule(source: "open", replacement: "OPEN"),
                VocabularyRule(source: "open claw", replacement: "OpenClaw"),
            ]
        )

        XCTAssertEqual(result.text, "OpenClaw")
        XCTAssertEqual(result.appliedCount, 1)
    }

    func testSuggestsOneCompactCorrection() {
        let suggestion = VocabularyProcessor.suggestion(
            from: "Hoje falei sobre o G4S no Slack.",
            to: "Hoje falei sobre o G4OS no Slack.",
            existingRules: []
        )

        XCTAssertEqual(
            suggestion,
            VocabularySuggestion(source: "G4S", replacement: "G4OS")
        )
    }

    func testDoesNotSuggestLargeRewriteOrExistingSource() {
        XCTAssertNil(
            VocabularyProcessor.suggestion(
                from: "um dois três quatro cinco",
                to: "outro texto totalmente diferente aqui",
                existingRules: []
            )
        )
        XCTAssertNil(
            VocabularyProcessor.suggestion(
                from: "Usei G4S hoje.",
                to: "Usei G4OS hoje.",
                existingRules: [
                    VocabularyRule(source: "g4s", replacement: "G4OS"),
                ]
            )
        )
    }
}
