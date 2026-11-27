import XCTest

nonisolated final class AccountSignOutTests: XCTestCase {
    @MainActor func testAccountAsksOnceAndEscapeKeepsTheLibraryOpen() {
        continueAfterFailure = false
        let app = XCUIApplication.sample()
        app.launch()
        defer { app.terminate() }

        let library = app.descendants(matching: .any)["SidebarNew"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let account = app.descendants(matching: .any)["SettingsPage-account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.click()

        let signOut = app.buttons["AccountSignOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.click()
        let confirm = app.sheets.buttons["Sign Out"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.buttons.matching(identifier: "Sign Out").count, 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AccountSignOut"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
        XCTAssertTrue(library.exists)

        signOut.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.buttons["MarfaOpenConnect"].waitForExistence(timeout: 10))
        XCTAssertFalse(library.exists)
    }
}
