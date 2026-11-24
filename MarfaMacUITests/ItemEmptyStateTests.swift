import XCTest

nonisolated final class ItemEmptyStateTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    @MainActor private var list: XCUIElement { window.outlines["ItemList"] }
    @MainActor private var prompt: XCUIElement { window.staticTexts["No Item Selected"] }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws { app.terminate() }

    @MainActor func testItemsWithoutSelectionShowAQuietPrompt() {
        sidebar.staticTexts["Items"].click()
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Items without selection and matching toolbar background")
    }

    @MainActor func testAnEmptyCollectionLeavesTheContentPaneBlank() {
        window.quickAdd(type: "Collection", title: "Empty collection check")
        sidebar.staticTexts["Collections"].click()
        let index = window.descendants(matching: .any).matching(identifier: "SidebarIndex").firstMatch
        let collection = index.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Empty collection check")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        collection.doubleClick()
        XCTAssertTrue(window.staticTexts["No Items"].waitForExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Empty collection and blank content pane")
    }

    @MainActor func testAnEmptySearchLeavesTheContentPaneBlank() {
        sidebar.staticTexts["Items"].click()
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = window.textFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("No matching item for this empty state check")
        XCTAssertTrue(window.itemPageTitle.waitForNonExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        capture("Empty search and blank content pane")
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
