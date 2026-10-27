import AppKit
import XCTest

/// Settings is a place in the main window: the sidebar stays, its pages take the list's column and the page the
/// detail column, and choosing a place in the sidebar leaves it.
@MainActor
final class SettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    /// Settings' pages, which take the list's column while Settings is the place.
    private var settings: XCUIElement { element("SettingsPageList") }
    /// The instance's name at the sidebar's foot, which opens the menu that holds Settings.
    private var instanceMenu: XCUIElement { element("SidebarLibrary") }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testSettingsUsesTheCurrentWindowAndReturnsToTheSelectedNote() throws {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let title = window.itemPageTitle
        let selected = expectation(for: NSPredicate(format: "value == %@", "Trip to Lisbon"), evaluatedWith: title)
        wait(for: [selected], timeout: 3)
        let initialWidth = list.frame.width
        let splitter = try XCTUnwrap(window.splitters.allElementsBoundByIndex.min {
            abs($0.frame.midX - list.frame.maxX) < abs($1.frame.midX - list.frame.maxX)
        })
        XCTAssertLessThan(abs(splitter.frame.midX - list.frame.maxX), 8)
        let divider = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        divider.click(forDuration: 0.2, thenDragTo: divider.withOffset(CGVector(dx: 60, dy: 0)))
        XCTAssertGreaterThan(list.frame.width, initialWidth + 40, "the list is resized before opening Settings")
        let listFrame = list.frame

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1, "settings uses the same window")
        XCTAssertFalse(list.exists, "the pages take the item list's column")
        XCTAssertTrue(sidebar.exists, "the sidebar stays")
        XCTAssertFalse(element("MoreToolbar").exists, "item commands are hidden in settings")
        attachScreenshot("SettingsAppearance")
        XCTAssertTrue(element("SettingsDetail").exists)
        XCTAssertTrue(window.popUpButtons["NoteSort"].exists, "the real list preferences are available")
        XCTAssertEqual(window.popUpButtons["NoteSort"].label, "Sort By")

        leaveSettings()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Trip to Lisbon")
        XCTAssertEqual(list.frame.width, listFrame.width, accuracy: 2, "the note-list width is preserved")
    }

    func testEachSettingsPageShowsInTheDetailColumnWithItsTitle() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertFalse(element("MoreToolbar").exists)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForNonExistence(timeout: 3), "the native sidebar toggle works in Settings")
        XCTAssertTrue(settings.exists, "the pages stay")
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
        let pages = [("editor", "Editor"), ("sidebar", "Sidebar"), ("library", "Library"),
                     ("thisMarfa", "This Marfa"), ("about", "About"), ("appearance", "Appearance")]
        XCTAssertFalse(element("SettingsPage-recentlyDeleted").exists, "Recently Deleted is a workspace destination")
        for (page, title) in pages {
            let row = element("SettingsPage-\(page)")
            XCTAssertTrue(row.exists, "\(title) is a page")
            XCTAssertGreaterThan(row.frame.minX, sidebar.frame.maxX, "the pages are in the content column, not the sidebar")
            row.click()
            XCTAssertTrue(element("SettingsDetail").exists)
            attachScreenshot("Settings-\(page)")
            XCTAssertTrue(element("SettingsDetail").staticTexts[title].waitForExistence(timeout: 3), "the detail shows the selected page's title")
        }
        leaveSettings()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(element("MoreToolbar").exists)
    }

    func testSettingsReturnsToTheChosenPlace() {
        sidebar.staticTexts["Inbox"].click()
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Garden ideas")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            sidebar.staticTexts["Inbox"].click()
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch.exists)
        }
    }

    func testSettingsPreservesTheEditorsTextAndUndoHistory() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        row.click()
        let body = app.itemPageBody
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\n\nRetained editor check", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        let inserted = expectation(for: NSPredicate(format: "value CONTAINS %@", "Retained editor check"), evaluatedWith: body)
        wait(for: [inserted], timeout: 3)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        leaveSettings()
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertTrue((body.value as? String)?.contains("Retained editor check") == true)
        body.click()
        app.typeKey("z", modifierFlags: .command)
        let undone = expectation(for: NSPredicate(format: "NOT (value CONTAINS %@)", "Retained editor check"), evaluatedWith: body)
        wait(for: [undone], timeout: 3)
    }

    func testSettingsFromAnUnselectedItemReturnsToNoSelection() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        let prompt = window.staticTexts["No Item Selected"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(element("SettingsDetail").exists)
        attachScreenshot("Settings-no-item-selected")
        leaveSettings()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
    }

    func testSettingsKeepsExpandedColumnSearchForReturning() {
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = window.textFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Lisbon")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertFalse(search.exists)
        XCTAssertTrue(element("SettingsDetail").staticTexts["Appearance"].waitForExistence(timeout: 3))
        attachScreenshot("Settings-from-column-search")
        leaveSettings()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Lisbon")
        search.typeKey(.escape, modifierFlags: [])
    }

    func testAPreferenceChangedInSettingsOutlivesLeavingIt() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        element("SettingsPage-editor").click()
        let spelling = window.switches["CheckSpelling"]
        XCTAssertTrue(spelling.waitForExistence(timeout: 3))
        XCTAssertEqual(spelling.label, "Check Spelling While Typing")
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "1")
        spelling.click()
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "0")
        leaveSettings()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(spelling.waitForExistence(timeout: 3), "Settings opens at the page shown last")
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "0", "the preference survives returning to the notes")
    }

    func testNewItemLeavesSettingsAndOpensThePageWithTheSidebarHidden() {
        app.typeKey("s", modifierFlags: [.command, .control])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        // With the sidebar hidden there is no place to choose; New leaves Settings through quick add.
        app.typeKey("n", modifierFlags: .command)
        window.completeQuickAdd(type: "Note", title: "From Settings")
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCTAssertFalse(settings.exists)
        XCTAssertFalse(sidebar.exists, "the sidebar stays hidden after returning")
    }

    func testSettingsCanOpenAfterTheLastWindowCloses() {
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
    }

    func testCommandPaletteOpensSettingsInTheSameWindow() {
        app.typeKey("k", modifierFlags: .command)
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("settings")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(field.exists)
    }

    func testBaseTextSizeChangesTheInterfaceAndPreservesNoteTextSize() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let originalHeight = row.frame.height
        let sidebarText = sidebar.staticTexts["Items"]
        let originalSidebarHeight = sidebarText.frame.height
        let typeText = sidebar.staticTexts["SidebarType-core.note"]
        XCTAssertTrue(typeText.waitForExistence(timeout: 3))
        let originalTypeHeight = typeText.frame.height
        XCTAssertEqual(list.frame.width, 340, accuracy: 2, "a fresh window starts with a 340-point list")
        XCTAssertTrue(instanceMenu.exists)
        XCTAssertLessThan(instanceMenu.frame.maxX, list.frame.minX, "the foot belongs to the sidebar")
        instanceMenu.click()
        app.menuItems["Settings"].click()
        let size = window.popUpButtons["InterfaceTextSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        size.click()
        app.menuItems["18 pt"].click()
        leaveSettings()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(row.frame.height, originalHeight + 8, "list text and row height scale together")
        XCTAssertGreaterThan(typeText.frame.height, originalTypeHeight + 3, "a type's row scales with the interface")
        XCTAssertGreaterThan(sidebarText.frame.height, originalSidebarHeight + 3, "sidebar text scales too")
        attachScreenshot("LargerInterfaceText")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertEqual(size.value as? String, "18 pt", "the setting is retained on returning")
        element("SettingsPage-editor").click()
        let noteSize = window.popUpButtons["TextSize"]
        XCTAssertTrue(noteSize.waitForExistence(timeout: 3))
        XCTAssertEqual(noteSize.value as? String, "13 pt", "the note's own text setting stays independent")
        attachScreenshot("SeparateEditorTextSize")
        app.terminate()
        app.launchArguments += ["-MAPPKeepSampleSettings"]
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        element("SettingsPage-appearance").click()
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertEqual(size.value as? String, "18 pt", "the preference survives restarting the app")
    }

    func testBaseTextSizeKeepsTheSidebarFootAndSearchUsableAtLimits() {
        for points in [24, 11] {
            app.typeKey(",", modifierFlags: .command)
            let size = window.popUpButtons["InterfaceTextSize"]
            XCTAssertTrue(size.waitForExistence(timeout: 3))
            size.click()
            app.menuItems["\(points) pt"].click()
            leaveSettings()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
            XCTAssertTrue(instanceMenu.waitForExistence(timeout: 3))
            XCTAssertTrue(instanceMenu.isHittable, "the sidebar's instance menu is reachable at \(points) points")
            XCTAssertTrue(instanceMenu.isEnabled)
            XCTAssertTrue(element("NewItemToolbar").isHittable, "the foot's New Item button is reachable at \(points) points")
            app.typeKey("f", modifierFlags: [.command, .option])
            let search = window.textFields["ColumnSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            search.typeText("Lisbon")
            XCTAssertEqual(search.value as? String, "Lisbon")
            search.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(search.waitForNonExistence(timeout: 3))
            attachScreenshot("InterfaceText-\(points)")
        }
    }

    /// Chooses the place the window showed, which leaves Settings with the window as it was.
    private func leaveSettings() {
        let items = sidebar.staticTexts["Items"]
        XCTAssertTrue(items.waitForExistence(timeout: 3))
        items.click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 3))
    }

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
