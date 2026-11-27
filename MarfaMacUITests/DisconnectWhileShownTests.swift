import XCTest

/// Signing out of a live library from Settings while the main window shows it, with the details pane open. The
/// window must stay open and ask for a server again, not crash on a library that is no longer there.
///
/// Needs a throwaway server: it runs only with `MARFA_MAC_LEAVING_UI` set, and takes the server from `MARFA_API_URL` and
/// `MARFA_API_KEY` (given to the test runner as `TEST_RUNNER_MARFA_API_URL` and `TEST_RUNNER_MARFA_API_KEY`). The app
/// keeps the key in memory and its copy in a temporary folder, so nothing reaches the person's data.
nonisolated final class DisconnectWhileShownTests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MARFA_MAC_LEAVING_UI"] != nil, "MARFA_MAC_LEAVING_UI is not set")
        let address = try XCTUnwrap(environment["MARFA_API_URL"], "A test server's address is needed (MARFA_API_URL)")
        let key = try XCTUnwrap(environment["MARFA_API_KEY"], "A key for the test server is needed (MARFA_API_KEY)")
        let host = URL(string: address)?.host()
        try XCTSkipUnless(host == "127.0.0.1" || host == "localhost", "Refused: only a server on this Mac")
        app = XCUIApplication.sample()
        app.launchEnvironment["MARFA_MAC_TEST_MARFA_URL"] = address
        app.launchEnvironment["MARFA_MAC_TEST_MARFA_KEY"] = key
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["SidebarNew"].waitForExistence(timeout: 60), "the library showed")
    }

    @MainActor override func tearDown() async throws {
        app?.terminate()
    }

    @MainActor private func signOutFromSettings() {
        app.typeKey(",", modifierFlags: .command)
        let sidebar = app.descendants(matching: .any).matching(identifier: "SettingsSidebar").element(boundBy: 0)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "SettingsPage-account").element(boundBy: 0).click()
        let signOut = app.buttons["AccountSignOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        let confirm = app.sheets.buttons["Sign Out"]
        // A system prompt can take the first click, which the test's interruption handling answers; the question is then asked again.
        for _ in 0..<3 where !confirm.exists {
            signOut.click()
            if confirm.waitForExistence(timeout: 4) { break }
        }
        XCTAssertTrue(confirm.exists, "the question was asked")
        confirm.click()
    }

    /// Once the library is gone the main window asks for a server again, and Connection offers to sign in.
    @MainActor private func assertLeft(_ extra: String) {
        XCTAssertTrue(app.buttons["MarfaOpenConnect"].waitForExistence(timeout: 20), "the window offers to sign in again \(extra)")
        XCTAssertNotEqual(app.state, .notRunning, "the app is still running")
        XCTAssertFalse(app.buttons["MarfaDisconnect"].exists, "there is no library to disconnect from")
        XCTAssertFalse(app.descendants(matching: .any)["SidebarNew"].exists, "the library is gone from the window")
    }

    @MainActor func testSigningOutWhileTheWindowShowsTheLibraryLeavesTheWindowOpen() {
        signOutFromSettings()
        assertLeft("")
    }

    @MainActor func testSigningOutWithTheDetailsPaneOpenLeavesTheWindowOpen() {
        app.typeKey("i", modifierFlags: [.command, .option])
        signOutFromSettings()
        assertLeft("with the details open")
    }
}
