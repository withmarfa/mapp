import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var settingsRow: XCUIElement { element("SidebarSettingsRow") }
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

    func testSidebarListsTopPlacesThenFoldersThenFavoritesWithSettingsAtTheFoot() {
        for title in ["Inbox", "Recents", "All Notes", "Folders", "Favorites", "Kitchen quotes", "Reading list"] {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        for title in ["Library", "Projects", "Recently Deleted", "All Favorites"] {
            XCTAssertFalse(sidebarText(title).exists, "\(title) is not in the sidebar")
        }
        XCTAssertFalse(sidebarText("Collections").exists, "nothing in the sample is filed under anything")
        XCTAssertTrue(settingsRow.exists)
        XCTAssertLessThan(sidebarText("Inbox").frame.maxY, sidebarText("Recents").frame.minY)
        XCTAssertLessThan(sidebarText("Recents").frame.maxY, sidebarText("All Notes").frame.minY)
        XCTAssertLessThan(sidebarText("All Notes").frame.maxY, sidebarText("Folders").frame.minY)
        XCTAssertLessThan(sidebarText("Folders").frame.maxY, sidebarText("Favorites").frame.minY)
        XCTAssertLessThan(sidebarText("Reading list").frame.maxY, settingsRow.frame.minY, "Settings sits below the places")
        attachScreenshot("SidebarGroupedNavigation")
    }

    func testEachFavoriteShortcutSelectsItsActualItem() {
        let title = window.itemPageTitle
        for favorite in ["Kitchen quotes", "Reading list"] {
            sidebarText(favorite).click()
            let selected = expectation(for: NSPredicate(format: "value == %@", favorite), evaluatedWith: title)
            wait(for: [selected], timeout: 3)
            let other = favorite == "Kitchen quotes" ? "Reading list" : "Kitchen quotes"
            XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", other)).firstMatch.exists)
        }
    }

    func testFavoritesSectionCollapsesAndRemembersItsStateWhenSettingsCloses() {
        disclosure(for: "Favorites").click()
        XCTAssertTrue(sidebarText("Kitchen quotes").waitForNonExistence(timeout: 3))
        XCTAssertFalse(sidebarText("Reading list").exists)
        XCTAssertTrue(sidebarText("Folders").exists)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        sidebarText("All Notes").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Favorites").exists)
        XCTAssertFalse(sidebarText("Reading list").exists)
        disclosure(for: "Favorites").click()
        XCTAssertTrue(sidebarText("Reading list").waitForExistence(timeout: 3))
    }

    func testTheSettingsRowAtTheFootOpensSettingsInTheWindowAndAPlaceLeavesIt() {
        settingsRow.hover()
        attachScreenshot("SettingsRowHover")
        settingsRow.click()
        XCTAssertTrue(settingsPages.waitForExistence(timeout: 3))
        XCTAssertFalse(list.exists, "the pages take the list's column")
        XCTAssertTrue(sidebar.exists, "the sidebar stays")
        XCTAssertEqual(app.windows.count, 1)
        attachScreenshot("SettingsRowSelected")
        sidebarText("Inbox").click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertFalse(settingsPages.exists)
    }

    func testFavoritesSectionDisappearsAfterTheLastItemIsRemoved() {
        for favorite in ["Kitchen quotes", "Reading list"] {
            let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", favorite)).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3))
            note.rightClick()
            window.menuItems["Remove from Favorites"].click()
            XCTAssertTrue(sidebarText(favorite).waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(sidebarText("Favorites").waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Folders").exists)
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch
        note.rightClick()
        window.menuItems["Add to Favorites"].click()
        XCTAssertTrue(sidebarText("Favorites").waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Reading list").waitForExistence(timeout: 3))
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
        sidebarText("All Notes").click()
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

    func testAnItemFiledUnderAnotherMakesItACollection() {
        create(type: "Project", title: "Field research")
        XCTAssertFalse(sidebarText("Collections").exists, "a project with nothing under it is no collection")
        create(type: "Task", title: "Survey the site", parent: "Field research")
        XCTAssertTrue(sidebarText("Collections").waitForExistence(timeout: 3))
        XCTAssertLessThan(sidebarText("Folders").frame.maxY, sidebarText("Collections").frame.minY)
        XCTAssertLessThan(sidebarText("Collections").frame.maxY, sidebarText("Favorites").frame.minY)
        let collection = sidebar.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND (label == %@ OR value == %@)", "SidebarCollection-", "Field research", "Field research"))
            .element(boundBy: 0)
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        collection.click()
        XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Survey the site")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch.exists)
        disclosure(for: "Collections").click()
        XCTAssertTrue(collection.waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Collections").exists)
        disclosure(for: "Collections").click()
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
    }

    private func create(type: String, title: String, parent: String? = nil) {
        app.typeKey("n", modifierFlags: .command)
        let typePicker = window.descendants(matching: .any)["NewItemType"]
        XCTAssertTrue(typePicker.waitForExistence(timeout: 3))
        typePicker.click()
        window.menuItems[type].click()
        if let parent {
            window.descendants(matching: .any)["NewItemParent"].click()
            window.menuItems[parent].click()
        }
        let field = window.textFields["NewItemTitle"]
        field.click()
        field.typeText(title)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
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
        if title == "Favorites" {
            sidebarText(title).hover()
        }
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
        case "Favorites": "SidebarFavoritesSection"
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
