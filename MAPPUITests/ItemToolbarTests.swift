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
        XCTAssertTrue(window.textFields["ItemPageTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.webViews.firstMatch.textViews.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testToolbarHasOneTrailingGroupAndMenusContainMovedActions() {
        let controls = ["NewItemToolbar", "FormatToolbar", "DetailsToggle", "MoreToolbar"].map(control)
        for element in controls { XCTAssertTrue(element.exists) }
        for pair in zip(controls, controls.dropFirst()) {
            XCTAssertLessThan(pair.0.frame.maxX, pair.1.frame.midX)
            XCTAssertEqual(pair.0.frame.midY, pair.1.frame.midY, accuracy: 3)
        }
        XCTAssertGreaterThan(controls[0].frame.minX, window.frame.midX)
        capture("Single trailing item toolbar")
        control("FormatToolbar").click()
        for title in ["Bulleted List", "Numbered List", "Checklist", "Table"] {
            XCTAssertTrue(window.menuItems[title].exists)
            XCTAssertTrue(window.menuItems[title].isEnabled)
        }
        app.typeKey(.escape, modifierFlags: [])
        control("MoreToolbar").click()
        XCTAssertTrue(window.menuItems["Share…"].waitForExistence(timeout: 3))
        XCTAssertTrue(window.menuItems["Share…"].isEnabled)
        XCTAssertTrue(window.menuItems["Add Attachment…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        control("NewItemToolbar").click()
        XCTAssertTrue(window.textFields["NewItemTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(control("FormatToolbar").isEnabled)
        XCTAssertFalse(control("DetailsToggle").isEnabled)
        control("MoreToolbar").click()
        XCTAssertFalse(window.menuItems["Share…"].isEnabled)
        XCTAssertFalse(window.menuItems["Add Attachment…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testMovedFormattingAndAttachmentActionsStillWork() {
        let page = window.webViews.firstMatch
        let editor = page.textViews.firstMatch
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\nToolbar list check")
        control("FormatToolbar").click()
        window.menuItems["Checklist"].click()
        XCTAssertTrue((editor.value as? String)?.contains("Toolbar list check") == true)
        capture("Checklist inserted through Format")
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeKey(.return, modifierFlags: [])
        editor.typeKey(.return, modifierFlags: [])
        control("FormatToolbar").click()
        window.menuItems["Table"].click()
        XCTAssertTrue(page.tables.firstMatch.waitForExistence(timeout: 3))
        control("MoreToolbar").click()
        window.menuItems["Add Attachment…"].click()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
    }

    private func control(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
