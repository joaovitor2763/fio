import XCTest
@testable import SlateKit

final class TranscriptTests: XCTestCase {
    func testTrimsWhitespaceOnInit() {
        XCTAssertEqual(Transcript("  hello world \n").text, "hello world")
    }

    func testWordCount() {
        XCTAssertEqual(Transcript("").wordCount, 0)
        XCTAssertEqual(Transcript("one").wordCount, 1)
        XCTAssertEqual(Transcript("one two  three\nfour").wordCount, 4)
    }

    func testSubstantialThreshold() {
        let nineteen = (1...19).map(String.init).joined(separator: " ")
        let twenty = (1...20).map(String.init).joined(separator: " ")
        XCTAssertFalse(Transcript(nineteen).isSubstantial)
        XCTAssertTrue(Transcript(twenty).isSubstantial)
    }

    func testPreviewShortTextIsUntouched() {
        XCTAssertEqual(Transcript("just a few words").preview(), "just a few words")
    }

    func testPreviewTruncatesWithEllipsis() {
        let text = (1...20).map { "w\($0)" }.joined(separator: " ")
        let preview = Transcript(text).preview(maxWords: 5)
        XCTAssertEqual(preview, "w1 w2 w3 w4 w5…")
    }

    func testExcerptCutsOnWordBoundary() {
        let text = "alpha beta gamma delta epsilon"
        let excerpt = Transcript(text).excerpt(maxCharacters: 13)
        XCTAssertEqual(excerpt, "alpha beta…")
    }

    func testExcerptLeavesShortTextAlone() {
        XCTAssertEqual(Transcript("short").excerpt(maxCharacters: 400), "short")
    }
}
