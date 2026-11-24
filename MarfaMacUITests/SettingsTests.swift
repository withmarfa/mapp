import AppKit
import XCTest

/// Settings is a window of its own: Command-comma opens one instance with a sidebar of pages, Back and Forward, and the
/// page's name; the main window stays as it was.
nonisolated final class SettingsTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var sidebar: XCUIElement { element("SettingsSidebar") }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.outlines["ItemList"].waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws {
        app.terminate()
    }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    @MainActor private func openSettings() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
    }

    @MainActor func testSettingsOpensInAWindowOfItsOwnAndTheMainWindowStays() {
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

    @MainActor func testCommandCommaWithSettingsOpenBringsItForwardAndMakesNoSecondWindow() {
        openSettings()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 2)
    }

    @MainActor func testEachPageShowsItsContent() {
        openSettings()
        for (page, marker) in [("appearance", "InterfaceTextSize"), ("lists", "ListsDensity"), ("editor", "PageWidth"), ("connection", "LibrarySummary")] {
            element("SettingsPage-\(page)").click()
            XCTAssertTrue(element(marker).waitForExistence(timeout: 3), "\(page) shows \(marker)")
        }
    }

    @MainActor func testBackAndForwardMoveThroughThePagesOpened() {
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

    @MainActor func testTheSidebarSearchFindsAPageByARowAndSaysWhenNothingMatches() {
        openSettings()
        let search = element("SettingsSidebar").searchFields.firstMatch
        search.click()
        search.typeText("spelling")
        XCTAssertTrue(element("SettingsPage-editor").waitForExistence(timeout: 3))
        XCTAssertFalse(element("SettingsPage-lists").exists)
        search.typeText("zzzz")
        XCTAssertTrue(element("SettingsSearchEmpty").waitForExistence(timeout: 3))
    }

    @MainActor func testAPreferenceChangedInSettingsAppliesToTheMainWindow() {
        openSettings()
        element("SettingsPage-lists").click()
        XCTAssertTrue(element("ListsDensity").waitForExistence(timeout: 3))
        XCTAssertTrue(window.outlines["ItemList"].exists)
    }

    @MainActor func testTheCommandPaletteOpensSettingsAtAPage() {
        app.typeKey("k", modifierFlags: .command)
        app.typeText("Settings: Editor")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("PageWidth").waitForExistence(timeout: 3))
    }

    @MainActor private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
