import XCTest

/// The last row of the Library section follows the sidebar size chosen in System Settings, so each size is checked.
@MainActor
final class SidebarSizeTests: XCTestCase {
    func testTheLastLibraryRowFitsAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication()
            // Before the sample folder's flag, which takes no value.
            app.launchArguments += ["-NSTableViewDefaultSizeMode", size, "-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
            app.launch()
            let sidebar = app.windows.firstMatch.outlines["Sidebar"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            let deleted = sidebar.staticTexts["Recently Deleted"]
            XCTAssertTrue(deleted.waitForExistence(timeout: 3))
            XCTAssertTrue(sidebar.frame.contains(deleted.frame), "the row is cut off at sidebar size \(size)")
            app.terminate()
        }
    }
}
