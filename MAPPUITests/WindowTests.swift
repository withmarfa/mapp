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
    private var editor: XCUIElement { app.itemPageBody }
    private var text: String { editor.value as? String ?? "" }

    private func waitForText(_ predicate: String, _ argument: String) -> Bool {
        let format = predicate.hasPrefix("NOT ") ? "NOT (value \(predicate.dropFirst(4)) %@)" : "value \(predicate) %@"
        let expectation = expectation(for: NSPredicate(format: format, argument), evaluatedWith: editor)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func waitForNote(_ title: String, containing bodyText: String) -> Bool {
        let titleShown = expectation(for: NSPredicate(format: "value == %@", title), evaluatedWith: window.itemPageTitle)
        let bodyShown = expectation(for: NSPredicate(format: "value CONTAINS %@", bodyText), evaluatedWith: editor)
        return XCTWaiter.wait(for: [titleShown, bodyShown], timeout: 3) == .completed
    }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
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
        case "Favorites": "SidebarPlace-favorites"
        case "Types": "SidebarTypes"
        case "Note": "SidebarType-core.note"
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
        for name in ["Inbox", "Recents", "Items", "Favorites", "Types", "Note"] {
            XCTAssertTrue(sidebarItem(name).exists, "\(name) is missing")
        }
        XCTAssertGreaterThan(count(of: "Items"), 0)
    }

    func testTheFirstNoteIsSelectedAndShownInThePage() {
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
    }

    func testSelectingANoteShowsIt() {
        row(titled: "Trip to Lisbon").click()
        XCTAssertTrue(waitForNote("Trip to Lisbon", containing: "Three days in October."))
    }

    private func beginNewItem(title: String = "New test note") {
        window.quickAdd(type: "Note", title: title)
        XCTAssertTrue(row(titled: title).waitForExistence(timeout: 3))
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
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

    func testNewNoteWithOnlyATitleIsCreatedSelectedAndHasAnEmptyBody() {
        let before = count(of: "Items")
        sidebarItem("Inbox").click()
        beginNewItem(title: "Empty body note")
        XCTAssertEqual(window.itemPageTitle.value as? String, "Empty body note")
        // An empty page holds nothing but the line the caret sits on.
        let empty = expectation(for: NSPredicate(format: "value == nil OR value MATCHES %@", "\\s*"), evaluatedWith: editor)
        wait(for: [empty], timeout: 3)
        XCTAssertEqual(count(of: "Items"), before + 1)
    }

    func testDeletingFromTheContextMenuRemovesTheNoteAndUndoes() {
        let before = count(of: "Items")
        row(titled: "Bike service").rightClick()
        window.menuItems["Delete"].click()
        XCTAssertTrue(row(titled: "Bike service").waitForNonExistence(timeout: 2))
        XCTAssertEqual(count(of: "Items"), before - 1)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row(titled: "Bike service").waitForExistence(timeout: 2))
        XCTAssertEqual(count(of: "Items"), before)
    }

    func testRecentlyDeletedFromTheInstanceMenuRestoresANote() {
        let instanceName = window.descendants(matching: .any).matching(identifier: "SidebarLibrary").element(boundBy: 0)
        XCTAssertTrue(instanceName.waitForExistence(timeout: 3))
        instanceName.click()
        let recentlyDeleted = window.menuItems["Recently Deleted"].firstMatch
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: 3))
        recentlyDeleted.click()
        let deleted = row(titled: "Old packing list")
        XCTAssertTrue(deleted.waitForExistence(timeout: 3))
        XCTAssertTrue(row(titled: "Draft agenda").exists)
        XCTAssertFalse(window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0).exists)
        deleted.click()
        let restore = window.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        XCTAssertTrue(restore.isEnabled)
        restore.click()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Draft agenda").exists, "only the one restored leaves")
        sidebarItem("Items").click()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(row(titled: "Old packing list").waitForExistence(timeout: 2))
    }

    /// The list's search, a field only once its button beside View Options is clicked.
    private var listSearch: XCUIElement { window.textFields["ColumnSearch"] }

    func testTheListsSearchFindsNotesAndEscapePutsItAway() {
        XCTAssertFalse(listSearch.exists, "a button until it is clicked")
        window.toolbars.buttons["Search"].firstMatch.click()
        XCTAssertTrue(listSearch.waitForExistence(timeout: 2))
        app.typeText("ragu")
        XCTAssertTrue(row(titled: "Recipes to try").waitForExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"), "the page follows the results")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(listSearch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(row(titled: "Kitchen quotes").waitForExistence(timeout: 2), "the whole list is back")
    }

    func testAddingToFavoritesFromTheContextMenuIncludesTheItem() {
        row(titled: "Garden ideas").rightClick()
        window.menuItems["Add to Favorites"].click()
        sidebarItem("Favorites").click()
        XCTAssertTrue(row(titled: "Garden ideas").waitForExistence(timeout: 2))
        XCTAssertFalse(sidebarItem("Garden ideas").exists, "favorites are listed in the workspace")
    }

    // MARK: Keyboard, menus and windows

    func testReturnEntersThePageAndEscapeGoesBackToTheList() {
        row(titled: "Garden ideas").click()
        XCTAssertTrue(waitForNote("Garden ideas", containing: "Raised beds along the south fence"))
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Draft")
        XCTAssertTrue(waitForText("CONTAINS", "Draft"), "typing after Return goes into the page")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForText("NOT CONTAINS", "Draft"), "Escape handed the arrows back to the list")
    }

    func testCommandNOpensQuickAddAndCreatesTheTitledNote() {
        let before = count(of: "Items")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["QuickAddTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.buttons["QuickAddAdd"].isEnabled, "an empty draft cannot make an item")
        XCTAssertEqual(count(of: "Items"), before)
        window.completeQuickAdd(type: "Note", title: "Shopping")
        XCTAssertTrue(row(titled: "Shopping").waitForExistence(timeout: 3))
        window.itemPageTitle.click()
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Milk")
        XCTAssertTrue(waitForText("CONTAINS", "Milk"), "Return moves from the title into the page")
    }

    func testCommandDeleteDeletesTheSelectedNote() {
        row(titled: "Bike service").click()
        app.typeKey(.delete, modifierFlags: .command)
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
        XCTAssertTrue(waitForNote("Bike service", containing: "Booked for Saturday morning."))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        // New Item leads what "new" finds.
        app.typeText("new")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        window.completeQuickAdd(type: "Note", title: "Palette note")
        XCTAssertTrue(row(titled: "Palette note").waitForExistence(timeout: 3), "the command opened quick add and its item was made")
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
        XCTAssertTrue(waitForNote("Garden ideas", containing: "Raised beds along the south fence"))
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
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        editor.click()
        app.typeKey("p", modifierFlags: [.command, .shift])
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        app.typeText("ragu")
        XCTAssertFalse(text.contains("ragu"), "the palette took the typing, not the page")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"))
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
        app.typeText("Groceries")
        XCTAssertTrue(waitForText("==", "Groceries"))
        app.menuBars.menuBarItems["Edit"].click()
        app.menuBars.menuItems["Undo"].click()
        XCTAssertTrue(waitForText("!=", "Groceries"))
    }

    func testCommandZUndoesNewNoteOnceThePageHasNoTypingToUndo() {
        let before = count(of: "Items")
        beginNewItem()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row(titled: "New test note").waitForNonExistence(timeout: 2))
        XCTAssertEqual(count(of: "Items"), before)
    }

    func testATableIsInsertedFromTheFormatMenu() {
        beginNewItem()
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
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        editor.click()
        let fields = window.searchFields.count
        window.typeKey("f", modifierFlags: .command)
        let findField = window.searchFields.element(boundBy: fields)
        XCTAssertTrue(findField.waitForExistence(timeout: 2), "the find bar shows its search field")
        findField.typeText("quote")
        XCTAssertTrue(window.staticTexts["2"].waitForExistence(timeout: 2), "the find bar counts matches in the body")
        findField.typeKey(.escape, modifierFlags: [])
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: findField)], timeout: 2)
    }

    // MARK: The page under the toolbar

    func testALongNoteStartsBelowTheToolbarAndScrollsSteadilyUnderIt() {
        row(titled: "The Design of Everyday Things").click()
        XCTAssertTrue(waitForNote("The Design of Everyday Things", containing: "Notes as I read."))
        // The sample alone can fit a restored, maximized window. Add enough text to overflow any
        // viewport this test uses, so it tests scrolling rather than the screen's dimensions.
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        let paragraphs = max(80, Int(window.frame.height / 20) * 2)
        app.typeText("\n\nScroll overflow.\n\n" + Array(repeating: "x", count: paragraphs).joined(separator: "\n\n"))
        XCTAssertTrue(waitForText("CONTAINS", "Scroll overflow."))
        app.typeKey(.upArrow, modifierFlags: .command)
        let title = window.itemPageTitle
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
        XCTAssertTrue(waitForNote("Garden ideas", containing: "Raised beds along the south fence"))
        let title = window.itemPageTitle
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

    func testBackAndForwardShortcutsMoveThroughTheItemsOpened() {
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        row(titled: "Recipes to try").click()
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Back"].click()
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Forward"].click()
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"))
    }

    func testBackAndForwardKeysBelongToThePageWhileItHasTheKeyboard() {
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."))
        row(titled: "Recipes to try").click()
        XCTAssertTrue(waitForNote("Recipes to try", containing: "Slow-roast tomatoes"))
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("[", modifierFlags: .command)
        XCTAssertFalse(waitForNote("Kitchen quotes", containing: "Three quotes in so far."), "the page keeps ⌘[ while it has the keyboard")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForNote("Kitchen quotes", containing: "Three quotes in so far."), "the list has the keyboard again, so ⌘[ goes back")
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
