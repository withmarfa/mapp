import XCTest

/// Drives the real app through its accessibility tree.
@MainActor
final class WindowTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines.matching(NSPredicate(format: "identifier == 'Sidebar'")).firstMatch }
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
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func sidebarItem(_ name: String) -> XCUIElement {
        if let identifier = groupIdentifier(for: name) {
            // Use the full indexed query: firstMatch omitted native outline labels visible in its own snapshot.
            return sidebar.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
        }
        return sidebar.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", name, name)).firstMatch
    }

    private func groupIdentifier(for name: String) -> String? {
        switch name {
        case "Favorites": "SidebarFavoritesSection"
        case "Folders": "SidebarFolders"
        default: nil
        }
    }

    private func row(titled title: String) -> XCUIElement {
        list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", title)).firstMatch
    }

    private func count(of name: String) -> Int {
        Int(sidebarItem(name).value as? String ?? "") ?? (sidebarItem(name).value as? Int ?? -1)
    }

    func testSidebarListsEverySectionWithCounts() {
        for name in ["Inbox", "Recents", "All Notes", "Favorites", "Folders", "Work", "Home", "Personal", "Reading"] {
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

    private func beginNewItem(title: String = "") {
        app.typeKey("n", modifierFlags: .command)
        let field = window.textFields["NewItemTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        if !title.isEmpty { field.typeText(title) }
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
    }

    func testANewItemHasAnEditableTitleIndependentOfItsBody() {
        beginNewItem(title: "Groceries")
        XCTAssertTrue(row(titled: "Groceries").waitForExistence(timeout: 3))
        editor.typeText("Milk and eggs")
        let title = window.itemPageTitle
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Weekly Groceries")
        title.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row(titled: "Weekly Groceries").waitForExistence(timeout: 3))
        XCTAssertTrue(waitForText("CONTAINS", "Milk and eggs"))
    }

    func testNewNoteIsCreatedSelectedAndEmpty() {
        let before = count(of: "All Notes")
        sidebarItem("Inbox").click()
        beginNewItem()
        XCTAssertTrue(row(titled: "Untitled").waitForExistence(timeout: 2))
        // An empty page holds nothing but the line the caret sits on.
        let empty = expectation(for: NSPredicate(format: "value == nil OR value MATCHES %@", "\\s*"), evaluatedWith: editor)
        wait(for: [empty], timeout: 3)
        XCTAssertEqual(count(of: "All Notes"), before + 1)
    }

    func testDeletingFromTheContextMenuRemovesTheNoteAndUndoes() {
        let before = count(of: "All Notes")
        row(titled: "Bike service").rightClick()
        window.menuItems["Delete"].click()
        XCTAssertTrue(row(titled: "Bike service").waitForNonExistence(timeout: 2))
        XCTAssertEqual(count(of: "All Notes"), before - 1)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row(titled: "Bike service").waitForExistence(timeout: 2))
        XCTAssertEqual(count(of: "All Notes"), before)
    }

    func testRecentlyDeletedInSettingsRestoresANote() {
        app.typeKey(",", modifierFlags: .command)
        let page = window.descendants(matching: .any).matching(identifier: "SettingsPage-recentlyDeleted").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
        let detail = window.descendants(matching: .any).matching(identifier: "SettingsDetail").element(boundBy: 0)
        let deleted = detail.staticTexts["Old packing list"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 3))
        XCTAssertTrue(detail.staticTexts["Draft agenda"].exists)
        let restores = detail.buttons.matching(identifier: "RecentlyDeletedRestore").allElementsBoundByIndex
        let restore = restores.min { abs($0.frame.midY - deleted.frame.midY) < abs($1.frame.midY - deleted.frame.midY) }
        XCTAssertNotNil(restore, "each deleted item has its own Restore")
        restore?.click()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 2))
        XCTAssertTrue(detail.staticTexts["Draft agenda"].exists, "only the one restored leaves")
        sidebarItem("Personal").click()
        XCTAssertTrue(row(titled: "Old packing list").waitForExistence(timeout: 2))
    }

    func testNewFolderIsNamedInPlace() {
        app.typeKey("n", modifierFlags: [.command, .shift])
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Projects")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(sidebarItem("Projects").waitForExistence(timeout: 2))
    }

    /// The list's search, a field only once its button beside View Options is clicked.
    private var listSearch: XCUIElement { window.searchFields["ColumnSearch"] }

    func testTheListsSearchFindsNotesAcrossFoldersAndEscapePutsItAway() {
        XCTAssertFalse(listSearch.exists, "a button until it is clicked")
        window.buttons["Search"].firstMatch.click()
        XCTAssertTrue(listSearch.waitForExistence(timeout: 2))
        app.typeText("ragu")
        XCTAssertTrue(row(titled: "Recipes to try").waitForExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"), "the page follows the results")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(listSearch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForExistence(timeout: 2), "the whole list is back")
    }

    func testAddingToFavoritesFromTheContextMenuAddsAShortcut() {
        XCTAssertFalse(sidebarItem("Garden ideas").exists)
        row(titled: "Garden ideas").rightClick()
        window.menuItems["Add to Favorites"].click()
        XCTAssertTrue(sidebarItem("Garden ideas").waitForExistence(timeout: 2))
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
        beginNewItem()
        XCTAssertTrue(row(titled: "Untitled").waitForExistence(timeout: 2))
        app.typeText("Shopping")
        XCTAssertTrue(waitForText("CONTAINS", "Shopping"))
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

    func testTheCommandPaletteOpensANoteAndRunsACommand() {
        app.typeKey("k", modifierFlags: .command)
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        app.typeText("bike serv\r")
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("BEGINSWITH", "Bike service"))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        // New Item leads what "new" finds; the arrow key moves on to New Folder.
        app.typeText("new")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sidebar.textFields.firstMatch.waitForExistence(timeout: 2), "the new folder's name is being edited")
    }

    func testEscapePutsTheCommandPaletteAway() {
        app.typeKey("k", modifierFlags: .command)
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
    }

    func testCommandZInTheSearchFieldLeavesThePageAlone() {
        row(titled: "Garden ideas").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Garden ideas"))
        app.typeKey(.return, modifierFlags: [])
        app.typeText(" Draft")
        XCTAssertTrue(waitForText("CONTAINS", "Draft"))
        app.typeKey("f", modifierFlags: [.command, .option])
        XCTAssertTrue(listSearch.waitForExistence(timeout: 2))
        app.typeText("garden")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForText("CONTAINS", "Draft"), "the note kept its typing; ⌘Z was the field's")
    }

    func testOptionCommandFReturnsToAnOpenSearch() {
        app.typeKey("f", modifierFlags: [.command, .option])
        XCTAssertTrue(listSearch.waitForExistence(timeout: 2))
        app.typeText("rag")
        row(titled: "Recipes to try").click()
        app.typeKey("f", modifierFlags: [.command, .option])
        // As any search field does, it takes the keyboard with its text selected, so typing replaces it.
        app.typeText("tomatoes")
        XCTAssertEqual(listSearch.value as? String, "tomatoes", "the field took the keyboard again")
    }

    func testShiftCommandPSearchesEveryNotesTextAndOpensTheOneChosen() {
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        editor.click()
        app.typeKey("p", modifierFlags: [.command, .shift])
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        app.typeText("ragu")
        XCTAssertFalse(text.contains("ragu"), "the palette took the typing, not the page")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"))
    }

    func testAFolderIsRenamedFromTheMenuAndDeletedWithTheDeleteKey() {
        sidebarItem("Reading").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Rename Folder"].click()
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Books")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(sidebarItem("Books").waitForExistence(timeout: 2))
        app.typeKey(.delete, modifierFlags: [])
        let confirm = app.sheets.buttons["Delete Folder"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        XCTAssertTrue(app.sheets.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Books")).element(boundBy: 0).exists)
        XCTAssertTrue(app.sheets.staticTexts["Its notes will be moved to Recently Deleted."].exists)
        confirm.click()
        XCTAssertTrue(sidebarItem("Books").waitForNonExistence(timeout: 2))
    }

    func testDoubleClickingANoteOpensItInItsOwnWindow() {
        row(titled: "Garden ideas").doubleClick()
        let twoWindows = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: app.windows)
        wait(for: [twoWindows], timeout: 3)
    }

    func testTheListIsGroupedByDateUntilTheViewMenuOrTitleOrderDropsIt() {
        XCTAssertTrue(list.staticTexts["Today"].waitForExistence(timeout: 2), "lists group by date from the start")
        sortBy("Title")
        XCTAssertTrue(list.staticTexts["Today"].waitForNonExistence(timeout: 2))
        sortBy("Date Edited")
        XCTAssertTrue(list.staticTexts["Today"].waitForExistence(timeout: 2))
        toggleGroupByDate()
        XCTAssertTrue(list.staticTexts["Today"].waitForNonExistence(timeout: 2))
        toggleGroupByDate()
        XCTAssertTrue(list.staticTexts["Today"].waitForExistence(timeout: 2))
    }

    func testUndoInTheEditMenuUndoesTypingInThePage() {
        beginNewItem()
        XCTAssertTrue(row(titled: "Untitled").waitForExistence(timeout: 2))
        app.typeText("Groceries")
        XCTAssertTrue(waitForText("==", "Groceries"))
        app.menuBars.menuBarItems["Edit"].click()
        app.menuBars.menuItems["Undo"].click()
        XCTAssertTrue(waitForText("!=", "Groceries"))
    }

    func testCommandZUndoesNewNoteOnceThePageHasNoTypingToUndo() {
        let before = count(of: "All Notes")
        beginNewItem()
        XCTAssertTrue(row(titled: "Untitled").waitForExistence(timeout: 2))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row(titled: "Untitled").waitForNonExistence(timeout: 2))
        XCTAssertEqual(count(of: "All Notes"), before)
    }

    func testATableIsInsertedFromTheFormatMenu() {
        beginNewItem()
        XCTAssertTrue(row(titled: "Untitled").waitForExistence(timeout: 2))
        app.typeText("Quotes")
        app.typeKey("t", modifierFlags: [.command, .option])
        let table = page.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3))
    }

    private func toggleGroupByDate() {
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Group by Date"].click()
    }

    private func sortBy(_ order: String) {
        app.menuBars.menuBarItems["View"].click()
        let sortBy = app.menuBars.menuItems["Sort By"]
        sortBy.hover()
        sortBy.menuItems[order].click()
    }

    func testCommandFOpensTheSystemFindBarInThePage() {
        row(titled: "Kitchen quotes").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        editor.click()
        let fields = window.searchFields.count
        window.typeKey("f", modifierFlags: .command)
        let findField = window.searchFields.element(boundBy: fields)
        XCTAssertTrue(findField.waitForExistence(timeout: 2), "the find bar shows its search field")
        findField.typeText("quote")
        XCTAssertTrue(window.staticTexts["3"].waitForExistence(timeout: 2), "the find bar counts the matches")
        findField.typeKey(.escape, modifierFlags: [])
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: findField)], timeout: 2)
    }

    func testTheFoldersHeadingCreatesANewFolderFromItsContextMenu() {
        let heading = sidebarItem("Folders")
        heading.rightClick()
        let newFolder = window.menuItems["New Folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 2))
        newFolder.click()
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Projects")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(sidebarItem("Projects").waitForExistence(timeout: 2))
    }

    // MARK: The page under the toolbar

    func testALongNoteStartsBelowTheToolbarAndScrollsSteadilyUnderIt() {
        sidebarItem("Reading").click()
        row(titled: "The Design of Everyday Things").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "The Design of Everyday Things"))
        // The sample alone can fit a restored, maximized window. Add enough text to overflow any
        // viewport this test uses, so it tests scrolling rather than the screen's dimensions.
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        let paragraphs = max(80, Int(window.frame.height / 20) * 2)
        app.typeText("\n\nScroll overflow.\n\n" + Array(repeating: "x", count: paragraphs).joined(separator: "\n\n"))
        XCTAssertTrue(waitForText("CONTAINS", "Scroll overflow."))
        app.typeKey(.upArrow, modifierFlags: .command)
        let title = page.staticTexts["The Design of Everyday Things"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(title.frame.minY, window.toolbars.firstMatch.frame.maxY, "the note starts below the toolbar")
        let heading = page.staticTexts["The psychology of everyday actions"].firstMatch
        var last = heading.frame.minY
        for _ in 0..<10 {
            page.scroll(byDeltaX: 0, deltaY: -15)
            let now = heading.frame.minY
            // Each step moves the text up by the step, never back and never by a jump.
            XCTAssertEqual(last - now, 15, accuracy: 4, "the page moved \(last - now) for a 15 point scroll")
            last = now
        }
    }

    func testAShortNoteStaysPutWhenScrolled() {
        row(titled: "Garden ideas").click()
        let title = page.staticTexts["Garden ideas"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        let before = title.frame.minY
        page.scroll(byDeltaX: 0, deltaY: -40)
        XCTAssertEqual(title.frame.minY, before, accuracy: 2, "a note shorter than the window has nothing to scroll")
    }

    func testMoreAndDetailsSitAtTheToolbarsEnd() {
        let more = window.menuButtons["More"]
        let details = window.descendants(matching: .any).matching(identifier: "DetailsToggle").element(boundBy: 0)
        XCTAssertTrue(more.waitForExistence(timeout: 2))
        XCTAssertTrue(details.exists)
        XCTAssertLessThan(window.frame.maxX - details.frame.maxX, 30, "Details is at the end, not mid-toolbar")
        XCTAssertLessThan(more.frame.maxX, details.frame.minX, "More comes just before it")
    }

    // MARK: Back and forward

    func testBackAndForwardMoveThroughTheItemsOpened() {
        let back = window.descendants(matching: .any).matching(identifier: "BackToolbar").element(boundBy: 0)
        let forward = window.descendants(matching: .any).matching(identifier: "ForwardToolbar").element(boundBy: 0)
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        XCTAssertFalse(back.isEnabled, "nothing was opened before the first note")
        row(titled: "Recipes to try").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"))
        XCTAssertTrue(back.isEnabled)
        XCTAssertFalse(forward.isEnabled, "nothing lies ahead")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        XCTAssertTrue(forward.isEnabled)
        XCTAssertFalse(back.isEnabled)
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"))
        back.click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        forward.click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"))
    }

    func testBackAndForwardKeysBelongToThePageWhileItHasTheKeyboard() {
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"))
        row(titled: "Recipes to try").click()
        XCTAssertTrue(waitForText("BEGINSWITH", "Recipes to try"))
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("[", modifierFlags: .command)
        XCTAssertFalse(waitForText("BEGINSWITH", "Kitchen quotes"), "the page keeps ⌘[ while it has the keyboard")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForText("BEGINSWITH", "Kitchen quotes"), "the list has the keyboard again, so ⌘[ goes back")
    }

    func testTheMainWindowPassesTheAccessibilityAudit() throws {
        // Some findings belong to the system rather than the app: List reports its section headers outside
        // their table, SwiftUI wraps columns and section headers in unlabelled groups that VoiceOver passes
        // through, and the sidebar's counts and the list's previews and dates are the system's secondary
        // colour, as Mail and Notes draw them, which the audit finds a shade short; a toolbar menu offers Show
        // Menu rather than Press. The list's title and count in the toolbar above it are the system's too.
        // Controls and text are still audited everywhere else.
        let windowFrame = window.frame
        let sidebarFrame = sidebar.frame
        let listFrame = list.frame
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            // The audit is of the window; the menu bar above it is the system's to draw.
            if !windowFrame.intersects(element.frame) { return true }
            // A tooltip, shown where the pointer happens to rest, is the system's to draw and describe.
            if element.elementType == .helpTag { return true }
            switch issue.auditType {
            case .parentChild: return true
            case .sufficientElementDescription: return element.elementType == .group && element.label.isEmpty
            case .contrast:
                // A row cut off at the pane's edge still belongs to the pane.
                @MainActor func isIn(_ pane: CGRect) -> Bool {
                    element.frame.intersects(pane) && element.frame.minX >= pane.minX && element.frame.maxX <= pane.maxX
                }
                let isListTitle = element.frame.minY < listFrame.minY
                    && element.frame.minX >= listFrame.minX && element.frame.maxX <= listFrame.maxX
                return isIn(sidebarFrame) || isIn(listFrame) || isListTitle
            case .action: return element.elementType == .menuButton || element.elementType == .popUpButton
            default: return false
            }
        }
    }
}
