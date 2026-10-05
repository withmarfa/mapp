import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }
    private var list: XCUIElement { window.outlines["NoteList"] }

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

    func testSidebarKeepsTopPlacesAndPinsAboveTheNativeGroups() {
        for title in ["Inbox", "All Notes", "Pinned", "Kitchen quotes", "Reading list", "Library", "Projects", "Items", "Folders"] {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        XCTAssertFalse(sidebarText("All Pinned").exists)
        XCTAssertLessThan(sidebarText("All Notes").frame.maxY, sidebarText("Pinned").frame.minY)
        XCTAssertLessThan(sidebarText("Reading list").frame.maxY, sidebarText("Library").frame.minY)
        XCTAssertLessThan(sidebarText("Library").frame.maxY, sidebarText("Projects").frame.minY)
        let places = window.outlines["SidebarPlaces"]
        XCTAssertTrue(places.staticTexts["Marfa Types"].exists)
        XCTAssertTrue(places.staticTexts["Recently Deleted"].exists)
        attachScreenshot("SidebarGroupedNavigation")
    }

    func testEachPinnedShortcutSelectsItsActualItem() {
        let title = window.textFields["ItemPageTitle"]
        for pin in ["Kitchen quotes", "Reading list"] {
            sidebarText(pin).click()
            let selected = expectation(for: NSPredicate(format: "value == %@", pin), evaluatedWith: title)
            wait(for: [selected], timeout: 3)
            let other = pin == "Kitchen quotes" ? "Reading list" : "Kitchen quotes"
            XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", other)).firstMatch.exists)
        }
    }

    func testPinnedSectionCollapsesAndRemembersItsStateWhenSettingsCloses() {
        disclosure(for: "Pinned").click()
        XCTAssertTrue(sidebarText("Kitchen quotes").waitForNonExistence(timeout: 3))
        XCTAssertFalse(sidebarText("Reading list").exists)
        XCTAssertTrue(sidebarText("Library").exists)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.buttons["SettingsBack"].waitForExistence(timeout: 3))
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(sidebarText("Pinned").waitForExistence(timeout: 3))
        XCTAssertFalse(sidebarText("Reading list").exists)
        disclosure(for: "Pinned").click()
        XCTAssertTrue(sidebarText("Reading list").waitForExistence(timeout: 3))
    }

    func testFooterHoverAndSelectionKeepTheNativeAppearance() {
        let places = window.outlines["SidebarPlaces"]
        let types = places.staticTexts["Marfa Types"]
        XCTAssertTrue(types.waitForExistence(timeout: 3))
        types.hover()
        attachScreenshot("FooterMarfaTypesHover")
        types.click()
        XCTAssertTrue(window.groups["MarfaTypes"].webViews.firstMatch.waitForExistence(timeout: 5))
        types.hover()
        attachScreenshot("FooterMarfaTypesSelected")

        let deleted = places.staticTexts["Recently Deleted"]
        deleted.click()
        XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Old packing list")).firstMatch.waitForExistence(timeout: 3))
        attachScreenshot("FooterRecentlyDeletedSelected")
    }

    func testPinnedSectionDisappearsAfterTheLastItemIsUnpinned() {
        for pin in ["Kitchen quotes", "Reading list"] {
            let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", pin)).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3))
            note.rightClick()
            window.menuItems["Unpin"].click()
            XCTAssertTrue(sidebarText(pin).waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(sidebarText("Pinned").waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Library").exists)
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Reading list")).firstMatch
        note.rightClick()
        window.menuItems["Pin"].click()
        XCTAssertTrue(sidebarText("Pinned").waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Reading list").waitForExistence(timeout: 3))
    }

    func testItemsDisclosureRemembersItsStateWhenSettingsCloses() {
        XCTAssertFalse(sidebarText("Note").exists)
        disclosure(for: "Items").click()
        XCTAssertTrue(sidebarText("Note").waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Files").exists)
        XCTAssertFalse(sidebarText("Project").exists, "Projects is the only project collection row")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.buttons["SettingsBack"].waitForExistence(timeout: 3))
        window.buttons["SettingsBack"].click()
        XCTAssertTrue(sidebarText("Note").waitForExistence(timeout: 3))
        disclosure(for: "Items").click()
        XCTAssertTrue(sidebarText("Note").waitForNonExistence(timeout: 3))
        XCTAssertTrue(window.outlines["SidebarPlaces"].staticTexts["Recently Deleted"].exists)
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

    func testProjectsCreatesAProjectAndExposesItsCollection() {
        sidebarText("Projects").click()
        app.typeKey("n", modifierFlags: .command)
        let title = window.textFields["NewItemTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Field research\r")
        let project = sidebarText("Field research")
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        project.click()
        XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Field research")).firstMatch.waitForExistence(timeout: 3))
        disclosure(for: "Projects").click()
        XCTAssertTrue(project.waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Projects").exists)
        disclosure(for: "Projects").click()
        XCTAssertTrue(project.waitForExistence(timeout: 3))
    }

    private func sidebarText(_ title: String) -> XCUIElement {
        if let identifier = groupIdentifier(for: title) {
            // Use the full indexed query: firstMatch omitted native outline labels visible in its own snapshot.
            return sidebar.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
        }
        return sidebar.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).firstMatch
    }

    private func disclosure(for title: String) -> XCUIElement {
        if title == "Pinned" {
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
        case "Pinned": "SidebarPinnedSection"
        case "Library": "SidebarLibrarySection"
        case "Projects": "SidebarProjects"
        case "Items": "SidebarItems"
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
