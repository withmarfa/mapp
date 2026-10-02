import XCTest

@MainActor
final class ItemLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testHeaderAndBodyOccupySeparateRegions() {
        app.outlines["Sidebar"].staticTexts["All Notes"].click()
        let row = app.outlines["NoteList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let title = app.descendants(matching: .any)["ItemPageTitle"]
        let page = app.webViews.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["View"].click()
        if app.menuItems["Hide Details"].exists { app.menuItems["Hide Details"].click() }
        else { app.typeKey(.escape, modifierFlags: []) }
        let normalWidth = page.frame.width
        capture("Document normal width")
        XCTAssertGreaterThanOrEqual(page.frame.minY, title.frame.maxY + 20,
                                    "The editor must start below the title and property chips.")
        app.buttons["DetailsToggle"].click()
        capture("Document with inspector and narrower content")
        XCTAssertGreaterThanOrEqual(page.frame.minY, title.frame.maxY + 20)
        XCTAssertLessThan(page.frame.width, normalWidth)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["NewItemTitle"].waitForExistence(timeout: 3))
        capture("New item narrow width")
        XCTAssertFalse(app.buttons["Import File…"].exists)
        XCTAssertFalse(app.buttons["Back"].exists)
    }

    private func capture(_ name: String) {
        // AppKit's inspector animation continues after the accessibility action returns.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
