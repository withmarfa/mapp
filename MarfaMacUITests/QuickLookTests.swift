import XCTest

nonisolated final class QuickLookTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var list: XCUIElement { window.outlines["ItemList"] }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws { app.terminate() }

    @MainActor func testSpaceOnASelectedItemShowsItInQuickLookAndSpaceClosesIt() throws {
        let row = list.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        list.typeKey(" ", modifierFlags: [])
        // The panel is titled Quick Look and shows the item as a markdown file named after it. Its service starts cold, so it can be slow.
        let panel = app.windows["Quick Look"]
        XCTAssertTrue(panel.waitForExistence(timeout: 40))
        let preview = panel.webViews.firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.label.hasSuffix(".md"), "Quick Look shows \(preview.label)")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }
}
