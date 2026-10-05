import AppKit
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
        let bodyHeading = page.staticTexts["Kitchen quotes"].firstMatch
        XCTAssertTrue(bodyHeading.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(bodyHeading.frame.minY, title.frame.maxY + 20,
                                    "Body content must start below the native title and property chips.")
        app.buttons["DetailsToggle"].click()
        capture("Document with inspector and narrower content")
        XCTAssertGreaterThanOrEqual(bodyHeading.frame.minY, title.frame.maxY + 20)
        XCTAssertLessThan(page.frame.width, normalWidth)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["NewItemTitle"].waitForExistence(timeout: 3))
        capture("New item narrow width")
        XCTAssertFalse(app.buttons["Import File…"].exists)
        XCTAssertFalse(app.buttons["Back"].exists)
    }

    func testSearchFillsItsColumnAndHasATrailingCloseButton() {
        app.outlines["Sidebar"].staticTexts["All Notes"].click()
        let list = app.outlines["NoteList"]
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = app.searchFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        capture("Full width column search")
        let close = app.buttons["CloseColumnSearch"]
        XCTAssertTrue(close.exists)
        XCTAssertLessThan(abs(search.frame.minX - list.frame.minX), 20)
        XCTAssertLessThan(abs(list.frame.maxX - search.frame.maxX), 20)
        XCTAssertGreaterThan(close.frame.midX, search.frame.midX)
        search.typeText("tomatoes")
        XCTAssertEqual(search.value as? String, "tomatoes")
        close.click()
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
    }

    func testHeaderScrollsWithTheBodyAndTitleMovesIntoToolbar() {
        app.outlines["Sidebar"].staticTexts["Reading"].click()
        let row = app.outlines["NoteList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "The Design of Everyday Things")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(page.staticTexts["The Design of Everyday Things"].firstMatch.waitForExistence(timeout: 5))
        let body = page.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\n\n" + Array(repeating: "A paragraph for the scrolling check.", count: 45).joined(separator: "\n\n"), forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.upArrow, modifierFlags: .command)
        let header = app.textFields["ItemPageTitle"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        capture("Header at start of long document")
        let before = header.frame.minY
        header.scroll(byDeltaX: 0, deltaY: -40)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertLessThan(header.frame.minY, before - 20, "The native header follows WebKit's scroll.")
        for _ in 0..<8 { page.scroll(byDeltaX: 0, deltaY: -100) }
        let compactTitle = app.staticTexts["ScrolledItemTitle"]
        XCTAssertTrue(compactTitle.waitForExistence(timeout: 3))
        XCTAssertFalse(header.isHittable)
        capture("Compact title in toolbar after scrolling")
        app.typeKey("f", modifierFlags: .command)
        capture("Find bar on scrolled document")
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
