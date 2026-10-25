import XCTest

/// The Marfa server section of Settings > Library, starting as a first launch does. The sample's app has a host of its own, on a
/// Keychain held in memory, so nothing here reaches the person's saved server or keys; the steps used need no server, since an address that
/// is no server is refused before anything is asked of the network.
@MainActor
final class MarfaSettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var settings: XCUIElement { window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0) }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleLibrary", "-MAPPSampleUnconfigured"]
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
    private var key: XCUIElement { window.secureTextFields["MarfaKey"] }
    private var connect: XCUIElement { window.buttons["MarfaConnect"] }

    func testTheLibraryPageAsksForAnAddressAndAKeyThePersonPastes() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertTrue(key.exists, "the key is typed into a secure field, so it is never shown")
        XCTAssertTrue(connect.exists)
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "there is nothing to disconnect from")
        XCTAssertTrue(window.toolbars.staticTexts["Library"].waitForExistence(timeout: 3))
        attachScreenshot("SettingsMarfaDisconnected")
    }

    func testConnectWaitsForBothAnAddressAndAKey() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertFalse(connect.isEnabled)
        address.click()
        address.typeText("https://marfa.example.com")
        XCTAssertFalse(connect.isEnabled, "a key is needed too")
        key.click()
        key.typeText("pasted-key")
        XCTAssertTrue(connect.isEnabled)
    }

    func testAnAddressThatIsNoServerIsToldInPlainWords() {
        openLibraryPage()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.click()
        address.typeText("marfa.example")
        key.click()
        key.typeText("pasted-key")
        connect.click()
        let notice = window.descendants(matching: .any)["MarfaNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(notice.label.contains("Check the Address"), "the notice reads as one element, with its title in its label")
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "nothing was connected")
        attachScreenshot("SettingsMarfaNotAServer")
    }

    func testWithNoServerTheWindowAsksToConnectAndShowsNoSync() {
        let welcome = window.descendants(matching: .any)["Welcome"].firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 3))
        XCTAssertFalse(window.outlines["Sidebar"].exists)
        XCTAssertFalse(window.buttons["SyncStatus"].exists)
        XCTAssertFalse(window.descendants(matching: .any)["SyncDetails"].exists)
        window.buttons["WelcomeConnect"].click()
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
