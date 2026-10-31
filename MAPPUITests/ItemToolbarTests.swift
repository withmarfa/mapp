import AppKit
import XCTest

@MainActor
final class ItemToolbarTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.itemPageBody.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws { app.terminate() }

    func testTheSidebarFootOffersNewItemAndThePageToolbarHoldsViewAsShareMoreAndDetails() {
        let viewMode = control("ViewModeMenu")
        let viewOptions = control("ViewOptionsToolbar")
        let newItem = control("SidebarNew")
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        let share = control("ShareToolbar")
        for element in [viewMode, viewOptions, newItem, details, share, more] { XCTAssertTrue(element.exists) }
        XCTAssertFalse(control("NewItemToolbar").exists, "the toolbar's New Item shows only with the sidebar hidden")
        XCTAssertFalse(control("BackToolbar").exists)
        XCTAssertFalse(control("ForwardToolbar").exists)
        XCTAssertEqual(count("DetailsToggle"), 1, "The closed inspector adds no second Details")
        XCTAssertEqual(count("MoreToolbar"), 1, "The closed inspector adds no second More")
        XCTAssertEqual(count("ShareToolbar"), 1, "The closed inspector adds no second Share")
        XCTAssertFalse(control("FormatToolbar").exists, "Format is out of the default toolbar")
        let page = window.itemPageTitle.frame
        XCTAssertLessThan(newItem.frame.maxX, page.minX, "New Item belongs to the sidebar's foot")
        XCTAssertLessThan(newItem.frame.maxX, viewOptions.frame.minX)
        XCTAssertGreaterThan(newItem.frame.minY, details.frame.maxY, "New Item sits at the sidebar's foot, below the toolbar row")
        XCTAssertLessThan(viewOptions.frame.maxX, viewMode.frame.minX, "View Options comes before View As")
        XCTAssertLessThan(viewMode.frame.maxX, share.frame.minX)
        XCTAssertLessThan(share.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, details.frame.minX, "Details is at the far right")
        XCTAssertGreaterThan(more.frame.minX, window.frame.midX)
        XCTAssertEqual(details.frame.midY, more.frame.midY, accuracy: 3)
        capture("List and page toolbars")
    }

    func testShareMoreAndDetailsMoveAboveTheInspectorWhileItIsOpen() {
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        let share = control("ShareToolbar")
        details.click()
        let inspector = window.descendants(matching: .any)["ItemInspectorDetails"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        XCTAssertTrue(details.exists)
        XCTAssertTrue(more.exists)
        XCTAssertTrue(share.exists)
        XCTAssertEqual(count("DetailsToggle"), 1)
        XCTAssertEqual(count("MoreToolbar"), 1)
        XCTAssertEqual(count("ShareToolbar"), 1)
        XCTAssertGreaterThanOrEqual(share.frame.minX, inspector.frame.minX, "Share, More and Details sit above the inspector column")
        XCTAssertLessThan(share.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, details.frame.minX)
        XCTAssertFalse(control("BackToolbar").exists)
        XCTAssertFalse(control("ForwardToolbar").exists)
        capture("Share More and Details above the inspector")
        details.click()
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 3))
        XCTAssertTrue(control("DetailsToggle").exists, "Details returns to the page toolbar")
        XCTAssertEqual(count("DetailsToggle"), 1)
        XCTAssertEqual(count("MoreToolbar"), 1)
        XCTAssertEqual(count("ShareToolbar"), 1)
    }

    func testViewOptionsOffersSortByAndGroupBy() {
        control("ViewOptionsToolbar").click()
        let sortBy = window.menuItems["Sort by"].firstMatch
        let groupBy = window.menuItems["Group by"].firstMatch
        XCTAssertTrue(sortBy.waitForExistence(timeout: 3))
        XCTAssertTrue(groupBy.exists)
        XCTAssertLessThan(sortBy.frame.minY, groupBy.frame.minY)
        XCTAssertFalse(control("IncludeSubtypesToolbar").exists, "Include Subtypes is in the menu, not on the toolbar")
        XCTAssertFalse(window.menuItems["Gallery"].exists, "View As has the views now")
        XCTAssertFalse(window.menuItems["View As"].exists)
        sortBy.hover()
        for title in ["Date Edited", "Date Created", "Title"] {
            XCTAssertTrue(window.menuItems[title].firstMatch.waitForExistence(timeout: 3), "\(title) is in the Sort by submenu")
        }
        capture("View Options menu")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    func testMoreHoldsTheItemActionsInOrder() {
        control("MoreToolbar").click()
        let titles = ["Quick Look", "Open in New Window", "Open Original", "Open in Browser", "Share…", "Remove from Favorites", "Add Tag…",
                      "Change Type…", "Customize Page…", "Version History…", "Add to Collection…", "Add Attachment…",
                      "Page Width", "Show Markdown Source", "Print…", "Export as PDF…", "Delete"]
        var previous = -CGFloat.infinity
        for title in titles {
            let item = window.menuItems[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), title)
            XCTAssertGreaterThan(item.frame.minY, previous, "\(title) follows the item before it")
            previous = item.frame.minY
        }
        let shown = window.menuItems.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
        XCTAssertEqual(shown, titles + ["Standard", "Full Width"], "the menu holds these actions, Page Width's two choices last, and no others")
        capture("More menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testANewItemHasTheItemActionsOfAnyOther() {
        window.quickAdd(type: "Note", title: "Toolbar item")
        XCTAssertTrue(window.itemPageTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(control("DetailsToggle").isEnabled)
        XCTAssertTrue(control("ShareToolbar").isEnabled)
        XCTAssertTrue(control("MoreToolbar").isEnabled)
    }

    func testMovedAttachmentAndFormattingActionsStillWork() {
        let page = window.webViews.firstMatch
        let editor = app.itemPageBody
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
        XCTAssertTrue(app.menuBars.menuItems["as List"].exists)
        XCTAssertTrue(app.menuBars.menuItems["as Gallery"].exists)
        XCTAssertTrue(app.menuBars.menuItems["as Table"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Back"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Forward"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuBars.menuItems["Print…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testCommandOneAndTwoSwitchBetweenTheListAndTheGallery() {
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["ItemGallery"].waitForExistence(timeout: 3))
        let viewOptions = control("ViewOptionsToolbar")
        let details = control("DetailsToggle")
        let more = control("MoreToolbar")
        let share = control("ShareToolbar")
        let newItem = control("SidebarNew")
        let viewMode = control("ViewModeMenu")
        XCTAssertTrue(viewMode.exists, "View As stays reachable in the gallery")
        XCTAssertTrue(viewOptions.exists, "View Options stays reachable in the gallery")
        XCTAssertTrue(newItem.exists, "New stays reachable in the gallery, from the sidebar")
        XCTAssertTrue(details.exists, "the card selected in the list is still selected, so item actions have something to act on")
        XCTAssertTrue(share.exists)
        XCTAssertLessThan(newItem.frame.maxX, viewMode.frame.minX, "New Item stays at the sidebar's foot")
        let search = window.toolbars.buttons["Search"].firstMatch
        XCTAssertTrue(search.exists)
        XCTAssertLessThan(search.frame.maxX, viewOptions.frame.minX, "Search leads the trailing controls")
        XCTAssertLessThan(viewOptions.frame.maxX, viewMode.frame.minX)
        XCTAssertLessThan(viewMode.frame.maxX, share.frame.minX)
        XCTAssertLessThan(share.frame.maxX, more.frame.minX)
        XCTAssertLessThan(more.frame.maxX, details.frame.minX, "Details is at the far right")
        // ⌘2 leaves the keyboard where it was, so the grid is given it before Escape clears the selection.
        window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "GalleryItem-", "Selected")).firstMatch.click()
        app.typeKey(.escape, modifierFlags: [])
        let cleared = expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: details)
        wait(for: [cleared], timeout: 3)
        for action in [details, share, more] {
            XCTAssertTrue(action.exists, "item actions stay in place when selection clears")
            XCTAssertFalse(action.isEnabled)
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(window.descendants(matching: .any)["ItemGallery"].waitForNonExistence(timeout: 3))
    }

    func testViewAsShowsTheTableWithItsOwnFilterAndViewOptions() {
        show("as Table")
        let table = control("ItemTable")
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        XCTAssertFalse(window.outlines["NoteList"].exists, "the table spans the window")
        XCTAssertFalse(window.webViews.firstMatch.exists)
        let filter = control("ItemTableFilter")
        XCTAssertTrue(filter.exists, "Filter is on the toolbar")
        XCTAssertLessThan(filter.frame.maxX, control("ViewOptionsToolbar").frame.minX, "Filter sits with Search, before View Options")
        XCTAssertLessThan(control("ViewOptionsToolbar").frame.maxX, control("ViewModeMenu").frame.minX)
        control("ViewOptionsToolbar").click()
        for title in ["Sort by", "Group by", "Columns"] {
            XCTAssertTrue(window.menuItems[title].firstMatch.waitForExistence(timeout: 3), title)
        }
        capture("Table View Options menu")
        app.typeKey(.escape, modifierFlags: [])
        show("as Gallery")
        XCTAssertTrue(control("ItemGallery").waitForExistence(timeout: 3))
        XCTAssertTrue(table.waitForNonExistence(timeout: 3))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        show("as List")
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
