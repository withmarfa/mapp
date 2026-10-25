import XCTest

@MainActor
final class ItemJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleLibrary"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    override func tearDown() { app.terminate() }

    func testCreateRelateEditAndReopen() {
        create(type: "Project", title: "Interface Test Project")
        let details = app.descendants(matching: .any)["DetailsToggle"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.click()
        // Description is a field of the sample's Project type; the inspector offers only what the type declares.
        let addProperty = app.descendants(matching: .any)["ItemInspectorAddProperty"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 3))
        addProperty.click()
        app.menuItems.matching(NSPredicate(format: "identifier == %@ OR title == %@", "ItemInspectorAdd.description", "Description")).firstMatch.click()
        let description = app.descendants(matching: .any)["ItemProperty.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.typeText("Saved through the native inspector")
        app.typeKey(.tab, modifierFlags: [])
        details.click()

        create(type: "Task", title: "Interface Test Task")
        details.click()
        let addRelationship = app.descendants(matching: .any)["RelationshipAddMenu"]
        XCTAssertTrue(addRelationship.waitForExistence(timeout: 3))
        addRelationship.click()
        let parentEdit = app.menuItems.matching(NSPredicate(format: "identifier == %@ OR title == %@", "RelationshipAdd.child-of", "Parent")).firstMatch
        XCTAssertTrue(parentEdit.waitForExistence(timeout: 3))
        parentEdit.click()
        let search = app.textFields["RelationshipSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("Interface Test Project")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipCandidate.'")).firstMatch.click()
        app.buttons["RelationshipSave"].click()
        details.click()
        let editor = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("A document written through the existing editor.")
        let typedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: editor)
        wait(for: [typedBody], timeout: 5)

        reopen("Interface Test Task")
        let reopened = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        details.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipTarget.' AND label CONTAINS %@", "Interface Test Project")).firstMatch.waitForExistence(timeout: 3))
        reopen("Interface Test Project")
        let savedDescription = app.descendants(matching: .any)["ItemProperty.description"]
        XCTAssertTrue(savedDescription.waitForExistence(timeout: 3))
        XCTAssertEqual(savedDescription.value as? String, "Saved through the native inspector")
    }

    func testANewItemOpensInThePageAndHeaderEditsSurviveReopening() {
        app.buttons["NewItemToolbar"].click()
        app.menuItems["Task"].click()
        let pageTitle = app.itemPageTitle
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 3))
        app.typeText("Body Focus Draft")
        app.typeKey(.return, modifierFlags: [])
        let editor = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Created by starting the document body.")
        let typedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created by starting the document body."), evaluatedWith: editor)
        wait(for: [typedBody], timeout: 5)

        let title = app.itemPageTitle
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Body Focus Saved Task")
        title.typeKey(.return, modifierFlags: [])
        let row = app.outlines["NoteList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Body Focus Saved Task")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let status = app.itemStatusPin
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.click()
        app.menuItems["Completed"].click()
        app.descendants(matching: .any)["DetailsToggle"].click()
        let inspectorStatus = app.descendants(matching: .any)["ItemProperty.status"]
        XCTAssertTrue(inspectorStatus.waitForExistence(timeout: 3))
        XCTAssertTrue(inspectorStatus.label.contains("Completed") || inspectorStatus.value as? String == "Completed")
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Item page with pins and details"
        attachment.lifetime = .keepAlways
        add(attachment)
        reopen("Body Focus Saved Task")
        let reopened = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created by starting the document body."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        if !inspectorStatus.exists { app.descendants(matching: .any)["DetailsToggle"].click() }
        XCTAssertTrue(inspectorStatus.waitForExistence(timeout: 3))
        XCTAssertTrue(inspectorStatus.label.contains("Completed") || inspectorStatus.value as? String == "Completed")
    }

    /// Leaves the item for another and comes back, so the page reads it again from the library. The sample
    /// library lives only as long as the app, so a relaunch would find none of it.
    private func reopen(_ title: String) {
        let rows = app.outlines["NoteList"].staticTexts
        let other = rows.matching(NSPredicate(format: "NOT (value BEGINSWITH %@)", title)).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.click()
        let row = rows.matching(NSPredicate(format: "value BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
    }

    private func create(type: String, title: String) {
        app.buttons["NewItemToolbar"].click()
        app.menuItems[type].click()
        XCTAssertTrue(app.itemPageTitle.waitForExistence(timeout: 3))
        app.typeText(title)
        app.typeKey(.return, modifierFlags: [])
    }
}
