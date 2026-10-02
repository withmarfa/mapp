import XCTest

@MainActor
final class ItemJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testCreateRelateEditAndReopen() {
        create(type: "Project", title: "Interface Test Project")
        create(type: "Task", title: "Interface Test Task")
        let details = app.buttons["DetailsToggle"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.click()
        let parentEdit = app.buttons["RelationshipEdit.child-of"]
        XCTAssertTrue(parentEdit.waitForExistence(timeout: 3))
        parentEdit.click()
        let search = app.textFields["RelationshipSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("Interface Test Project")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipCandidate.'")).firstMatch.click()
        app.buttons["RelationshipSave"].click()
        let description = app.textFields["ItemProperty.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.click()
        description.typeText("Saved through the native inspector")
        app.typeKey(.tab, modifierFlags: [])
        details.click()
        let editor = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("A document written through the existing editor.")
        app.terminate()
        app.launchArguments.append("-MAPPKeepSampleFolder")
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let row = app.outlines["NoteList"].staticTexts["Interface Test Task"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.webViews.firstMatch.textViews.firstMatch.waitForExistence(timeout: 3))
        let reopened = app.webViews.firstMatch.textViews.firstMatch
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        app.buttons["DetailsToggle"].click()
        let savedDescription = app.textFields["ItemProperty.description"]
        XCTAssertTrue(savedDescription.waitForExistence(timeout: 3))
        XCTAssertEqual(savedDescription.value as? String, "Saved through the native inspector")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipTarget.' AND label CONTAINS %@", "Interface Test Project")).firstMatch.exists)
    }

    private func create(type: String, title: String) {
        app.typeKey("n", modifierFlags: [.command, .control])
        let typePicker = app.popUpButtons["NewItemType"]
        XCTAssertTrue(typePicker.waitForExistence(timeout: 3))
        typePicker.click()
        app.menuItems[type].click()
        let field = app.textFields["NewItemTitle"]
        field.click()
        field.typeText(title)
        app.buttons["NewItemCreate"].click()
        XCTAssertTrue(app.buttons["NewItemCreate"].waitForNonExistence(timeout: 3))
    }
}
