import XCTest

/// The places fixed at the sidebar's foot are a list sized to its rows, whose height follows the sidebar size
/// chosen in System Settings, so each size is checked.
@MainActor
final class SidebarSizeTests: XCTestCase {
    func testThePlacesAtTheFootFitAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication()
            // Before the sample folder's flag, which takes no value.
            app.launchArguments += ["-NSTableViewDefaultSizeMode", size, "-ApplePersistenceIgnoreState", "YES", "-MAPPSampleFolder"]
            app.launch()
            let places = app.windows.firstMatch.outlines["SidebarPlaces"]
            XCTAssertTrue(places.waitForExistence(timeout: 10))
            for row in places.outlineRows.allElementsBoundByIndex {
                XCTAssertTrue(places.frame.contains(row.frame), "a row is cut off at sidebar size \(size)")
            }
            XCTAssertEqual(places.outlineRows.count, 2)
            app.terminate()
        }
    }
}
