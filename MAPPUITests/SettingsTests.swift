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

    func testSettingsUsesTheCurrentWindowAndReturnsToTheSelectedNote() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let title = window.textFields["ItemPageTitle"]
        let selected = expectation(for: NSPredicate(format: "value == %@", "Trip to Lisbon"), evaluatedWith: title)
        wait(for: [selected], timeout: 3)
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

    func testSettingsFromAnUnselectedItemKeepsNativeChrome() {
        let row = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Trip to Lisbon")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(window.textFields["ItemPageTitle"].waitForExistence(timeout: 3))
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

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
