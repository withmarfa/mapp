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
        XCTAssertTrue(window.staticTexts["Settings"].exists)
        XCTAssertTrue(window.popUpButtons["NoteSort"].exists, "the real list preferences are available")
        XCTAssertEqual(window.popUpButtons["NoteSort"].label, "Sort By")

        window.buttons["SettingsBack"].click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 3))
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Trip to Lisbon")
        XCTAssertEqual(list.frame.width, listFrame.width, accuracy: 2, "the note-list width is preserved")
    }

    func testSettingsSearchFindsControlsAndHandlesNoMatches() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let search = window.searchFields["SettingsSearch"]
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
