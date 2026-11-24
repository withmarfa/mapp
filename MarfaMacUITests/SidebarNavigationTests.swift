import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["ItemList"] }
    private var instanceName: XCUIElement { element("SidebarSettings") }
    private var settingsPages: XCUIElement { element("SettingsSidebar") }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("ItemsIndex").waitForExistence(timeout: 5), "the window opens on the Items index")
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testSidebarListsNewAndSearchThenTheLibraryGroupThenViewsAndTypes() {
        let destinations = ["New", "Search", "Library", "Items", "Sources", "Collections", "Views", "Inbox", "Recents", "Favorites", "Recent Notes", "Types"]
        for title in destinations {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        for title in ["Files", "Recently Deleted", "Kitchen quotes", "Reading list"] {
            XCTAssertFalse(sidebarText(title).exists, "\(title) is not in the sidebar")
        }
        XCTAssertTrue(instanceName.exists)
        XCTAssertTrue(element("SidebarSettings").exists, "the foot holds the settings cog")
        XCTAssertFalse(element("NewItemToolbar").exists, "the foot has no New Item button")
        XCTAssertTrue(element("SidebarNew").exists, "New is a row of the top block")
        XCTAssertTrue(element("SidebarSearch").exists, "Search is a row of the top block")
        XCTAssertFalse(sidebarText("Browse").exists, "New and Search have no heading")
        XCTAssertFalse(element("SidebarOpenSettings").exists, "Settings is the foot's cog")
        XCTAssertFalse(element("SidebarRecentlyDeleted").exists, "Recently Deleted is a Settings page")
        for title in ["Sources", "Collections"] {
            let row = sidebar.outlineRows.containing(NSPredicate(format: "label == %@ OR value == %@", title, title)).element(boundBy: 0)
            XCTAssertFalse(row.disclosureTriangles.firstMatch.exists, "Indexes do not expand in the sidebar")
        }
        for (before, after) in zip(destinations, destinations.dropFirst()) {
            XCTAssertLessThan(sidebarText(before).frame.maxY, sidebarText(after).frame.minY)
        }
        attachScreenshot("SidebarGroupedNavigation")
    }

    func testFavoritesListsItsItemsForSelection() {
        choose("Favorites")
        let title = window.itemPageTitle
        for favorite in ["Kitchen quotes", "Reading list"] {
            let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", favorite)).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3))
            note.click()
            let selected = expectation(for: NSPredicate(format: "value == %@", favorite), evaluatedWith: title)
            wait(for: [selected], timeout: 3)
        }
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Garden ideas")).firstMatch.exists)
    }

    func testSearchOpensFromTheKeyboardAndFromItsRow() {
        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("CommandPaletteField").waitForNonExistence(timeout: 2))
        element("SidebarSearch").click()
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testTheNewRowOpensQuickAddAndTakesNoSelection() {
        element("SidebarNew").click()
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("QuickAddTitle").waitForNonExistence(timeout: 2))
        XCTAssertTrue(element("ItemsIndex").exists, "the window stays where it was")
    }

    /// A click near the sidebar's trailing edge, level with `row`, past the end of its words.
    private func clickBeyondTheWords(of row: XCUIElement) {
        let edge = sidebar.frame
        sidebar.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: edge.width - 28, dy: row.frame.midY - edge.minY)).click()
    }

    func testTheNewAndSearchRowsTakeAClickAnywhereAlongTheirWidth() {
        clickBeyondTheWords(of: element("SidebarNew"))
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3), "New opens from the end of its row")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("QuickAddTitle").waitForNonExistence(timeout: 2))
        clickBeyondTheWords(of: element("SidebarSearch"))
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3), "Search opens from the end of its row")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testChoosingItemsFromAnotherPlaceOpensTheItemsIndex() {
        choose("Inbox")
        XCTAssertTrue(list.waitForExistence(timeout: 3), "Inbox is a list")
        choose("Items")
        XCTAssertTrue(element("ItemsIndex").waitForExistence(timeout: 3), "Items opens its index")
        XCTAssertTrue(list.waitForNonExistence(timeout: 3), "the index spans the window")
    }

    func testTheCogOpensSettingsWithNoMenu() {
        instanceName.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        XCTAssertFalse(window.menuItems["Settings"].firstMatch.exists, "the cog opens Settings directly")
        XCTAssertTrue(element("SettingsPage-recentlyDeleted").exists)
    }

    func testTheCogOpensSettingsInAWindowOfItsOwnAndTheMainWindowStays() {
        instanceName.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        // The Settings window is the front one, so the main window's parts are asked of the whole app.
        XCTAssertTrue(app.descendants(matching: .any)["ItemsIndex"].exists, "the main window keeps its page")
        XCTAssertTrue(app.outlines["Sidebar"].exists, "and its sidebar")
        XCTAssertEqual(app.windows.count, 2)
        attachScreenshot("SettingsFromInstanceMenu")
    }

    func testTheNewRowOpensQuickAdd() {
        element("SidebarNew").click()
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testFavoritesRemainsAvailableAfterTheLastItemIsRemoved() {
        choose("Favorites")
        for favorite in ["Kitchen quotes", "Reading list"] {
            let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", favorite)).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3))
            note.rightClick()
            window.menuItems["Remove from Favorites"].click()
            XCTAssertTrue(note.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(sidebarText("Favorites").exists)
        XCTAssertTrue(sidebarText("Types").exists)
        // Items is an index page; a type lists its items.
        element("SidebarType-core.note").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.rightClick()
        window.menuItems["Add to Favorites"].click()
        XCTAssertTrue(sidebarText("Favorites").waitForExistence(timeout: 3))
        choose("Favorites")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
    }

    func testTheCollectionsIndexListsTheLibrarysCollections() {
        XCTAssertTrue(sidebarText("Collections").waitForExistence(timeout: 3))
        XCTAssertLessThan(sidebarText("Sources").frame.maxY, sidebarText("Collections").frame.minY)
        XCTAssertLessThan(sidebarText("Collections").frame.maxY, sidebarText("Favorites").frame.minY, "the indexes are in the Library group, above Views")
        XCTAssertFalse(sidebarText("Home").exists, "collection entries belong in the index")
        choose("Collections")
        let index = window.outlines["IndexPage"]
        XCTAssertTrue(index.waitForExistence(timeout: 3))
        let home = index.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Home")).firstMatch
        let reading = index.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(home.frame.maxY, reading.frame.minY, "collections go by title")
        home.doubleClick()
        let boiler = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Boiler")).firstMatch
        let moving = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Moving checklist")).firstMatch
        XCTAssertTrue(boiler.waitForExistence(timeout: 3))
        XCTAssertLessThan(boiler.frame.maxY, moving.frame.minY, "members keep the collection's order")
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch.exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    /// Clicks a sidebar row at the middle of its words. The row's label is not "hittable" to UI testing, which wants the
    /// click to land on the label itself, while the list row around it takes the click.
    private func choose(_ title: String) {
        sidebarText(title).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func sidebarText(_ title: String) -> XCUIElement {
        // The visible name: a heading keeps the section's identifier, and a row keeps its own.
        sidebar.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", title, title))
            .element(boundBy: 0)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
