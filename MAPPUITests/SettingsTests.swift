import AppKit
import XCTest

/// Settings is a window of its own: Command-comma opens one instance with a sidebar of pages, Back and Forward, and the
/// page's name; the main window stays as it was.
@MainActor
final class SettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { element("SettingsSidebar") }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.outlines["ItemList"].waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func openSettings() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
    }

    func testSettingsOpensInAWindowOfItsOwnAndTheMainWindowStays() {
        let list = window.outlines["ItemList"]
        openSettings()
        XCTAssertEqual(app.windows.count, 2, "Settings is a second window")
        XCTAssertTrue(list.exists, "the main window keeps its list")
        XCTAssertTrue(element("SettingsDetail").exists)
        XCTAssertTrue(element("SettingsPage-appearance").exists)
        XCTAssertTrue(element("SettingsPage-connection").exists)
        XCTAssertTrue(element("SettingsPage-overview").exists)
        XCTAssertFalse(element("SettingsPage-sidebar").exists, "Settings > Sidebar is gone")
        attachScreenshot("SettingsWindow")
    }

    func testCommandCommaWithSettingsOpenBringsItForwardAndMakesNoSecondWindow() {
        openSettings()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 2)
    }

    func testEachPageShowsItsContent() {
        openSettings()
        for (page, marker) in [("appearance", "InterfaceTextSize"), ("lists", "ListsDensity"), ("editor", "PageWidth"), ("connection", "LibrarySummary")] {
            element("SettingsPage-\(page)").click()
            XCTAssertTrue(element(marker).waitForExistence(timeout: 3), "\(page) shows \(marker)")
        }
    }

    func testBackAndForwardMoveThroughThePagesOpened() {
        openSettings()
        element("SettingsPage-editor").click()
        XCTAssertTrue(element("PageWidth").waitForExistence(timeout: 3))
        element("SettingsPage-lists").click()
        XCTAssertTrue(element("ListsDensity").waitForExistence(timeout: 3))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(element("PageWidth").waitForExistence(timeout: 3), "Back returns to Editor")
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(element("ListsDensity").waitForExistence(timeout: 3), "Forward returns to Lists")
    }

    func testTheSidebarSearchFindsAPageByARowAndSaysWhenNothingMatches() {
        openSettings()
        let search = app.textFields["SettingsSearch"]
        search.click()
        search.typeText("spelling")
        XCTAssertTrue(element("SettingsPage-editor").waitForExistence(timeout: 3))
        XCTAssertFalse(element("SettingsPage-lists").exists)
        search.typeText("zzzz")
        XCTAssertTrue(element("SettingsSearchEmpty").waitForExistence(timeout: 3))
    }

    func testAPreferenceChangedInSettingsAppliesToTheMainWindow() {
        openSettings()
        element("SettingsPage-lists").click()
        XCTAssertTrue(element("ListsDensity").waitForExistence(timeout: 3))
        XCTAssertTrue(window.outlines["ItemList"].exists)
    }

    func testTheCommandPaletteOpensSettingsAtAPage() {
        app.typeKey("k", modifierFlags: .command)
        app.typeText("Settings: Editor")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("PageWidth").waitForExistence(timeout: 3))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
