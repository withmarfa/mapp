import AppKit
import XCTest

@MainActor
final class SettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var settings: XCUIElement { window.descendants(matching: .any)["SettingsWorkspace"].firstMatch }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
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
        XCTAssertFalse(list.exists, "there is no item-list column in settings")
        XCTAssertFalse(window.buttons["Share"].exists, "note commands are hidden in settings")
        attachScreenshot("SettingsAppearance")
        XCTAssertTrue(window.staticTexts["Appearance"].exists)
        XCTAssertTrue(window.popUpButtons["NoteSort"].exists, "the real list preferences are available")
        XCTAssertEqual(window.popUpButtons["NoteSort"].label, "Sort By")

        window.buttons["SettingsBack"].click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 3))
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Trip to Lisbon")
        XCTAssertEqual(list.frame.width, listFrame.width, accuracy: 2, "the note-list width is preserved")
    }

    func testSettingsUsesNativeSidebarAndToolbarAcrossCategories() {
        let workspaceTitle = window.children(matching: .staticText).matching(NSPredicate(format: "value == %@", "All Notes")).firstMatch
        XCTAssertTrue(workspaceTitle.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(workspaceTitle.waitForNonExistence(timeout: 3), "the hidden workspace does not contribute a title")
        let back = window.toolbars.buttons["SettingsBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "Back belongs to the system toolbar")
        let sidebar = window.outlines["SettingsSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
        XCTAssertLessThan(back.frame.maxX, sidebar.frame.maxX, "Back stays in the sidebar toolbar")
        let sidebarToggle = window.toolbars.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sidebar")).firstMatch
        XCTAssertTrue(sidebarToggle.exists)
        XCTAssertLessThan(sidebarToggle.frame.maxX, sidebar.frame.maxX, "the sidebar toggle stays with its column")
        XCTAssertFalse(window.descendants(matching: .any).matching(identifier: "FormatToolbar").element(boundBy: 0).exists)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForNonExistence(timeout: 3), "the native sidebar toggle targets Settings")
        XCTAssertTrue(back.exists)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
        for (pane, title) in [("editor", "Editor"), ("library", "Library"), ("marfa", "Marfa"), ("about", "About"), ("appearance", "Appearance")] {
            let category = sidebar.descendants(matching: .any).matching(identifier: "SettingsPane-\(pane)").element(boundBy: 0)
            XCTAssertTrue(category.exists)
            category.click()
            XCTAssertFalse(workspaceTitle.exists)
            XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "SettingsDetail").element(boundBy: 0).exists)
            attachScreenshot("NativeSettings-\(pane)")
            XCTAssertTrue(window.toolbars.staticTexts[title].waitForExistence(timeout: 3), "the active pane has a native toolbar title")
        }
        back.click()
        XCTAssertTrue(workspaceTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "FormatToolbar").element(boundBy: 0).exists)
    }

    func testSettingsReturnsToTheTypesBrowser() {
        window.outlines["SidebarPlaces"].staticTexts["Marfa Types"].click()
        let types = window.descendants(matching: .any)["MarfaTypesList"]
        XCTAssertTrue(types.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            window.buttons["SettingsBack"].click()
            XCTAssertTrue(types.waitForExistence(timeout: 5))
            XCTAssertFalse(list.exists)
        }
    }

    func testSettingsPreservesTheEditorsTextAndUndoHistory() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        row.click()
        let body = window.webViews.firstMatch.textViews.firstMatch
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
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertTrue((body.value as? String)?.contains("Retained editor check") == true)
        body.click()
        app.typeKey("z", modifierFlags: .command)
        let undone = expectation(for: NSPredicate(format: "NOT (value CONTAINS %@)", "Retained editor check"), evaluatedWith: body)
        wait(for: [undone], timeout: 3)
    }

    func testSettingsFromAnUnselectedItemKeepsNativeChrome() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        let prompt = window.staticTexts["SelectItemPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(window.toolbars.buttons["SettingsBack"].exists)
        XCTAssertTrue(window.outlines["SettingsSidebar"].exists)
        attachScreenshot("NativeSettings-no-item-selected")
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
    }

    func testSettingsKeepsExpandedColumnSearchForReturning() {
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = window.searchFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Lisbon")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertFalse(search.exists)
        XCTAssertTrue(window.toolbars.staticTexts["Appearance"].waitForExistence(timeout: 3))
        attachScreenshot("NativeSettings-from-column-search")
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Lisbon")
        window.buttons["CloseColumnSearch"].click()
    }

    func testSettingsSearchFindsControlsAndHandlesNoMatches() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let search = window.searchFields.element(boundBy: 0)
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("spelling")
        attachScreenshot("SettingsSearchSpelling")
        XCTAssertEqual(search.value as? String, "spelling")
        let spelling = window.switches["CheckSpelling"]
        XCTAssertTrue(spelling.waitForExistence(timeout: 3))
        XCTAssertEqual(spelling.label, "Check Spelling While Typing")
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "1")
        spelling.click()
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "0")
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(spelling.waitForExistence(timeout: 3))
        XCTAssertEqual(spelling.value.map { String(describing: $0) }, "0", "the preference survives returning to the notes")
        XCTAssertFalse(window.staticTexts["Appearance"].exists)
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeText("no matching preference")
        XCTAssertFalse(spelling.exists)
        XCTAssertTrue(window.buttons["SettingsBack"].exists, "return remains available with no results")
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(window.staticTexts["Appearance"].firstMatch.waitForExistence(timeout: 3))
    }

    func testSettingsPreservesAnUnsubmittedDraftWithTheSidebarHidden() {
        app.typeKey("s", modifierFlags: [.command, .control])
        app.typeKey("n", modifierFlags: .command)
        let title = window.textFields["NewItemTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Unsubmitted field notes")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Unsubmitted field notes")
        XCTAssertFalse(window.outlines["Sidebar"].exists, "the sidebar stays hidden after returning")
    }

    func testSettingsCanOpenAfterTheLastWindowCloses() {
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
    }

    func testCommandPaletteOpensTheSameSettingsWorkspace() {
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
        let sidebarText = window.outlines["Sidebar"].staticTexts["All Notes"]
        let originalSidebarHeight = sidebarText.frame.height
        let favoriteText = window.outlines["Sidebar"].staticTexts["Kitchen quotes"]
        let folderText = window.outlines["Sidebar"].staticTexts["Home"]
        let originalFavoriteHeight = favoriteText.frame.height
        let originalFolderHeight = folderText.frame.height
        XCTAssertEqual(list.frame.width, 340, accuracy: 2, "a fresh window starts with a 340-point list")
        let settingsButton = window.toolbars.buttons["SettingsToolbar"]
        XCTAssertTrue(settingsButton.exists)
        XCTAssertLessThan(settingsButton.frame.maxX, list.frame.minX, "Settings belongs to the sidebar")
        settingsButton.click()
        let size = window.popUpButtons["InterfaceTextSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        size.click()
        app.menuItems["18 pt"].click()
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(row.frame.height, originalHeight + 8, "list text and row height scale together")
        XCTAssertGreaterThan(favoriteText.frame.height, originalFavoriteHeight + 3, "favorite text scales with the interface")
        XCTAssertGreaterThan(folderText.frame.height, originalFolderHeight + 3, "nested folder text scales with the interface")
        XCTAssertGreaterThan(sidebarText.frame.height, originalSidebarHeight + 3, "sidebar text scales too")
        attachScreenshot("LargerInterfaceText")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertEqual(size.value as? String, "18 pt", "the setting is retained on returning")
        window.outlines["SettingsSidebar"].staticTexts["Editor"].click()
        let noteSize = window.popUpButtons["TextSize"]
        XCTAssertTrue(noteSize.waitForExistence(timeout: 3))
        XCTAssertEqual(noteSize.value as? String, "13 pt", "the note's own text setting stays independent")
        attachScreenshot("SeparateEditorTextSize")
        app.terminate()
        app.launchArguments += ["-MAPPKeepSampleSettings", "-MAPPKeepSampleFolder"]
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        XCTAssertEqual(size.value as? String, "18 pt", "the preference survives restarting the app")
    }

    func testBaseTextSizeKeepsSidebarPlacesAndSearchUsableAtLimits() {
        for points in [24, 11] {
            app.typeKey(",", modifierFlags: .command)
            let size = window.popUpButtons["InterfaceTextSize"]
            XCTAssertTrue(size.waitForExistence(timeout: 3))
            size.click()
            app.menuItems["\(points) pt"].click()
            window.buttons["SettingsBack"].click()
            let places = window.outlines["SidebarPlaces"]
            XCTAssertTrue(places.waitForExistence(timeout: 3))
            XCTAssertEqual(places.outlineRows.count, 2)
            for row in places.outlineRows.allElementsBoundByIndex {
                XCTAssertTrue(places.frame.contains(row.frame), "a sidebar place is clipped at \(points) points")
            }
            app.typeKey("f", modifierFlags: [.command, .option])
            let search = window.searchFields["ColumnSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            search.typeText("Lisbon")
            XCTAssertEqual(search.value as? String, "Lisbon")
            window.buttons["CloseColumnSearch"].click()
            XCTAssertTrue(search.waitForNonExistence(timeout: 3))
            attachScreenshot("InterfaceText-\(points)")
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
