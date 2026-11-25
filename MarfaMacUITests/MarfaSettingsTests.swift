import XCTest

/// The Marfa server section of Settings > Connection, starting as a first launch does. The sample's app has a host of its own, with
/// sign-ins held in memory, so nothing here reaches the person's saved server or sign-in; the steps used need no server and open no browser,
/// since an address that is no server is refused before anything is asked of the network.
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

    @MainActor private func openLibraryPage() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let page = app.descendants(matching: .any).matching(identifier: "SettingsPage-connection").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
    }

    @MainActor private var address: XCUIElement { app.textFields["MarfaAddress"] }
    @MainActor private var connect: XCUIElement { app.buttons["MarfaConnect"] }
    @MainActor private var connectWithCode: XCUIElement { app.buttons["MarfaConnectCode"] }

    @MainActor func testTheLibraryPageAsksForAnAddressAndOffersTwoWaysToSignIn() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "no key is typed into the app")
        XCTAssertTrue(connect.exists, "Sign In opens the server's own page")
        XCTAssertTrue(connectWithCode.exists, "Use a Code Instead is for a Mac that cannot open the browser")
        XCTAssertFalse(app.buttons["MarfaDisconnect"].exists, "there is nothing to disconnect from")
        XCTAssertTrue(app.descendants(matching: .any)["SettingsDetail"].staticTexts["Connect to a Marfa"].waitForExistence(timeout: 3))
        attachScreenshot("SettingsMarfaDisconnected")
    }

    @MainActor func testSigningInWaitsForAnAddress() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(connectWithCode.isEnabled)
        address.click()
        address.typeText("https://marfa.example.com")
        XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(connectWithCode.isEnabled)
    }

    @MainActor func testAnAddressThatIsNoServerIsToldInPlainWords() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.click()
        address.typeText("ftp://marfa.example")
        connect.click()
        let notice = app.descendants(matching: .any)["MarfaNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        let noticeText = notice.label + " " + (notice.value as? String ?? "")
        XCTAssertTrue(noticeText.contains("Check the Address"), "the combined notice exposes its title: \(notice.debugDescription)")
        XCTAssertFalse(app.buttons["MarfaDisconnect"].exists, "nothing was connected")
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
