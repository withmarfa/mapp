import XCTest

nonisolated final class EmptyTrashTests: XCTestCase {
    @MainActor func testEmptyTrashCountsTheListedItemsAndDefaultsToCancel() {
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
        let message = app.sheets.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 listed items")).firstMatch
        XCTAssertTrue(message.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "EmptyTrashConfirmation"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
        XCTAssertTrue(empty.isEnabled)

        empty.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(empty.isEnabled)
    }
}
