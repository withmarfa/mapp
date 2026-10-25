import XCTest

@MainActor
final class ItemEmptyStateTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var prompt: XCUIElement { window.staticTexts["SelectItemPrompt"] }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleLibrary"]
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testItemsWithoutSelectionShowAQuietPrompt() {
        sidebar.staticTexts["Items"].click()
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertEqual(prompt.value as? String, "No Item Selected")
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Items without selection and matching toolbar background")
    }

    func testAnEmptyCollectionLeavesTheContentPaneBlank() {
        app.typeKey("n", modifierFlags: [.command, .shift])
        let name = sidebar.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Empty collection check")
        name.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(name.waitForNonExistence(timeout: 3))
        XCTAssertTrue(window.staticTexts["No Items"].waitForExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        XCTAssertFalse(window.itemPageTitle.exists)
        capture("Empty collection and blank content pane")
    }

    func testAnEmptySearchLeavesTheContentPaneBlank() {
        sidebar.staticTexts["Items"].click()
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = window.searchFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("No matching item for this empty state check")
        XCTAssertTrue(window.itemPageTitle.waitForNonExistence(timeout: 3))
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(window.staticTexts["No Note Selected"].exists)
        capture("Empty search and blank content pane")
        window.buttons["CloseColumnSearch"].click()
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
