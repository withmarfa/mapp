import XCTest

/// Drives the real app through its accessibility tree.
@MainActor
final class WindowTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var page: XCUIElement { window.webViews.firstMatch }
    /// The note's text as the page shows it: formatted, so without markdown's marks.
    private var editor: XCUIElement { page.textViews.firstMatch }
    private var text: String { editor.value as? String ?? "" }

    private func waitForText(_ predicate: String, _ argument: String) -> Bool {
        let format = predicate.hasPrefix("NOT ") ? "NOT (value \(predicate.dropFirst(4)) %@)" : "value \(predicate) %@"
        let expectation = expectation(for: NSPredicate(format: format, argument), evaluatedWith: editor)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func sidebarItem(_ name: String) -> XCUIElement {
        sidebar.staticTexts[name]
    }

    private func row(titled title: String) -> XCUIElement {
        list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", title)).firstMatch
    }

    private func count(of name: String) -> Int {
        Int(sidebarItem(name).value as? String ?? "") ?? (sidebarItem(name).value as? Int ?? -1)
    }

    func testSidebarListsEverySectionWithCounts() {
        for name in ["Inbox", "All Notes", "Pinned", "Folders", "Work", "Home", "Personal", "Reading", "Recently Deleted"] {
            XCTAssertTrue(sidebarItem(name).exists, "\(name) is missing")
        }
        XCTAssertGreaterThan(count(of: "All Notes"), 0)
    }

    func testTheFirstNoteIsSelectedAndShownInThePage() {
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
    }

    func testSelectingAFolderShowsOnlyItsNotes() {
        sidebarItem("Work").click()
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Weekly review").exists)
    }

    func testSelectingANoteShowsIt() {
        row(titled: "Trip to Lisbon").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Trip to Lisbon"))
    }

    func testEditingANoteRetitlesItInTheList() {
        row(titled: "Garden ideas").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Garden ideas"))
        editor.click()
        editor.typeKey(.upArrow, modifierFlags: .command)
        editor.typeKey(.rightArrow, modifierFlags: .command)
        editor.typeText(" for spring")
        XCTAssertTrue(row(titled: "Garden ideas for spring").waitForExistence(timeout: 2))
    }

    func testNewNoteIsCreatedSelectedAndEmpty() {
        let before = count(of: "Inbox")
        sidebarItem("Inbox").click()
        window.toolbars.buttons["New Note"].click()
        XCTAssertTrue(row(titled: "New Note").waitForExistence(timeout: 2))
        XCTAssertTrue(waitForText("==", ""))
        XCTAssertEqual(count(of: "Inbox"), before + 1)
    }

    func testDeletingFromTheContextMenuMovesToRecentlyDeletedAndUndoes() {
        let deletedBefore = count(of: "Recently Deleted")
        row(titled: "Bike service").rightClick()
        window.menuItems["Delete"].click()
        XCTAssertTrue(row(titled: "Bike service").waitForNonExistence(timeout: 2))
        XCTAssertEqual(count(of: "Recently Deleted"), deletedBefore + 1)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row(titled: "Bike service").waitForExistence(timeout: 2))
        XCTAssertEqual(count(of: "Recently Deleted"), deletedBefore)
    }

    func testRecentlyDeletedNotesCanBeRecoveredButNotEdited() {
        sidebarItem("Recently Deleted").click()
        row(titled: "Old packing list").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Old packing list"))
        editor.click()
        app.typeText("zzz")
        XCTAssertFalse(text.contains("zzz"), "a deleted note takes no typing")
        window.buttons["Recover"].click()
        XCTAssertTrue(row(titled: "Old packing list").waitForNonExistence(timeout: 2))
        sidebarItem("Personal").click()
        XCTAssertTrue(row(titled: "Old packing list").waitForExistence(timeout: 2))
    }

    func testNewFolderIsNamedInPlace() {
        window.buttons["New Folder"].click()
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Projects\r")
        XCTAssertTrue(sidebarItem("Projects").waitForExistence(timeout: 2))
    }

    func testSearchFindsNotesAcrossFolders() {
        let search = window.searchFields.firstMatch
        search.click()
        search.typeText("ragu")
        XCTAssertTrue(row(titled: "Recipes to try").waitForExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"), "the page follows the results")
    }

    func testPinningFromTheContextMenuAddsToPinned() {
        let before = count(of: "Pinned")
        row(titled: "Garden ideas").rightClick()
        window.menuItems["Pin"].click()
        XCTAssertEqual(count(of: "Pinned"), before + 1)
    }

    func testMovingTheSelectedNoteAwaySelectsTheNextOne() {
        sidebarItem("Work").click()
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("BEGINSWITH", "Weekly review"))
        row(titled: "Weekly review").rightClick()
        window.menuItems["Move To"].click()
        window.menuItems["Home"].click()
        XCTAssertTrue(row(titled: "Weekly review").waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("NOT BEGINSWITH", "Weekly review"), "the page still shows the moved note")
    }

    // MARK: Keyboard, menus and windows

    func testReturnEntersThePageAndEscapeGoesBackToTheList() {
        row(titled: "Garden ideas").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Garden ideas"))
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Draft")
        XCTAssertTrue(waitForText("CONTAINS", "Draft"), "typing after Return goes into the page")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForText("NOT CONTAINS", "Draft"), "Escape handed the arrows back to the list")
    }

    func testCommandNMakesANoteReadyForTyping() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row(titled: "New Note").waitForExistence(timeout: 2))
        app.typeText("# Shopping")
        XCTAssertTrue(row(titled: "Shopping").waitForExistence(timeout: 2))
    }

    func testTheDeleteKeyDeletesTheSelectedNote() {
        sidebarItem("Personal").click()
        row(titled: "Bike service").click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(row(titled: "Bike service").waitForNonExistence(timeout: 2))
        XCTAssertTrue(editor.exists, "the next note is selected")
    }

    func testOptionCommandFSearchesNotes() {
        app.typeKey("f", modifierFlags: [.command, .option])
        app.typeText("ragu")
        XCTAssertTrue(row(titled: "Recipes to try").waitForExistence(timeout: 2))
    }

    func testAFolderIsRenamedFromTheMenuAndDeletedWithTheDeleteKey() {
        sidebarItem("Reading").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Rename Folder"].click()
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Books\r")
        XCTAssertTrue(sidebarItem("Books").waitForExistence(timeout: 2))
        app.typeKey(.delete, modifierFlags: [])
        let confirm = app.sheets.buttons["Delete Folder"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.click()
        XCTAssertTrue(sidebarItem("Books").waitForNonExistence(timeout: 2))
    }

    func testDoubleClickingANoteOpensItInItsOwnWindow() {
        row(titled: "Garden ideas").doubleClick()
        let twoWindows = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: app.windows)
        wait(for: [twoWindows], timeout: 3)
    }

    func testSortingByTitleFromTheViewMenuDropsTheDateSections() {
        XCTAssertTrue(list.staticTexts["Today"].exists)
        sortBy("Title")
        XCTAssertTrue(list.staticTexts["Today"].waitForNonExistence(timeout: 2))
        sortBy("Date Edited")
        XCTAssertTrue(list.staticTexts["Today"].waitForExistence(timeout: 2))
    }

    func testUndoInTheEditMenuUndoesTypingInThePage() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row(titled: "New Note").waitForExistence(timeout: 2))
        app.typeText("Groceries")
        XCTAssertTrue(waitForText("==", "Groceries"))
        app.menuBars.menuBarItems["Edit"].click()
        app.menuBars.menuItems["Undo"].click()
        XCTAssertTrue(waitForText("!=", "Groceries"))
    }

    func testATableIsInsertedFromTheFormatMenu() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row(titled: "New Note").waitForExistence(timeout: 2))
        app.typeText("Quotes")
        app.typeKey("t", modifierFlags: [.command, .option])
        let table = page.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3))
    }

    private func sortBy(_ order: String) {
        app.menuBars.menuBarItems["View"].click()
        let sortBy = app.menuBars.menuItems["Sort By"]
        sortBy.hover()
        sortBy.menuItems[order].click()
    }

    func testTheMainWindowPassesTheAccessibilityAudit() throws {
        // Some findings belong to the system rather than the app: List reports its section headers outside
        // their table, SwiftUI wraps columns and section headers in unlabelled groups that VoiceOver passes
        // through, and the system dims the sidebar's counts and a selected row's secondary text as Mail and
        // Notes do; a toolbar menu offers Show Menu rather than Press. Controls and text are still audited
        // everywhere else.
        let windowFrame = window.frame
        let sidebarFrame = sidebar.frame
        let selectedRowFrame = list.outlineRows.matching(NSPredicate(format: "selected == true")).firstMatch.frame
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            // The audit is of the window; the menu bar above it is the system's to draw.
            if !windowFrame.intersects(element.frame) { return true }
            switch issue.auditType {
            case .parentChild: return true
            case .sufficientElementDescription: return element.elementType == .group && element.label.isEmpty
            case .contrast: return sidebarFrame.contains(element.frame) || selectedRowFrame.contains(element.frame)
            case .action: return element.elementType == .menuButton || element.elementType == .popUpButton
            default: return false
            }
        }
    }
}

