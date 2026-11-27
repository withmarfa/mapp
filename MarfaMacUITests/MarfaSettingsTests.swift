import XCTest

/// Exercises first-time connection using in-memory sign-ins. Typing a valid address can start an unauthenticated health check.
nonisolated final class MarfaSettingsTests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var settings: XCUIElement { app.descendants(matching: .any).matching(identifier: "SettingsSidebar").element(boundBy: 0) }

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample(flags: ["-MarfaMacSampleUnconfigured"])
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    @MainActor override func tearDown() async throws {
        app.terminate()
    }

    @MainActor private func openConnectionPage() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let page = app.descendants(matching: .any).matching(identifier: "SettingsPage-connection").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
    }

    @MainActor private var address: XCUIElement { app.textFields["MarfaAddress"] }
    @MainActor private var openConnect: XCUIElement { app.buttons["MarfaOpenConnect"] }
    @MainActor private var connect: XCUIElement { app.buttons["MarfaConnect"] }
    @MainActor private var connectWithCode: XCUIElement { app.buttons["MarfaConnectCode"] }

    @MainActor private func openSignInSheet() {
        XCTAssertTrue(openConnect.waitForExistence(timeout: 3))
        openConnect.click()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
    }

    @MainActor func testSignedOutConnectionOpensASheetWithTwoWaysToSignIn() {
        openConnectionPage()
        XCTAssertTrue(app.staticTexts["Not Signed In"].waitForExistence(timeout: 3))
        XCTAssertFalse(address.exists)
        attachScreenshot("SettingsMarfaSignedOut")
        openSignInSheet()
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "no key is typed into the app")
        XCTAssertTrue(connect.exists, "Continue opens the server's own page")
        XCTAssertTrue(connectWithCode.exists, "Sign In with a Code is for a Mac that cannot open the browser")
        XCTAssertFalse(app.buttons["AccountSignOut"].exists, "there is no sign-in to end")
        XCTAssertTrue(app.staticTexts["Connect to a Marfa"].waitForExistence(timeout: 3))
        attachScreenshot("SettingsConnectToMarfa")
        app.buttons["MarfaConnectCancel"].click()
        XCTAssertTrue(address.waitForNonExistence(timeout: 3))
        XCTAssertTrue(openConnect.exists)
    }

    @MainActor func testSigningInWaitsForAnAddress() {
        openConnectionPage()
        openSignInSheet()
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(connectWithCode.isEnabled)
        address.click()
        address.typeText("https")
        address.typeKey(";", modifierFlags: .shift)
        address.typeText("//marfa.example")
        XCTAssertEqual(address.value as? String, "https://marfa.example")
        XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(connectWithCode.isEnabled)
    }

    @MainActor func testAnAddressThatIsNoServerIsToldInPlainWords() {
        openConnectionPage()
        openSignInSheet()
        address.click()
        let invalidAddress = "marfa example"
        address.typeText(invalidAddress)
        XCTAssertEqual(address.value as? String, invalidAddress)
        XCTAssertTrue(connect.isEnabled)
        connect.click()
        XCTAssertTrue(app.staticTexts["Check the Address"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Enter a Marfa server address, such as marfa.example."].exists)
        XCTAssertFalse(app.buttons["AccountSignOut"].exists, "nothing was connected")
        attachScreenshot("SettingsMarfaNotAServer")
    }

    @MainActor func testWithNoServerTheWindowAsksToConnectAndShowsNoSync() {
        let welcome = window.descendants(matching: .any)["Welcome"].firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 3))
        XCTAssertFalse(window.outlines["Sidebar"].exists)
        let connect = window.buttons["Connect…"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3), window.debugDescription)
        connect.click()
        XCTAssertTrue(address.waitForExistence(timeout: 3), "Connect opens the page that asks for the server")
        attachScreenshot("WelcomeConnect")
    }

    @MainActor private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
