import XCTest

/// The Settings row at the sidebar's foot is sized for the sidebar size chosen in System Settings, so each size is checked.
@MainActor
final class SidebarSizeTests: XCTestCase {
    func testTheSettingsRowFitsTheSidebarFootAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication()
            // Before the sample folder's flag, which takes no value.
            app.launchArguments += ["-NSTableViewDefaultSizeMode", size, "-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
            app.launch()
            let window = app.windows.firstMatch
            XCTAssertTrue(window.outlines["Sidebar"].waitForExistence(timeout: 10))
            let foot = window.descendants(matching: .any).matching(identifier: "SidebarFoot").element(boundBy: 0)
            let settings = foot.staticTexts["Settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            XCTAssertTrue(foot.frame.contains(settings.frame), "the row is cut off at sidebar size \(size)")
            app.terminate()
        }
    }
}
