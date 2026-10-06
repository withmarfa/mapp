import XCTest

/// The Marfa pane of Settings. The sample folder's app has a host of its own, on a Keychain held in memory, so
/// nothing here reaches the person's saved server or keys; the steps used need no server, since an address that
/// is no server is refused before anything is asked of the network.
@MainActor
final class MarfaSettingsTests: XCTestCase {
    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }
    private var settings: XCUIElement { window.descendants(matching: .any)["SettingsWorkspace"].firstMatch }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func openMarfaPane() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let sidebar = window.outlines["SettingsSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
        let pane = sidebar.descendants(matching: .any).matching(identifier: "SettingsPane-marfa").element(boundBy: 0)
        XCTAssertTrue(pane.waitForExistence(timeout: 3))
        pane.click()
    }

    private var address: XCUIElement { window.textFields["MarfaAddress"] }
    private var key: XCUIElement { window.secureTextFields["MarfaKey"] }
    private var connect: XCUIElement { window.buttons["MarfaConnect"] }

    func testThePaneAsksForAnAddressAndAKeyThePersonPastes() {
        openMarfaPane()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        XCTAssertTrue(key.exists, "the key is typed into a secure field, so it is never shown")
        XCTAssertTrue(connect.exists)
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "there is nothing to disconnect from")
        XCTAssertTrue(window.toolbars.staticTexts["Marfa"].waitForExistence(timeout: 3))
        attachScreenshot("SettingsMarfaDisconnected")
    }

    func testConnectWaitsForBothAnAddressAndAKey() {
        openMarfaPane()
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
        openMarfaPane()
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.click()
        address.typeText("marfa.example")
        key.click()
        key.typeText("pasted-key")
        connect.click()
        let notice = window.descendants(matching: .any)["MarfaNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(window.staticTexts["Check the Address"].exists)
        XCTAssertFalse(window.buttons["MarfaDisconnect"].exists, "nothing was connected")
        attachScreenshot("SettingsMarfaNotAServer")
    }

    func testNothingAboutTheServerShowsInTheWindowWhileTheAppReadsAFolder() {
        XCTAssertTrue(window.outlines["Sidebar"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.buttons["SyncStatus"].exists)
        XCTAssertFalse(window.descendants(matching: .any)["SyncDetails"].exists)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
