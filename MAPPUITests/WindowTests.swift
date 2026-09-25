import XCTest

/// Drives the real app through its accessibility tree.
@MainActor
final class WindowTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var editor: XCUIElement { window.textViews["NoteEditor"] }

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
        XCTAssertTrue(editor.exists)
        XCTAssertTrue((editor.value as? String ?? "").hasPrefix("# Kitchen quotes"))
    }

    func testSelectingAFolderShowsOnlyItsNotes() {
        sidebarItem("Work").click()
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Weekly review").exists)
    }

    func testSelectingANoteShowsIt() {
        row(titled: "Trip to Lisbon").click()
        XCTAssertTrue((editor.value as? String ?? "").hasPrefix("# Trip to Lisbon"))
    }

    func testEditingANoteRetitlesItInTheList() {
        row(titled: "Garden ideas").click()
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
        XCTAssertEqual(editor.value as? String, "")
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
        XCTAssertFalse(editor.isEnabled)
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
        XCTAssertTrue((editor.value as? String ?? "").hasPrefix("# Recipes to try"), "the page follows the results")
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
        let first = editor.value as? String ?? ""
        let title = String(first.prefix { $0 != "\n" }.dropFirst(2))
        row(titled: title).rightClick()
        window.menuItems["Move To"].click()
        window.menuItems["Home"].click()
        XCTAssertTrue(row(titled: title).waitForNonExistence(timeout: 2))
        XCTAssertFalse((editor.value as? String ?? "").hasPrefix(first.prefix(20)), "the page still shows the moved note")
        XCTAssertTrue(editor.exists)
    }
}
