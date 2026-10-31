import XCTest

/// Quits the app and starts it again with the system's window restoration on, which the other UI tests switch off.
@MainActor
final class WindowBringBackUITests: XCTestCase {
    /// `fresh` starts from the default window; otherwise the window comes back as the last run left it.
    private func launch(fresh: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (fresh ? ["-ApplePersistenceIgnoreState", "YES"] : []) + ["-MAPPSampleLibrary"]
        app.launch()
        return app
    }

    private func gallery(_ app: XCUIApplication) -> XCUIElement {
        app.windows.firstMatch.descendants(matching: .any).matching(identifier: "ItemGallery").element(boundBy: 0)
    }

    func testAHiddenSidebarAndAnOpenItemComeBackAfterQuitting() throws {
        var app = launch(fresh: true)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["as Gallery"].click()
        XCTAssertTrue(gallery(app).waitForExistence(timeout: 3))
        window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "GalleryItem-")).element(boundBy: 0).click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(gallery(app).waitForNonExistence(timeout: 3), "the item is open, not the grid")
        app.toolbars.buttons["Hide Sidebar"].click()
        XCTAssertTrue(window.outlines["Sidebar"].waitForNonExistence(timeout: 3))
        // The window's state is saved shortly after a change.
        Thread.sleep(forTimeInterval: 2)
        app.terminate()

        app = launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.toolbars.buttons["Show Sidebar"].waitForExistence(timeout: 5), "the sidebar stays hidden")
        XCTAssertFalse(app.windows.firstMatch.outlines["Sidebar"].exists)
        XCTAssertTrue(app.itemPageBody.waitForExistence(timeout: 5), "the item is open on the page")
        XCTAssertFalse(gallery(app).exists, "not the grid behind it")
    }
}
