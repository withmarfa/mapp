import XCTest

/// The sidebar's foot, its instance menu and its New Item button, stays reachable at every sidebar size chosen in System Settings.
@MainActor
final class SidebarSizeTests: XCTestCase {
    func testTheInstanceMenuOpensSettingsAtEverySidebarSize() {
        for size in ["1", "2", "3"] {
            let app = XCUIApplication.sample(settings: ["NSTableViewDefaultSizeMode": size])
            app.launch()
            let window = app.windows.firstMatch
            XCTAssertTrue(window.outlines["Sidebar"].waitForExistence(timeout: 10))
            let instance = window.descendants(matching: .any).matching(identifier: "SidebarLibrary").element(boundBy: 0)
            XCTAssertTrue(instance.waitForExistence(timeout: 3))
            XCTAssertTrue(instance.isHittable, "the instance menu is reachable at sidebar size \(size)")
            let newItem = window.descendants(matching: .any).matching(identifier: "NewItemToolbar").element(boundBy: 0)
            XCTAssertTrue(newItem.isHittable, "the New Item button is reachable at sidebar size \(size)")
            instance.click()
            app.menuItems["Settings"].click()
            XCTAssertTrue(window.descendants(matching: .any).matching(identifier: "SettingsPageList").element(boundBy: 0)
                .waitForExistence(timeout: 3))
            app.terminate()
        }
    }
}
