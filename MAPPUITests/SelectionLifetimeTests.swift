import XCTest

@MainActor
final class SelectionLifetimeTests: XCTestCase {
    func testSelectedOutlineSurvivesWorkspaceReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication.sample()
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        let list = window.outlines["NoteList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let note = list.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Kitchen quotes")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()

        for _ in 0..<3 {
            for (mode, key) in [("Gallery", "2"), ("Table", "3"), ("List", "1")] {
                app.typeKey(key, modifierFlags: .command)
                let content = mode == "List"
                    ? list
                    : window.descendants(matching: .any).matching(identifier: "Item\(mode)").element(boundBy: 0)
                XCTAssertTrue(content.waitForExistence(timeout: 3), "\(mode) survives replacing the selected outline")
                XCTAssertTrue(window.outlines["Sidebar"].exists)
            }
            XCTAssertTrue(note.exists)
            note.click()
        }
    }
}
