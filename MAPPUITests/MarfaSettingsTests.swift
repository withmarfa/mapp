import XCTest

/// The Marfa server section of Settings > Library, starting as a first launch does. The sample's app has a host of its own, with
/// sign-ins held in memory, so nothing here reaches the person's saved server or sign-in; the steps used need no server and open no browser,
/// since an address that is no server is refused before anything is asked of the network.
@MainActor
final class MarfaSettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var settings: XCUIElement { window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0) }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.sample(flags: ["-MAPPSampleUnconfigured"])
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func openLibraryPage() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let page = window.descendants(matching: .any).matching(identifier: "SettingsPage-library").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.click()
    }

    private var address: XCUIElement { window.textFields["MarfaAddress"] }
    private var connect: XCUIElement { window.buttons["MarfaConnect"] }
    private var connectWithCode: XCUIElement { window.buttons["MarfaConnectCode"] }

    func testTheLibraryPageAsksForAnAddressAndOffersTwoWaysToSignIn() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertFalse(window.secureTextFields.firstMatch.exists, "no key is typed into the app")
        XCTAssertTrue(connect.exists, "Sign In opens the server's own page")
        XCTAssertTrue(connectWithCode.exists, "Use a Code Instead is for a Mac that cannot open the browser")
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "there is nothing to disconnect from")
        XCTAssertTrue(window.descendants(matching: .any)["SettingsDetail"].staticTexts["Library"].waitForExistence(timeout: 3))
        attachScreenshot("SettingsMarfaDisconnected")
    }

    func testSigningInWaitsForAnAddress() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(connectWithCode.isEnabled)
        address.click()
        address.typeText("https://marfa.example.com")
        XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(connectWithCode.isEnabled)
    }

    func testAnAddressThatIsNoServerIsToldInPlainWords() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.click()
        address.typeText("marfa.example")
        connect.click()
        let notice = window.descendants(matching: .any)["MarfaNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        let noticeText = notice.label + " " + (notice.value as? String ?? "")
        XCTAssertTrue(noticeText.contains("Check the Address"), "the combined notice exposes its title: \(notice.debugDescription)")
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "nothing was connected")
        attachScreenshot("SettingsMarfaNotAServer")
    }

    func testWithNoServerTheWindowAsksToConnectAndShowsNoSync() {
        let welcome = window.descendants(matching: .any)["Welcome"].firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 3))
        XCTAssertFalse(window.outlines["Sidebar"].exists)
        let connect = window.buttons["Connect…"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3), window.debugDescription)
        connect.click()
        XCTAssertTrue(address.waitForExistence(timeout: 3), "Connect opens the page that asks for the server")
        attachScreenshot("WelcomeConnect")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
