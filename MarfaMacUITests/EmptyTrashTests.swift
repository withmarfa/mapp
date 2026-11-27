import XCTest

nonisolated final class EmptyTrashTests: XCTestCase {
    @MainActor func testEmptyTrashCountsTheListedItemsAndEscapeCancels() {
        continueAfterFailure = false
        let app = XCUIApplication.sample()
        app.launch()
        defer { app.terminate() }

        app.typeKey(",", modifierFlags: .command)
        let trash = app.descendants(matching: .any)["SettingsPage-trash"].firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.click()

        let empty = app.buttons["TrashEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isEnabled)
        empty.click()
        let confirm = app.sheets.buttons["Empty Trash"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "EmptyTrashConfirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        let count = "2 listed items"
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", count, count)
        let message = app.sheets.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(message.exists, app.sheets.firstMatch.debugDescription)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
        XCTAssertTrue(empty.isEnabled)

        empty.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(empty.isEnabled)
    }
}
