import XCTest

@MainActor
final class ItemEmptyStateTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var prompt: XCUIElement { window.staticTexts["No Item Selected"] }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws { app.terminate() }

    func testItemsWithoutSelectionShowAQuietPrompt() {
        sidebar.staticTexts["Items"].click()
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Items without selection and matching toolbar background")
    }

    func testAnEmptyCollectionLeavesTheContentPaneBlank() {
        window.quickAdd(type: "Collection", title: "Empty collection check")
        sidebar.staticTexts["Collections"].click()
        let index = window.descendants(matching: .any).matching(identifier: "SidebarIndex").firstMatch
        let collection = index.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Empty collection check")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        collection.click()
        XCTAssertTrue(window.staticTexts["No Items"].waitForExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Empty collection and blank content pane")
    }

    func testAnEmptySearchLeavesTheContentPaneBlank() {
        sidebar.staticTexts["Items"].click()
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = window.textFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("No matching item for this empty state check")
        XCTAssertTrue(window.itemPageTitle.waitForNonExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        capture("Empty search and blank content pane")
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
