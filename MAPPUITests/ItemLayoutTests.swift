import AppKit
import XCTest

@MainActor
final class ItemLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws { app.terminate() }

    func testHeaderAndBodyOccupySeparateRegions() {
        app.outlines["Sidebar"].staticTexts["Items"].click()
        let row = app.outlines["NoteList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let title = app.itemPageTitle
        let page = app.webViews.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["View"].click()
        if app.menuItems["Hide Details"].exists { app.menuItems["Hide Details"].click() }
        else { app.typeKey(.escape, modifierFlags: []) }
        let normalWidth = page.frame.width
        capture("Document normal width")
        let bodyHeading = page.textViews.firstMatch.staticTexts["Kitchen quotes"].firstMatch
        XCTAssertTrue(bodyHeading.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(bodyHeading.frame.minY, title.frame.maxY + 20,
                                    "Body content must start below the title and pinned properties.")
        app.descendants(matching: .any)["DetailsToggle"].click()
        capture("Document with inspector and narrower content")
        XCTAssertGreaterThanOrEqual(bodyHeading.frame.minY, title.frame.maxY + 20)
        XCTAssertLessThan(page.frame.width, normalWidth)
        app.typeKey("n", modifierFlags: .command)
        app.completeQuickAdd(type: "Note", title: "Narrow item")
        XCTAssertTrue(app.itemPageTitle.waitForExistence(timeout: 3))
        capture("New item narrow width")
        XCTAssertFalse(app.buttons["Back"].exists)
    }

    func testSearchFieldStartsAtTheColumnAndEndsBeforeTheOptions() {
        app.outlines["Sidebar"].staticTexts["Items"].click()
        let list = app.outlines["NoteList"]
        app.typeKey("f", modifierFlags: [.command, .option])
        let field = app.descendants(matching: .any)["ColumnSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let search = field.textFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        capture("Full width column search")
        // The glass field, not the text inside it, starts at the column's edge and leaves room for the options.
        XCTAssertLessThan(abs(field.frame.minX - list.frame.minX), 20)
        XCTAssertLessThan(field.frame.maxX, list.frame.maxX)
        XCTAssertGreaterThan(field.frame.width, list.frame.width * 0.5)
        search.typeText("tomatoes")
        XCTAssertEqual(search.value as? String, "tomatoes")
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
    }

    func testHeaderScrollsWithTheBodyAndTitleMovesIntoToolbar() {
        app.outlines["Sidebar"].staticTexts["Items"].click()
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
        let header = app.itemPageTitle
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        capture("Header at start of long document")
        let before = header.frame.minY
        let otherColumnControls = [
            app.toolbars.buttons["Search"],
            app.toolbars.menuButtons["View Options"],
            app.toolbars.buttons["Hide Sidebar"],
        ]
        let controlFrames = otherColumnControls.map(\.frame)
        let controlColors = otherColumnControls.map { averageColor(of: $0.screenshot()) }
        header.scroll(byDeltaX: 0, deltaY: -40)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertLessThan(header.frame.minY, before - 20, "The header scrolls with the page.")
        for _ in 0..<8 { page.scroll(byDeltaX: 0, deltaY: -100) }
        let compactTitle = app.staticTexts["ScrolledItemTitle"]
        XCTAssertTrue(compactTitle.waitForExistence(timeout: 3))
        XCTAssertFalse(header.isHittable)
        for _ in 0..<3 {
            page.scroll(byDeltaX: 0, deltaY: 800)
            page.scroll(byDeltaX: 0, deltaY: -1200)
        }
        for (index, control) in otherColumnControls.enumerated() {
            XCTAssertEqual(control.frame.minX, controlFrames[index].minX, accuracy: 2)
            let color = averageColor(of: control.screenshot())
            for channel in 0..<3 {
                XCTAssertEqual(color[channel], controlColors[index][channel], accuracy: 0.08,
                               "scrolling a note must not recolor controls in the other columns")
            }
        }
        capture("Compact title in toolbar after scrolling")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        // Choosing the place shown before leaves Settings with the window as it was.
        app.outlines["Sidebar"].staticTexts["Items"].click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 3))
        XCTAssertTrue(compactTitle.waitForExistence(timeout: 3), "returning from Settings preserves the note's scroll position")
        XCTAssertFalse(header.isHittable)
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

    private func averageColor(of screenshot: XCUIScreenshot) -> [Double] {
        guard let data = screenshot.image.tiffRepresentation,
              let image = NSBitmapImageRep(data: data) else {
            XCTFail("the toolbar screenshot could not be read")
            return [0, 0, 0]
        }
        var color = [0.0, 0.0, 0.0]
        var count = 0.0
        for y in stride(from: 0, to: image.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: image.pixelsWide, by: 2) {
                guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                color[0] += pixel.redComponent
                color[1] += pixel.greenComponent
                color[2] += pixel.blueComponent
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 0)
        return color.map { $0 / max(1, count) }
    }
}
