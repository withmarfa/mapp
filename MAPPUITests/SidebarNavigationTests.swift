import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var instanceName: XCUIElement { element("SidebarLibrary") }
    private var settingsPages: XCUIElement { element("SettingsPageList") }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testSidebarListsTopPlacesThenTypesAndViews() {
        let destinations = ["Inbox", "Recents", "Favorites", "Browse", "Items", "Sources", "Collections", "Types", "Views", "Recent Notes"]
        for title in destinations {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        for title in ["Files", "Recently Deleted", "Kitchen quotes", "Reading list"] {
            XCTAssertFalse(sidebarText(title).exists, "\(title) is not in the sidebar")
        }
        XCTAssertTrue(instanceName.exists)
        XCTAssertTrue(element("NewItemToolbar").exists, "the foot holds the New Item button")
        XCTAssertFalse(element("SidebarSearch").exists, "Search is the palette's, not the foot's")
        XCTAssertFalse(element("SidebarOpenSettings").exists, "Settings is in the instance menu")
        XCTAssertFalse(element("SidebarRecentlyDeleted").exists, "Recently Deleted is in Settings > Library")
        for identifier in ["SidebarSources", "SidebarCollections"] {
            let row = sidebar.outlineRows.containing(.any, identifier: identifier).element(boundBy: 0)
            XCTAssertFalse(row.disclosureTriangles.firstMatch.exists, "Indexes do not expand in the sidebar")
        }
        for (before, after) in zip(destinations, destinations.dropFirst()) {
            XCTAssertLessThan(sidebarText(before).frame.maxY, sidebarText(after).frame.minY)
        }
        attachScreenshot("SidebarGroupedNavigation")
    }

    func testFavoritesListsItsItemsForSelection() {
        sidebarText("Favorites").click()
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

    func testSearchOpensFromTheKeyboardWithNoSearchButtonAtTheFoot() {
        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("CommandPaletteField").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("CommandPaletteField").waitForNonExistence(timeout: 2))
    }

    func testTheInstanceMenuListsConsoleSettingsAndRecentlyDeleted() {
        instanceName.click()
        for title in ["Console", "Settings", "Recently Deleted"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 3), "\(title) is in the instance menu")
        }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Recently Deleted"].waitForNonExistence(timeout: 2))
    }

    func testTheInstanceMenuOpensSettingsInTheWindowAndAPlaceLeavesIt() {
        instanceName.click()
        app.menuItems["Settings"].click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        XCTAssertFalse(list.exists, "the pages take the list's column")
        XCTAssertTrue(sidebar.exists, "the sidebar stays")
        XCTAssertEqual(app.windows.count, 1)
        attachScreenshot("SettingsFromInstanceMenu")
        sidebarText("Inbox").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertFalse(settingsPages.exists)
    }

    func testTheFootsNewItemButtonOpensQuickAdd() {
        element("NewItemToolbar").click()
        XCTAssertTrue(element("QuickAddTitle").waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testFavoritesRemainsAvailableAfterTheLastItemIsRemoved() {
        sidebarText("Favorites").click()
        for favorite in ["Kitchen quotes", "Reading list"] {
            let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", favorite)).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3))
            note.rightClick()
            window.menuItems["Remove from Favorites"].click()
            XCTAssertTrue(note.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(sidebarText("Favorites").exists)
        XCTAssertTrue(sidebarText("Types").exists)
        sidebarText("Items").click()
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.rightClick()
        window.menuItems["Add to Favorites"].click()
        XCTAssertTrue(sidebarText("Favorites").waitForExistence(timeout: 3))
        sidebarText("Favorites").click()
        XCTAssertTrue(note.waitForExistence(timeout: 3))
    }

    func testAPlaceHiddenFromItsMenuIsOfferedBackInSettings() {
        sidebarText("Sources").rightClick()
        window.menuItems["Hide from Sidebar"].click()
        XCTAssertTrue(sidebarText("Sources").waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Favorites").exists, "the other places stay")

        app.typeKey(",", modifierFlags: .command)
        let page = element("SettingsPage-sidebar")
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
        let toggle = element("SidebarSetting-sources")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? Int, 0, "Settings lists the place switched off")
        toggle.click()
        XCTAssertTrue(sidebarText("Sources").waitForExistence(timeout: 3), "the sidebar beside Settings follows at once")
        sidebarText("Items").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
    }

    func testTheCollectionsIndexListsTheLibrarysCollections() {
        XCTAssertTrue(sidebarText("Collections").waitForExistence(timeout: 3))
        XCTAssertLessThan(sidebarText("Sources").frame.maxY, sidebarText("Collections").frame.minY)
        XCTAssertLessThan(sidebarText("Collections").frame.maxY, sidebarText("Favorites").frame.minY)
        XCTAssertFalse(sidebarText("Home").exists, "collection entries belong in the index")
        sidebarText("Collections").click()
        let index = element("SidebarIndex")
        XCTAssertTrue(index.waitForExistence(timeout: 3))
        let home = index.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Home")).firstMatch
        let reading = index.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Reading")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        XCTAssertLessThan(home.frame.maxY, reading.frame.minY, "collections go by title")
        home.click()
        let boiler = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Boiler")).firstMatch
        let moving = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Moving checklist")).firstMatch
        XCTAssertTrue(boiler.waitForExistence(timeout: 3))
        XCTAssertLessThan(boiler.frame.maxY, moving.frame.minY, "members keep the collection's order")
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch.exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func sidebarText(_ title: String) -> XCUIElement {
        if let identifier = groupIdentifier(for: title) {
            // Use the full indexed query: firstMatch omitted native outline labels visible in its own snapshot.
            return sidebar.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
        }
        return sidebar.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).firstMatch
    }

    private func groupIdentifier(for title: String) -> String? {
        switch title {
        case "Favorites": "SidebarFavorites"
        case "Sources": "SidebarSources"
        case "Collections": "SidebarCollections"
        case "Types": "SidebarTypes"
        default: nil
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
