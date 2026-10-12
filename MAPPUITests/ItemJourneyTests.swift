import AppKit
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
        let parentEdit = app.buttons["RelationshipAdd.child-of"]
        XCTAssertTrue(parentEdit.waitForExistence(timeout: 3))
        parentEdit.click()
        let search = app.textFields["RelationshipSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("Interface Test Project")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipCandidate.'")).firstMatch.click()
        app.buttons["RelationshipSave"].click()
        let description = app.descendants(matching: .any)["ItemProperty.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.click()
        description.typeText("Saved through the native inspector")
        app.typeKey(.tab, modifierFlags: [])
        details.click()
        let editor = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("A document written through the existing editor.")
        let typedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: editor)
        wait(for: [typedBody], timeout: 5)
        app.terminate()
        app.launchArguments.append("-MAPPKeepSampleFolder")
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let row = app.outlines["NoteList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Interface Test Task")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.webViews.firstMatch.textViews.firstMatch.waitForExistence(timeout: 3))
        let reopened = app.webViews.firstMatch.textViews.firstMatch
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "A document written through the existing editor."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        app.buttons["DetailsToggle"].click()
        let savedDescription = app.descendants(matching: .any)["ItemProperty.description"]
        XCTAssertTrue(savedDescription.waitForExistence(timeout: 3))
        XCTAssertEqual(savedDescription.value as? String, "Saved through the native inspector")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'RelationshipTarget.' AND label CONTAINS %@", "Interface Test Project")).firstMatch.exists)
    }

    func testBodyFocusCreatesItemAndHeaderEditsSurviveReopening() {
        app.typeKey("n", modifierFlags: .command)
        let type = app.descendants(matching: .any)["NewItemType"]
        XCTAssertTrue(type.waitForExistence(timeout: 3))
        type.click()
        app.menuItems["Task"].click()
        let draftTitle = app.textFields["NewItemTitle"]
        draftTitle.click()
        draftTitle.typeText("Body Focus Draft")
        let body = app.buttons["NewItemBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        body.click()
        XCTAssertTrue(draftTitle.waitForNonExistence(timeout: 3))
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
        let status = app.itemStatusChip
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.click()
        app.menuItems["Completed"].click()
        app.buttons["DetailsToggle"].click()
        let inspectorStatus = app.popUpButtons["ItemProperty.status"]
        XCTAssertTrue(inspectorStatus.waitForExistence(timeout: 3))
        XCTAssertEqual(inspectorStatus.value as? String, "Completed")
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Item page with shared chips and details"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        app.launchArguments.append("-MAPPKeepSampleFolder")
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let reopened = app.webViews.firstMatch.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        let savedBody = expectation(for: NSPredicate(format: "value CONTAINS %@", "Created by starting the document body."), evaluatedWith: reopened)
        wait(for: [savedBody], timeout: 5)
        if !inspectorStatus.exists { app.buttons["DetailsToggle"].click() }
        XCTAssertTrue(inspectorStatus.waitForExistence(timeout: 3))
        XCTAssertEqual(inspectorStatus.value as? String, "Completed")
    }

    func testImportPhotoAndShowNativeViewer() {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "MAPP/PreviewAssets/item-preview-photo.png")
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Import Files…"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source.path, forType: .string)
        app.typeKey("v", modifierFlags: [.command])
        app.typeKey(.return, modifierFlags: [])
        let open = app.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.click()
        XCTAssertTrue(app.buttons["Zoom In"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["item-preview-photo.png"].exists)
    }

    private func create(type: String, title: String) {
        app.typeKey("n", modifierFlags: .command)
        let typePicker = app.descendants(matching: .any)["NewItemType"]
        XCTAssertTrue(typePicker.waitForExistence(timeout: 3))
        typePicker.click()
        app.menuItems[type].click()
        let field = app.textFields["NewItemTitle"]
        field.click()
        field.typeText(title)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }
}
