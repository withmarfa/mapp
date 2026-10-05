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
        for title in ["Inbox", "All Notes", "All Pinned", "Kitchen quotes", "Reading list", "All Projects", "Items", "Folders"] {
            XCTAssertTrue(sidebarText(title).exists, "\(title) is available")
        }
        XCTAssertLessThan(sidebarText("All Notes").frame.maxY, sidebarText("All Pinned").frame.minY)
        XCTAssertLessThan(sidebarText("Reading list").frame.maxY, sidebarText("All Projects").frame.minY)
        let places = window.outlines["SidebarPlaces"]
        XCTAssertTrue(places.staticTexts["Marfa Types"].exists)
        XCTAssertTrue(places.staticTexts["Recently Deleted"].exists)
        attachScreenshot("SidebarGroupedNavigation")
    }

    func testPinnedShortcutSelectsThatItemAndAllPinnedShowsEveryPin() {
        sidebarText("Reading list").click()
        let title = window.textFields["ItemPageTitle"]
        let selected = expectation(for: NSPredicate(format: "value == %@", "Reading list"), evaluatedWith: title)
        wait(for: [selected], timeout: 3)
        XCTAssertFalse(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch.exists)
        sidebarText("All Pinned").click()
        for pin in ["Kitchen quotes", "Reading list"] {
            XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", pin)).firstMatch.waitForExistence(timeout: 3))
        }
    }

    func testItemsDisclosureRemembersItsStateWhenSettingsCloses() {
        XCTAssertFalse(sidebarText("Note").exists)
        disclosure(for: "Items").click()
        XCTAssertTrue(sidebarText("Note").waitForExistence(timeout: 3))
        XCTAssertTrue(sidebarText("Files").exists)
        XCTAssertFalse(sidebarText("Project").exists, "All Projects is the only project collection row")
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

    func testAllProjectsCreatesAProjectAndExposesItsCollection() {
        sidebarText("All Projects").click()
        app.typeKey("n", modifierFlags: .command)
        let title = window.textFields["NewItemTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Field research\r")
        let project = sidebarText("Field research")
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        project.click()
        XCTAssertTrue(list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Field research")).firstMatch.waitForExistence(timeout: 3))
        disclosure(for: "All Projects").click()
        XCTAssertTrue(project.waitForNonExistence(timeout: 3))
        XCTAssertTrue(sidebarText("All Projects").exists)
        disclosure(for: "All Projects").click()
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
        case "All Projects": "SidebarProjects"
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
