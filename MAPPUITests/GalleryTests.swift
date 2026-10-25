import AppKit
import XCTest

@MainActor
final class GalleryTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var gallery: XCUIElement { window.descendants(matching: .any).matching(identifier: "ItemGallery").element(boundBy: 0) }
    private var list: XCUIElement { window.outlines["NoteList"] }
    private var sidebar: XCUIElement { window.outlines["Sidebar"] }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws { app.terminate() }

    private func choose(_ mode: String) {
        app.menuBars.menuBarItems["View"].click()
        let option = app.menuBars.menuItems["View as \(mode)"]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.click()
    }

    private func card(_ title: String) -> XCUIElement {
        window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "GalleryItem-", title)).element(boundBy: 0)
    }

    func testGalleryReplacesTheListAndEditorWithAnAdaptiveGrid() throws {
        choose("Gallery")
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        XCTAssertFalse(list.exists)
        XCTAssertFalse(window.webViews.firstMatch.exists)
        XCTAssertTrue(sidebar.exists)
        let first = card("Kitchen quotes")
        let second = card("Reading list")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 4)
        XCTAssertGreaterThan(second.frame.minX, first.frame.maxX)
        XCTAssertGreaterThan(gallery.frame.width, window.frame.width / 2)
        XCTAssertEqual(card("Garden ideas").frame.width, first.frame.width, accuracy: 2)
        XCTAssertEqual(card("Garden ideas").frame.height, first.frame.height, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "GalleryGrid"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let frame = window.frame
        let sidebarFrame = sidebar.frame
        let galleryFrame = gallery.frame
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            // SwiftUI column groups and native toolbar menus have the same audit exclusions as the list workspace.
            if !frame.intersects(element.frame) || element.elementType == .helpTag { return true }
            switch issue.auditType {
            case .parentChild: return true
            case .sufficientElementDescription: return element.elementType == .group && element.label.isEmpty
            case .contrast:
                let isNativeTitle = element.frame.maxY <= galleryFrame.minY && element.frame.minX >= sidebarFrame.maxX
                return sidebarFrame.contains(element.frame) || isNativeTitle
            case .action: return element.elementType == .menuButton || element.elementType == .popUpButton
            default: return false
            }
        }
    }

    func testOpeningReturningAndListViewKeepTheNoteAndUndo() {
        choose("Gallery")
        let target = card("Kitchen quotes")
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.click()
        XCTAssertEqual(target.value as? String, "Selected")
        let neighbour = card("Reading list")
        let gap = gallery.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: (target.frame.maxX + neighbour.frame.minX) / 2 - gallery.frame.minX, dy: target.frame.midY - gallery.frame.minY))
        gap.click()
        XCTAssertNotEqual(target.value as? String, "Selected", "a click between the cards clears the selection")
        target.doubleClick()
        let editor = window.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let reading = editor.value as? String
        app.typeKey("q", modifierFlags: [])
        XCTAssertEqual(editor.value as? String, reading)
        editor.click()
        app.typeKey(.end, modifierFlags: .command)
        app.typeText("\nGallery edit retained")
        window.buttons["BackToGallery"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        choose("List")
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let text = expectation(for: NSPredicate(format: "value CONTAINS %@", "Gallery edit retained"), evaluatedWith: editor)
        wait(for: [text], timeout: 3)
        editor.click()
        app.typeKey("z", modifierFlags: .command)
        let undone = expectation(for: NSPredicate(format: "NOT (value CONTAINS %@)", "Gallery edit retained"), evaluatedWith: editor)
        wait(for: [undone], timeout: 3)
    }

    func testDeletingAnOpenedItemKeepsTheGallerySelectionCurrent() {
        choose("Gallery")
        let first = card("Kitchen quotes")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.doubleClick()
        XCTAssertTrue(window.buttons["BackToGallery"].waitForExistence(timeout: 3))
        window.descendants(matching: .any).matching(identifier: "MoreToolbar").firstMatch.click()
        window.menuItems["Delete"].firstMatch.click()
        window.buttons["BackToGallery"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        XCTAssertFalse(first.exists)
        XCTAssertEqual(card("Reading list").value as? String, "Selected")
        window.descendants(matching: .any).matching(identifier: "MoreToolbar").firstMatch.click()
        XCTAssertFalse(window.menuItems["Delete Immediately…"].exists)
        XCTAssertFalse(window.menuItems["Recover"].exists)
        XCTAssertTrue(window.menuItems["Delete"].firstMatch.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
    }

    func testAnOpenedGalleryNoteKeepsItsCompactTitleAndTrailingActions() {
        choose("Gallery")
        let target = card("Kitchen quotes")
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.doubleClick()
        let page = window.webViews.firstMatch
        let editor = page.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\n\n" + Array(repeating: "A paragraph for the gallery scrolling check.", count: 45).joined(separator: "\n\n"), forType: .string)
        app.typeKey("v", modifierFlags: .command)
        for _ in 0..<8 { page.scroll(byDeltaX: 0, deltaY: -100) }
        XCTAssertTrue(window.staticTexts["ScrolledItemTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(window.buttons["BackToGallery"].exists)
        let more = window.descendants(matching: .any).matching(identifier: "MoreToolbar").firstMatch
        XCTAssertTrue(more.exists)
        XCTAssertGreaterThan(more.frame.minX, window.frame.midX)
        window.buttons["BackToGallery"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        XCTAssertFalse(window.staticTexts["ScrolledItemTitle"].exists)
    }

    func testGallerySearchAndEmptyResultsUseTheExistingSearch() {
        choose("Gallery")
        XCTAssertTrue(card("Kitchen quotes").waitForExistence(timeout: 3))
        card("Kitchen quotes").doubleClick()
        XCTAssertTrue(window.buttons["BackToGallery"].waitForExistence(timeout: 3))
        app.typeKey("f", modifierFlags: [.command, .option])
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        let search = window.searchFields["ColumnSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Lisbon")
        XCTAssertTrue(card("Trip to Lisbon").waitForExistence(timeout: 3))
        XCTAssertTrue(card("Kitchen quotes").waitForNonExistence(timeout: 3))
        search.typeKey("a", modifierFlags: .command)
        search.typeText("no-matching-gallery-item")
        XCTAssertTrue(card("Trip to Lisbon").waitForNonExistence(timeout: 3))
        XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "GalleryEmptySearch").firstMatch.waitForExistence(timeout: 3))
        window.buttons["CloseColumnSearch"].click()
        XCTAssertTrue(card("Kitchen quotes").waitForExistence(timeout: 3))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(card("Kitchen quotes").value as? String, "Selected")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(card("Reading list").value as? String, "Selected")
    }

    func testKeyboardSelectionDeletionAndUndoWorkInGallery() {
        choose("Gallery")
        let first = card("Kitchen quotes")
        let second = card("Reading list")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.click()
        app.typeKey(.rightArrow, modifierFlags: .shift)
        XCTAssertEqual(first.value as? String, "Selected")
        XCTAssertEqual(second.value as? String, "Selected")
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(first.waitForNonExistence(timeout: 3))
        XCTAssertTrue(second.waitForNonExistence(timeout: 3))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        first.click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(window.buttons["BackToGallery"].waitForExistence(timeout: 3))
    }

    func testLeavingSettingsAnotherPlaceAndHiddenSidebarReturnToGallery() throws {
        choose("Gallery")
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        let splitter = try XCTUnwrap(window.splitters.allElementsBoundByIndex.min { abs($0.frame.midX - sidebar.frame.maxX) < abs($1.frame.midX - sidebar.frame.maxX) })
        let edge = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        edge.click(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: 45, dy: 0)))
        let width = sidebar.frame.width
        app.typeKey(",", modifierFlags: .command)
        let settings = window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertFalse(gallery.exists, "Settings shows its pages in place of the gallery")
        sidebar.staticTexts["Items"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        XCTAssertEqual(sidebar.frame.width, width, accuracy: 3)
        sidebar.staticTexts["Inbox"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        sidebar.staticTexts["Items"].click()
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForNonExistence(timeout: 3))
        for _ in 0..<3 {
            choose("List")
            XCTAssertTrue(list.waitForExistence(timeout: 3))
            XCTAssertFalse(sidebar.exists)
            choose("Gallery")
            XCTAssertTrue(gallery.waitForExistence(timeout: 3))
            XCTAssertFalse(sidebar.exists)
        }
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
        XCTAssertEqual(sidebar.frame.width, width, accuracy: 3)
    }

    func testANewItemMadeInTheGalleryOpensInThePageAndAppearsAsACardOnReturning() {
        choose("Gallery")
        window.buttons["NewItemToolbar"].click()
        window.menuItems["Note"].click()
        let title = window.itemPageTitle
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        app.typeText("Gallery item")
        app.typeKey(.return, modifierFlags: [])
        let editor = window.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Created from the gallery")
        window.buttons["BackToGallery"].click()
        XCTAssertTrue(card("Gallery item").waitForExistence(timeout: 3))
        card("Gallery item").doubleClick()
        let content = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created from the gallery"), evaluatedWith: editor)
        wait(for: [content], timeout: 3)
    }

    func testPaletteOffersViewModesAndHidesEditorCommandsInGallery() {
        let editor = window.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.typeKey("k", modifierFlags: .command)
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Print")
        XCTAssertTrue(window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Print…")).firstMatch.waitForExistence(timeout: 3))
        field.typeKey(.escape, modifierFlags: [])
        choose("Gallery")
        card("Reading list").click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Print")
        XCTAssertFalse(window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Print…")).firstMatch.exists)
        field.typeKey("a", modifierFlags: .command)
        field.typeText("View as List")
        XCTAssertTrue(window.buttons["View as List"].waitForExistence(timeout: 3))
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(list.waitForExistence(timeout: 3))
    }
}
