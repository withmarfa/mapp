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
