import XCTest

@MainActor
final class FioUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIO_UI_TESTING"] = "1"
        app.launchEnvironment["FIO_PERFORMANCE_FIXTURE_ENTRIES"] = "14"
        app.launchEnvironment["FIO_PERFORMANCE_FIXTURE_RESET"] = "1"
        app.launch()

        XCTAssertTrue(
            app.buttons["journal-search-button"].waitForExistence(timeout: 12),
            "The journal did not finish loading."
        )
        return app
    }

    func testSearchOpensEntryDetail() {
        let app = launchApp()
        app.buttons["journal-search-button"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("journal-5-word-0")

        let resultText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "journal-5-word-0")
        ).firstMatch
        XCTAssertTrue(resultText.waitForExistence(timeout: 5))
        app.buttons["journal-search-result"].tap()

        XCTAssertTrue(app.staticTexts["Transcript"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "journal-5-word-0")
            ).firstMatch.exists
        )
    }

    func testWriteAndDeleteEntry() {
        let app = launchApp()
        let recordButton = app.buttons["record-entry-button"]
        recordButton.press(forDuration: 0.8)

        XCTAssertTrue(app.navigationBars["Write"].waitForExistence(timeout: 4))
        let editor = app.textViews["text-entry-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.tap()

        let entryText = "A UI test entry that should be saved and deleted."
        editor.typeText(entryText)
        app.buttons["Save"].tap()

        let timelineEntry = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", entryText)
        ).firstMatch
        XCTAssertTrue(timelineEntry.waitForExistence(timeout: 6))
        timelineEntry.tap()
        XCTAssertTrue(app.staticTexts["Transcript"].waitForExistence(timeout: 4))

        let deleteButton = app.buttons["delete-entry-button"]
        for _ in 0..<4 where !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.isHittable)
        deleteButton.tap()

        let destructiveDelete = app.buttons.matching(
            identifier: "confirm-delete-entry-button"
        ).firstMatch
        XCTAssertTrue(destructiveDelete.waitForExistence(timeout: 3))
        destructiveDelete.tap()

        XCTAssertTrue(app.buttons["journal-search-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", entryText)
            ).firstMatch.exists
        )
    }

    func testUtilityScreensAndRecorder() {
        let app = launchApp()
        app.buttons["insights-button"].tap()
        XCTAssertTrue(
            app.staticTexts["Your private journal"].waitForExistence(timeout: 4)
        )
        app.buttons["Close"].tap()

        app.buttons["reviews-button"].tap()
        XCTAssertTrue(app.navigationBars["Reviews"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["No reviews yet."].exists)
        app.buttons["Close"].tap()

        app.buttons["record-entry-button"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Finish entry"].exists)
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["journal-search-button"].waitForExistence(timeout: 4))
    }

    func testBackupExplainsManualTransferAndAudioExclusion() {
        let app = launchApp()
        app.buttons["insights-button"].tap()

        let backupLink = app.buttons["backup-preference-link"]
        for _ in 0..<5 where !backupLink.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(backupLink.isHittable)
        backupLink.tap()

        XCTAssertTrue(app.navigationBars["Backup"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Export and import only"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "does not sync this backup automatically"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "Audio recordings are never included"
                )
            ).firstMatch.exists
        )
    }
}
