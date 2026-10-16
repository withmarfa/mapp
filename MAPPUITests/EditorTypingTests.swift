import XCTest

/// Types into the real page with the real keyboard: the slash menu, Link to Note, note suggestions after `[[`, the
/// table shortcut, moving a block, and quotes that stay as typed. This class holds what the suites share.
@MainActor
class EditorTypingCase: XCTestCase {
    var app: XCUIApplication!
    /// Defaults the app starts with, for a test that must not depend on the person's own settings.
    var extraLaunchArguments: [String] { [] }
    var window: XCUIElement { app.windows.firstMatch }
    var page: XCUIElement { window.webViews.firstMatch }
    var editor: XCUIElement { page.textViews.firstMatch }
    var text: String { editor.value as? String ?? "" }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"] + extraLaunchArguments
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        beginNewItem(title: "Typing test")
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func beginNewItem(title: String) {
        app.typeKey("n", modifierFlags: .command)
        let field = window.textFields["NewItemTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText(title)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
    }

    func waitForText(_ predicate: String, _ argument: String, timeout: TimeInterval = 4) -> Bool {
        let expectation = expectation(for: NSPredicate(format: "value \(predicate) %@", argument), evaluatedWith: editor)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// A row of the page's own menu, which shows beside the caret while it is open.
    func menuRow(_ name: String) -> XCUIElement {
        page.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@ OR title == %@", name, name, name)).firstMatch
    }
}

@MainActor
final class EditorTypingTests: EditorTypingCase {
    func testTheSlashMenuListsBlocksInTheAppsWordsAndMakesATable() {
        app.typeText("/")
        for name in ["Heading 1", "Bulleted List", "Checklist", "Code Block", "Table", "Callout", "Diagram", "Link to Note"] {
            XCTAssertTrue(menuRow(name).waitForExistence(timeout: 3), name)
        }
        app.typeText("tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(page.tables.firstMatch.waitForExistence(timeout: 3), "the Table command made a table")
    }

    func testTypingARowAndPressingReturnMakesATable() {
        app.typeText("| Name | Date |")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(page.tables.firstMatch.waitForExistence(timeout: 3))
    }

    func testLinkToNoteAsksWhichNoteAndWritesTheLink() {
        app.typeText("/link")
        XCTAssertTrue(menuRow("Link to Note").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        let field = app.sheets.firstMatch.textFields["NoteLinkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "a sheet asks which note")
        field.typeText("bike")
        XCTAssertTrue(app.sheets.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'NoteLinkRow.'")).firstMatch.waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForText("CONTAINS", "Bike service"), "the link to the note is on the line: \(text)")
        XCTAssertFalse(text.contains("/link"))
        app.typeText(" and then more")
        XCTAssertTrue(waitForText("CONTAINS", "and then more"), "typing carries on after the link")
    }

    func testLinkToNoteCancelledKeepsTheLineAsTyped() {
        app.typeText("/link")
        XCTAssertTrue(menuRow("Link to Note").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.textFields["NoteLinkField"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForText("CONTAINS", "/link"))
        app.typeText("!")
        XCTAssertTrue(waitForText("CONTAINS", "/link!"), "the page has the keyboard back")
    }

    func testDoubleBracketsOfferTheLibrarysNotes() {
        app.typeText("See [[bike")
        XCTAssertTrue(menuRow("Bike service").waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForText("CONTAINS", "See Bike service"), text)
        XCTAssertFalse(text.contains("[["))
        app.typeText(" and more")
        XCTAssertTrue(waitForText("CONTAINS", "Bike service and more"), "typing carries on after the link: \(text)")
    }

    func testOptionUpAndOptionDownMoveTheBlock() {
        app.typeText("first")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("second")
        app.typeKey(.upArrow, modifierFlags: .option)
        XCTAssertTrue(waitForText("BEGINSWITH", "second"), text)
        app.typeKey(.downArrow, modifierFlags: .option)
        XCTAssertTrue(waitForText("BEGINSWITH", "first"), text)
    }
}

/// InkKit's smart punctuation is off. The system's own substitution, which a person sets in Keyboard settings and
/// WebKit applies to any text field, is turned off for this launch, so the test shows what the page itself adds.
@MainActor
final class EditorPunctuationTests: EditorTypingCase {
    override var extraLaunchArguments: [String] {
        [
            "-NSAutomaticQuoteSubstitutionEnabled", "NO", "-NSAutomaticDashSubstitutionEnabled", "NO",
            "-WebAutomaticQuoteSubstitutionEnabled", "NO", "-WebAutomaticDashSubstitutionEnabled", "NO",
        ]
    }

    func testThePageAddsNoCurlyQuotesOrDashes() {
        app.typeText("\"quoted\" it's -- done")
        XCTAssertTrue(waitForText("CONTAINS", "\"quoted\" it's -- done"), text)
    }
}
