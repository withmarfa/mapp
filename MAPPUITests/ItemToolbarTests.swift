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

    func testTheListToolbarHoldsViewOptionsSearchAndNewItemAndThePageToolbarHoldsHistoryDetailsAndMore() {
        let viewOptions = control("ViewOptionsToolbar")
        let newItem = control("NewItemToolbar")
        let back = control("BackToolbar")
        let forward = control("ForwardToolbar")
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        for element in [viewOptions, newItem, back, forward, details, more] { XCTAssertTrue(element.exists) }
        XCTAssertFalse(control("FormatToolbar").exists, "Format is out of the default toolbar")
        let page = window.itemPageTitle.frame
        XCTAssertLessThan(newItem.frame.maxX, page.minX, "New Item belongs to the list column")
        XCTAssertLessThan(viewOptions.frame.maxX, newItem.frame.minX)
        XCTAssertGreaterThan(back.frame.minX, newItem.frame.maxX, "Back and Forward lead the page column, not the list column")
        XCTAssertLessThan(back.frame.maxX, forward.frame.minX)
        XCTAssertLessThan(forward.frame.maxX, details.frame.minX)
        XCTAssertLessThan(details.frame.maxX, more.frame.minX)
        XCTAssertGreaterThan(details.frame.minX, window.frame.midX)
        XCTAssertEqual(details.frame.midY, more.frame.midY, accuracy: 3)
        capture("List and page toolbars")
    }

    func testViewOptionsOffersViewAsAndSortBy() {
        control("ViewOptionsToolbar").click()
        for title in ["List", "Gallery", "Date Edited", "Date Created", "Title", "Group by Date"] {
            XCTAssertTrue(window.menuItems[title].waitForExistence(timeout: 3), title)
        }
        XCTAssertEqual(window.menuItems["List"].value as? Int, 1, "the list is the view shown")
        var previous = -CGFloat.infinity
        for title in ["View As", "List", "Gallery", "Sort By", "Date Edited", "Date Created", "Title", "Group by Date"] {
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

    func testViewMenuOffersTheListAndGalleryAndHistoryShortcuts() {
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuBars.menuItems["View as List"].exists)
        XCTAssertTrue(app.menuBars.menuItems["View as Gallery"].exists)
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
        XCTAssertTrue(viewOptions.exists, "View Options stays reachable in the gallery")
        XCTAssertTrue(newItem.exists, "New Item stays reachable in the gallery")
        XCTAssertTrue(details.exists, "the card selected in the list is still selected, so Details and More have something to act on")
        XCTAssertLessThan(viewOptions.frame.maxX, details.frame.minX)
        XCTAssertLessThan(details.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, newItem.frame.minX)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(details.waitForNonExistence(timeout: 3), "Details and More leave the grid when no card is selected")
        XCTAssertFalse(more.exists)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["ItemGallery"].waitForNonExistence(timeout: 3))
    }

    private func control(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
