import XCTest

nonisolated final class SidebarNavigationTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    @MainActor private var list: XCUIElement { window.outlines["ItemList"] }
    @MainActor private var instanceName: XCUIElement { element("SidebarSettings") }
    @MainActor private var settingsPages: XCUIElement { element("SettingsSidebar") }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("TopRowTitle").waitForExistence(timeout: 5), "the window opens on the Library")
    }

    @MainActor override func tearDown() async throws {
        app.terminate()
    }

    @MainActor func testSidebarListsNewAndSearchThenTheLibraryGroupThenViewsAndTypes() {
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

    @MainActor func testFavoritesListsItsItemsForSelection() {
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

    @MainActor func testSearchOpensFromTheKeyboardAndFromItsRow() {
        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("CommandPaletteField").waitForNonExistence(timeout: 2))
        element("SidebarSearch").click()
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor func testTheNewRowOpensQuickAddAndTakesNoSelection() {
        element("SidebarNew").click()
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("QuickAddTitle").waitForNonExistence(timeout: 2))
        XCTAssertTrue(element("TopRowTitle").exists, "the window stays where it was")
    }

    /// A click near the sidebar's trailing edge, level with `row`, past the end of its words.
    @MainActor private func clickBeyondTheWords(of row: XCUIElement) {
        let edge = sidebar.frame
        sidebar.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: edge.width - 28, dy: row.frame.midY - edge.minY)).click()
    }

    @MainActor func testTheNewAndSearchRowsTakeAClickAnywhereAlongTheirWidth() {
        clickBeyondTheWords(of: element("SidebarNew"))
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3), "New opens from the end of its row")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("QuickAddTitle").waitForNonExistence(timeout: 2))
        clickBeyondTheWords(of: element("SidebarSearch"))
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3), "Search opens from the end of its row")
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor func testTheCogOpensSettingsWithNoMenu() {
        instanceName.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        XCTAssertFalse(window.menuItems["Settings"].firstMatch.exists, "the cog opens Settings directly")
        XCTAssertTrue(element("SettingsPage-recentlyDeleted").exists)
    }

    @MainActor func testTheCogOpensSettingsInAWindowOfItsOwnAndTheMainWindowStays() {
        instanceName.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        // The Settings window is the front one, so the main window's parts are asked of the whole app.
        XCTAssertTrue(app.descendants(matching: .any)["TopRowTitle"].exists, "the main window keeps its page")
        XCTAssertTrue(app.outlines["Sidebar"].exists, "and its sidebar")
        XCTAssertEqual(app.windows.count, 2)
        attachScreenshot("SettingsFromInstanceMenu")
    }

    @MainActor func testTheNewRowOpensQuickAdd() {
        element("SidebarNew").click()
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor func testFavoritesRemainsAvailableAfterTheLastItemIsRemoved() {
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
        // A type lists its items.
        element("SidebarType-core.note").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.rightClick()
        window.menuItems["Add to Favorites"].click()
        XCTAssertTrue(sidebarText("Favorites").waitForExistence(timeout: 3))
        choose("Favorites")
        // Reading list is also in the Notes list, so the row alone would show a missed click as a pass.
        let shown = expectation(for: NSPredicate(format: "title BEGINSWITH %@", "Favorites"), evaluatedWith: window)
        wait(for: [shown], timeout: 3)
        XCTAssertTrue(note.waitForExistence(timeout: 3))
    }

    @MainActor func testTheCollectionsIndexListsTheLibrarysCollections() {
        XCTAssertTrue(sidebarText("Collections").waitForExistence(timeout: 3))
        XCTAssertLessThan(sidebarText("Sources").frame.maxY, sidebarText("Collections").frame.minY)
        XCTAssertLessThan(sidebarText("Collections").frame.maxY, sidebarText("Favorites").frame.minY, "the indexes are in the Library group, above Views")
        XCTAssertFalse(sidebarText("Home").exists, "collection entries belong in the index")
        choose("Collections")
        let index = element("PlaceIndexTable")
        XCTAssertTrue(index.waitForExistence(timeout: 3))
        let home = index.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Home")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        home.doubleClick()
        let boiler = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Boiler")).firstMatch
        let moving = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Moving checklist")).firstMatch
        XCTAssertTrue(boiler.waitForExistence(timeout: 3))
        XCTAssertLessThan(boiler.frame.maxY, moving.frame.minY, "members keep the collection's order")
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch.exists)
    }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    /// Clicks a sidebar row at the middle of its words. The row's label is not "hittable" to UI testing, which wants the
    /// click to land on the label itself, while the list row around it takes the click.
    @MainActor private func choose(_ title: String) {
        sidebarText(title).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor private func sidebarText(_ title: String) -> XCUIElement {
        // The visible name: a heading keeps the section's identifier, and a row keeps its own.
        sidebar.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", title, title))
            .element(boundBy: 0)
    }

    @MainActor private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
