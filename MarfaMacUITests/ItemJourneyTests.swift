import XCTest

nonisolated final class ItemJourneyTests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws { app.terminate() }

    @MainActor func testCreateEditAndReopen() {
        create(type: "Project", title: "Interface Test Project")
        create(type: "Task", title: "Interface Test Task")
        let editor = app.itemPageBody
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("A document written through the existing editor.")
        let typedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: editor)
        wait(for: [typedBody], timeout: 5)

        reopen("Interface Test Task")
        let reopened = app.itemPageBody
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
    }

    @MainActor func testANewItemOpensInThePageAndHeaderEditsSurviveReopening() {
        app.quickAdd(type: "Task", title: "Body Focus Draft")
        let pageTitle = app.itemPageTitle
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        let editor = app.itemPageBody
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Created by starting the document body.")
        let typedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created by starting the document body."), evaluatedWith: editor)
        wait(for: [typedBody], timeout: 5)

        let title = app.itemPageTitle
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Body Focus Saved Task")
        title.typeKey(.return, modifierFlags: [])
        let row = app.outlines["ItemList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Body Focus Saved Task")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        // A new task has no status, so its pin is an empty chip, which opens the panel that sets it.
        let status = app.itemStatusPin
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.click()
        let completed = app.descendants(matching: .any)["ValueEditRow.option:completed"]
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        completed.click()
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Completed") || status.value as? String == "Completed")
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Item page with pins"
        attachment.lifetime = .keepAlways
        add(attachment)
        reopen("Body Focus Saved Task")
        let reopened = app.itemPageBody
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created by starting the document body."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        let reopenedStatus = app.itemStatusPin
        XCTAssertTrue(reopenedStatus.waitForExistence(timeout: 3))
        XCTAssertTrue(reopenedStatus.label.contains("Completed") || reopenedStatus.value as? String == "Completed")
    }

    /// Leaves the item for another and comes back, so the page reads it again from the library. The sample
    /// library lives only as long as the app, so a relaunch would find none of it.
    @MainActor private func reopen(_ title: String) {
        let rows = app.outlines["ItemList"].staticTexts
        let other = rows.matching(NSPredicate(format: "NOT (value BEGINSWITH %@)", title)).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.click()
        let row = rows.matching(NSPredicate(format: "value BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
    }

    @MainActor private func create(type: String, title: String) {
        app.quickAdd(type: type, title: title)
        XCTAssertTrue(app.itemPageTitle.waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
    }
}
