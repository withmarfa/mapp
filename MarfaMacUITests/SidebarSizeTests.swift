import XCTest

/// The sidebar's foot, its instance menu and its New Item button, stays reachable at every sidebar size chosen in System Settings.
nonisolated final class SidebarSizeTests: XCTestCase {
    @MainActor func testTheInstanceMenuOpensSettingsAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication.sample(settings: ["NSTableViewDefaultSizeMode": size])
            app.launch()
            let window = app.windows.firstMatch
            XCTAssertTrue(window.outlines["Sidebar"].waitForExistence(timeout: 10))
            let instance = window.descendants(matching: .any).matching(identifier: "SidebarSettings").element(boundBy: 0)
            XCTAssertTrue(instance.waitForExistence(timeout: 3))
            XCTAssertTrue(instance.isHittable, "the instance menu is reachable at sidebar size \(size)")
            let newItem = window.descendants(matching: .any).matching(identifier: "SidebarNew").element(boundBy: 0)
            XCTAssertTrue(newItem.isHittable, "the New Item button is reachable at sidebar size \(size)")
            instance.click()
            app.menuItems["Settings"].click()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "SettingsSidebar").element(boundBy: 0)
                .waitForExistence(timeout: 3))
            app.terminate()
        }
    }
}
