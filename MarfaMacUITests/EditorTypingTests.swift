import XCTest

/// Types into the real page with the real keyboard: the slash menu, canceling Link to Item, the table shortcut
/// and moving a block.
nonisolated final class EditorTypingTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var page: XCUIElement { window.webViews.firstMatch }
    @MainActor private var editor: XCUIElement { app.itemPageBody }
    @MainActor private var text: String { editor.value as? String ?? "" }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        beginNewItem(title: "Typing test")
    }

    @MainActor override func tearDown() async throws {
        app.terminate()
    }

    @MainActor private func beginNewItem(title: String) {
        window.quickAdd(type: "Note", title: title)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
    }

    @MainActor private func waitForText(_ predicate: String, _ argument: String, timeout: TimeInterval = 4) -> Bool {
        let expectation = expectation(for: NSPredicate(format: "value \(predicate) %@", argument), evaluatedWith: editor)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// A row of the page's own menu, which shows beside the caret while it is open.
    @MainActor private func menuRow(_ name: String) -> XCUIElement {
        page.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@ OR title == %@", name, name, name)).firstMatch
    }

    @MainActor func testTheSlashMenuListsBlocksInTheAppsWordsAndMakesATable() {
        app.typeText("/")
        for name in ["Heading 1", "Bulleted List", "Checklist", "Code Block", "Table", "Callout", "Diagram", "Link to Item"] {
            XCTAssertTrue(menuRow(name).waitForExistence(timeout: 3), name)
        }
        app.typeText("tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(page.tables.firstMatch.waitForExistence(timeout: 3), "the Table command made a table")
    }

    @MainActor func testTypingARowAndPressingReturnMakesATable() {
        app.typeText("| Name | Date |")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(page.tables.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor func testLinkToItemCancelledKeepsTheLineAsTyped() {
        app.typeText("/link")
        XCTAssertTrue(menuRow("Link to Item").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        let field = app.sheets.firstMatch.descendants(matching: .any)["ItemLinkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForText("CONTAINS", "/link"))
        app.typeText("!")
        XCTAssertTrue(waitForText("CONTAINS", "/link!"), "the page has the keyboard back")
    }

    @MainActor func testOptionUpAndOptionDownMoveTheBlock() {
        app.typeText("first")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("second")
        app.typeKey(.upArrow, modifierFlags: .option)
        XCTAssertTrue(waitForText("BEGINSWITH", "second"), text)
        app.typeKey(.downArrow, modifierFlags: .option)
        XCTAssertTrue(waitForText("BEGINSWITH", "first"), text)
    }
}
