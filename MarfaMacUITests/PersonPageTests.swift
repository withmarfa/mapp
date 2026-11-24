import XCTest

nonisolated final class PersonPageTests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample(flags: ["-MarfaMacCollectionSample"])
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws { app.terminate() }

    /// The header of a person's page, with the inspector open at the test window's size, keeps its title and contact
    /// lines readable: each is wider than a few characters, not set one character to a line.
    @MainActor func testPersonHeaderStaysReadableBesideTheInspector() {
        // The sidebar lists a few types and folds the rest under Show More.
        let sidebar = app.outlines["Sidebar"]
        let person = sidebar.descendants(matching: .any).matching(identifier: "SidebarType-core.entity.person").element(boundBy: 0)
        if !person.exists { sidebar.descendants(matching: .any)["SidebarShowMore"].click() }
        person.click()
        let row = app.outlines["ItemList"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Ruth Okonjo")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let title = app.itemPageTitle
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        capture("Person page, inspector closed")
        app.descendants(matching: .any)["DetailsToggle"].click()
        capture("Person page, inspector open")
        let page = app.webViews.firstMatch
        XCTAssertGreaterThan(title.frame.width, 120, "The title must not collapse beside the inspector.")
        let email = page.staticTexts["ruth@example.com"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(email.frame.width, 80, "The email must not be set one character to a line.")
        XCTAssertLessThan(email.frame.height, 40)
    }

    @MainActor private func capture(_ name: String) {
        // AppKit's inspector animation continues after the accessibility action returns.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
