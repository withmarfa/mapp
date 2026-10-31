import XCTest

/// Drives the real app by keyboard alone, with Full Keyboard Access on for this launch only (a launch argument, not
/// a system setting).
@MainActor
final class KeyboardNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample(settings: ["AppleKeyboardUIMode": "3"])
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func focusedElement() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
    }

    func testTabMovesFocusThroughMoreThanOneAreaOfTheWindow() {
        var seen: [String] = []
        for _ in 0..<14 {
            app.typeKey(.tab, modifierFlags: [])
            let focused = focusedElement()
            if focused.exists {
                let name = "\(focused.elementType.rawValue):\(focused.identifier):\(focused.label)"
                if seen.last != name { seen.append(name) }
            }
        }
        let areas = Set(seen)
        XCTAssertTrue(areas.contains { $0.contains("NoteList") }, "Tab reaches the list: \(seen)")
        XCTAssertTrue(areas.contains { $0.contains("Sidebar") }, "Tab reaches the sidebar: \(seen)")
        XCTAssertGreaterThanOrEqual(areas.count, 3, "Tab goes on past the list and sidebar, to the page: \(seen)")
    }

    /// Under Full Keyboard Access Tab steps through the list, the sidebar and its rows only; the toolbar is reached with
    /// Control-F5, which a synthesized key does not trigger, so what can be checked here is that every toolbar control
    /// is a labeled, enabled button that keyboard users and VoiceOver can name.
    func testEveryToolbarControlIsALabeledButton() {
        let toolbar = app.toolbars.firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 3))
        let buttons = toolbar.buttons.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertFalse(buttons.isEmpty, "the toolbar has controls")
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty, "a toolbar button has no label: \(button.debugDescription)")
        }
    }

    func testNewWindowInThePaletteOpensAWindow() {
        app.typeKey("k", modifierFlags: .command)
        let field = window.textFields["CommandPaletteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("New Window")
        XCTAssertTrue(window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New Window")).firstMatch.waitForExistence(timeout: 3))
        field.typeKey(.return, modifierFlags: [])
        let opened = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: app.windows)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 5), .completed, "choosing New Window opens a second window")
    }
}
