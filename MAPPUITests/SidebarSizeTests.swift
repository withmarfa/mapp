import XCTest

/// The sidebar's foot's buttons stay reachable at every sidebar size chosen in System Settings.
@MainActor
final class SidebarSizeTests: XCTestCase {
    func testTheFootsSettingsButtonOpensSettingsAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication.sample(settings: ["NSTableViewDefaultSizeMode": size])
            app.launch()
            let window = app.windows.firstMatch
            XCTAssertTrue(window.outlines["Sidebar"].waitForExistence(timeout: 10))
            let settings = window.descendants(matching: .any).matching(identifier: "SidebarOpenSettings").element(boundBy: 0)
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            XCTAssertTrue(settings.isHittable, "the Settings button is reachable at sidebar size \(size)")
            settings.click()
            XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0)
                .waitForExistence(timeout: 3))
            app.terminate()
        }
    }
}
