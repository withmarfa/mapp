import AppKit
import XCTest

@MainActor
final class ItemToolbarTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(window.webViews.firstMatch.textViews.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testTheListToolbarHoldsViewOptionsSearchAndNewItemAndThePageToolbarHoldsHistoryViewAsMoreAndDetails() {
        let viewMode = control("ViewModeMenu")
        let viewOptions = control("ViewOptionsToolbar")
        let newItem = control("NewItemToolbar")
        let back = control("BackToolbar")
        let forward = control("ForwardToolbar")
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        for element in [viewMode, viewOptions, newItem, back, forward, details, more] { XCTAssertTrue(element.exists) }
        XCTAssertEqual(count("DetailsToggle"), 1, "The closed inspector adds no second Details")
        XCTAssertEqual(count("MoreToolbar"), 1, "The closed inspector adds no second More")
        XCTAssertFalse(control("FormatToolbar").exists, "Format is out of the default toolbar")
        let page = window.itemPageTitle.frame
        XCTAssertLessThan(newItem.frame.maxX, page.minX, "New Item belongs to the list column")
        XCTAssertLessThan(viewOptions.frame.maxX, newItem.frame.minX)
        XCTAssertGreaterThan(back.frame.minX, newItem.frame.maxX, "Back and Forward lead the page column, not the list column")
        XCTAssertLessThan(back.frame.maxX, forward.frame.minX)
        XCTAssertLessThan(forward.frame.maxX, viewMode.frame.minX, "View As is on the page's trailing side, as in the gallery")
        XCTAssertLessThan(viewMode.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, details.frame.minX, "Details is at the far right")
        XCTAssertGreaterThan(more.frame.minX, window.frame.midX)
        XCTAssertEqual(details.frame.midY, more.frame.midY, accuracy: 3)
        capture("List and page toolbars")
    }

    func testDetailsAndMoreMoveAboveTheInspectorWhileItIsOpen() {
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        details.click()
        let inspector = window.descendants(matching: .any)["ItemInspectorDetails"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        XCTAssertTrue(details.exists)
        XCTAssertTrue(more.exists)
        XCTAssertEqual(count("DetailsToggle"), 1)
        XCTAssertEqual(count("MoreToolbar"), 1)
        XCTAssertGreaterThanOrEqual(more.frame.minX, inspector.frame.minX, "More and Details sit above the inspector column")
        XCTAssertLessThan(more.frame.maxX, details.frame.minX)
        XCTAssertTrue(control("BackToolbar").exists, "Back and Forward stay with the page")
        XCTAssertTrue(control("ForwardToolbar").exists)
        capture("Details and More above the inspector")
        details.click()
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 3))
        XCTAssertTrue(control("DetailsToggle").exists, "Details returns to the page toolbar")
        XCTAssertEqual(count("DetailsToggle"), 1)
        XCTAssertEqual(count("MoreToolbar"), 1)
    }

    func testViewOptionsOffersSortByAndGroupByDate() {
        control("ViewOptionsToolbar").click()
        for title in ["Date Edited", "Date Created", "Title", "Group by Date"] {
            XCTAssertTrue(window.menuItems[title].waitForExistence(timeout: 3), title)
        }
        XCTAssertFalse(window.menuItems["Gallery"].exists, "View As has the views now")
        XCTAssertFalse(window.menuItems["View As"].exists)
        var previous = -CGFloat.infinity
        for title in ["Sort By", "Date Edited", "Date Created", "Title", "Group by Date"] {
            let item = window.menuItems[title].firstMatch
            XCTAssertGreaterThan(item.frame.minY, previous, "\(title) follows the item before it")
            previous = item.frame.minY
        }
        capture("View Options menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testMoreHoldsTheItemActionsInOrder() {
        control("MoreToolbar").click()
        let titles = ["Open in New Window", "Share…", "Add to Favorites", "Move To", "Add Attachment…", "Rename…",
                      "Page Width", "Show Markdown Source", "Print…", "Export as PDF…", "Delete"]
        var previous = -CGFloat.infinity
        for title in titles {
            let item = window.menuItems[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), title)
            XCTAssertGreaterThan(item.frame.minY, previous, "\(title) follows the item before it")
            previous = item.frame.minY
        }
        XCTAssertFalse(window.menuItems["Archive"].exists)
        XCTAssertFalse(window.menuItems["Copy Link"].exists)
        capture("More menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testANewItemDraftDisablesTheItemActions() {
        control("NewItemToolbar").click()
        XCTAssertTrue(window.textFields["NewItemTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(control("DetailsToggle").isEnabled)
        control("MoreToolbar").click()
        XCTAssertFalse(window.menuItems["Share…"].isEnabled)
        XCTAssertFalse(window.menuItems["Add Attachment…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testMovedAttachmentAndFormattingActionsStillWork() {
        let page = window.webViews.firstMatch
        let editor = page.textViews.firstMatch
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\nToolbar list check")
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuItems["Checklist"].click()
        XCTAssertTrue((editor.value as? String)?.contains("Toolbar list check") == true)
        control("MoreToolbar").click()
        window.menuItems["Add Attachment…"].click()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
    }

    func testViewMenuOffersTheThreeViewsAndHistoryShortcuts() {
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuBars.menuItems["View as List"].exists)
        XCTAssertTrue(app.menuBars.menuItems["View as Gallery"].exists)
        XCTAssertTrue(app.menuBars.menuItems["View as Table"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Back"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Forward"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuBars.menuItems["Print…"].exists)
        XCTAssertFalse(app.menuBars.menuItems["Archive Note"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testCommandOneAndTwoSwitchBetweenTheListAndTheGallery() {
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["ItemGallery"].waitForExistence(timeout: 3))
        let viewOptions = control("ViewOptionsToolbar")
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        let newItem = control("NewItemToolbar")
        let viewMode = control("ViewModeMenu")
        XCTAssertTrue(viewMode.exists, "View As stays reachable in the gallery")
        XCTAssertTrue(viewOptions.exists, "View Options stays reachable in the gallery")
        XCTAssertTrue(newItem.exists, "New Item stays reachable in the gallery")
        XCTAssertTrue(details.exists, "the card selected in the list is still selected, so Details and More have something to act on")
        XCTAssertLessThan(viewMode.frame.maxX, viewOptions.frame.minX)
        XCTAssertLessThan(viewOptions.frame.maxX, newItem.frame.minX)
        XCTAssertLessThan(newItem.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, details.frame.minX, "Details is at the far right")
        // ⌘2 leaves the keyboard where it was, so the grid is given it before Escape clears the selection.
        window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "GalleryItem-", "Selected")).firstMatch.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(details.waitForNonExistence(timeout: 3), "Details and More leave the grid when no card is selected")
        XCTAssertFalse(more.exists)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["ItemGallery"].waitForNonExistence(timeout: 3))
    }

    func testViewAsShowsTheTableWithItsOwnFilterAndViewOptions() {
        show("Table")
        let table = control("ItemTable")
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        XCTAssertFalse(window.outlines["NoteList"].exists, "the table spans the window")
        XCTAssertFalse(window.webViews.firstMatch.exists)
        XCTAssertTrue(control("ItemTableFilter").exists, "Filter is on the toolbar")
        control("ViewOptionsToolbar").click()
        for title in ["Sort By", "Group By", "Columns"] {
            XCTAssertTrue(window.menuItems[title].firstMatch.waitForExistence(timeout: 3), title)
        }
        XCTAssertFalse(window.menuItems["Group by Date"].exists, "the table groups by its columns")
        capture("Table View Options menu")
        app.typeKey(.escape, modifierFlags: [])
        show("Gallery")
        XCTAssertTrue(control("ItemGallery").waitForExistence(timeout: 3))
        XCTAssertTrue(table.waitForNonExistence(timeout: 3))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        show("List")
        XCTAssertTrue(window.outlines["NoteList"].waitForExistence(timeout: 3))
        XCTAssertTrue(table.waitForNonExistence(timeout: 3))
    }

    /// Chooses a view from the toolbar's View As pop-up.
    private func show(_ title: String) {
        let menu = control("ViewModeMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.click()
        let item = window.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), title)
        item.click()
    }

    private func control(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func count(_ identifier: String) -> Int {
        window.descendants(matching: .any).matching(identifier: identifier).count
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
