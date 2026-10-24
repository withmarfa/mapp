import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var instanceMenu: XCUIElement { element("SidebarLibrary") }
    private var settingsPages: XCUIElement { element("SettingsPageList") }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testSidebarListsTopPlacesThenFoldersAndViews() {
        let destinations = ["Inbox", "Recents", "Items", "Sources", "Collections", "Favorites", "Folders", "Views"]
        for title in destinations {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        for title in ["Browse", "Files", "Recently Deleted", "Kitchen quotes", "Reading list"] {
            XCTAssertFalse(sidebarText(title).exists, "\(title) is not in the sidebar")
        }
        XCTAssertTrue(instanceMenu.exists)
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

    func testFoldersRememberTheirCollapsedStateWhenSettingsCloses() {
        disclosure(for: "Folders").click()
        XCTAssertTrue(sidebarText("Home").waitForNonExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        sidebarText("Items").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Folders").exists)
        XCTAssertFalse(sidebarText("Home").exists)
        disclosure(for: "Folders").click()
        XCTAssertTrue(sidebarText("Home").waitForExistence(timeout: 3))
    }

    func testTheInstanceMenuOpensSettingsInTheWindowAndAPlaceLeavesIt() {
        instanceMenu.click()
        let settings = app.menuItems["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Recently Deleted"].exists)
        settings.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        XCTAssertFalse(list.exists, "the pages take the list's column")
        XCTAssertTrue(sidebar.exists, "the sidebar stays")
        XCTAssertEqual(app.windows.count, 1)
        attachScreenshot("SettingsFromInstanceMenu")
        sidebarText("Inbox").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertFalse(settingsPages.exists)
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
        XCTAssertTrue(sidebarText("Folders").exists)
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
        sidebarText("Folders").rightClick()
        window.menuItems["Hide from Sidebar"].click()
        XCTAssertTrue(sidebarText("Folders").waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Home").waitForNonExistence(timeout: 3), "the folders go with their section")
        XCTAssertTrue(sidebarText("Favorites").exists, "the other places stay")

        app.typeKey(",", modifierFlags: .command)
        let page = element("SettingsPage-sidebar")
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
        let toggle = element("SidebarSetting-folders")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? Int, 0, "Settings lists the place switched off")
        toggle.click()
        XCTAssertTrue(sidebarText("Folders").waitForExistence(timeout: 3), "the sidebar beside Settings follows at once")
        sidebarText("Items").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Home").exists)
    }

    func testCollapsedFoldersExpandForCreationAndKeepRenameAndDelete() {
        disclosure(for: "Folders").click()
        XCTAssertTrue(sidebarText("Home").waitForNonExistence(timeout: 3))
        app.typeKey("n", modifierFlags: [.command, .shift])
        let field = sidebar.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Research")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3), "Return commits the new folder name")
        XCTAssertTrue(sidebarText("Research").waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Home").exists, "creation expands the native folder group")

        sidebarText("Research").rightClick()
        window.menuItems["Rename Folder"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Archive")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3), "Return commits the renamed folder")
        XCTAssertTrue(sidebarText("Archive").waitForExistence(timeout: 3))
        sidebarText("Archive").rightClick()
        window.menuItems["Delete Folder"].click()
        let confirm = app.sheets.buttons["Delete Folder"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        XCTAssertTrue(sidebarText("Archive").waitForNonExistence(timeout: 3))
    }

    func testAnItemFiledUnderAnotherAppearsInTheCollectionsIndex() {
        create(type: "Project", title: "Field research")
        XCTAssertTrue(sidebarText("Collections").exists, "the collections index stays available when empty")
        XCTAssertFalse(sidebarText("Field research").exists, "a project with nothing under it is no collection")
        create(type: "Task", title: "Survey the site", parent: "Field research")
        XCTAssertTrue(sidebarText("Collections").waitForExistence(timeout: 3))
        XCTAssertLessThan(sidebarText("Sources").frame.maxY, sidebarText("Collections").frame.minY)
        XCTAssertLessThan(sidebarText("Collections").frame.maxY, sidebarText("Favorites").frame.minY)
        XCTAssertFalse(sidebarText("Field research").exists, "Collection entries belong in the index")
        sidebarText("Collections").click()
        let index = element("SidebarIndex")
        XCTAssertTrue(index.waitForExistence(timeout: 3))
        let collection = index.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Field research")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        collection.click()
        XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Survey the site")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch.exists)
    }

    private func create(type: String, title: String, parent: String? = nil) {
        window.buttons["NewItemToolbar"].click()
        window.menuItems[type].click()
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        app.typeText(title)
        app.typeKey(.return, modifierFlags: [])
        if let parent {
            window.itemParentPin.click()
            window.menuItems[parent].click()
        }
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

    private func disclosure(for title: String) -> XCUIElement {
        sidebarText(title).hover()
        let row: XCUIElement
        if let identifier = groupIdentifier(for: title) {
            row = sidebar.outlineRows.containing(.any, identifier: identifier).element(boundBy: 0)
        } else {
            row = sidebar.outlineRows.containing(NSPredicate(format: "label == %@ OR value == %@", title, title)).firstMatch
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let disclosure = row.disclosureTriangles.element(boundBy: 0)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3), "\(title) has a native disclosure control")
        return disclosure
    }

    private func groupIdentifier(for title: String) -> String? {
        switch title {
        case "Favorites": "SidebarFavorites"
        case "Sources": "SidebarSources"
        case "Collections": "SidebarCollections"
        case "Folders": "SidebarFolders"
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
