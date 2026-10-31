import XCTest

@MainActor
final class QuickLookTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var list: XCUIElement { window.outlines["NoteList"] }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample()
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws { app.terminate() }

    func testSpaceOnASelectedNoteShowsItInQuickLookAndSpaceClosesIt() throws {
        let row = list.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let before = app.windows.count
        list.typeKey(" ", modifierFlags: [])
        // Quick Look is a panel of its own, the app's second window while it shows; its service starts cold, so it can be slow.
        let shown = NSPredicate { _, _ in self.app.windows.count > before }
        wait(for: [expectation(for: shown, evaluatedWith: nil)], timeout: 40)
        app.typeKey(" ", modifierFlags: [])
        let closed = NSPredicate { _, _ in self.app.windows.count == before }
        wait(for: [expectation(for: closed, evaluatedWith: nil)], timeout: 5)
    }
}
