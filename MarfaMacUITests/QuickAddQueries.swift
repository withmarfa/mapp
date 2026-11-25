import XCTest

extension XCUIElement {
    /// Makes an item through the new-item line: the sidebar's New row, its kind from the kind menu, its title, then
    /// Command-Return, which opens it.
    func quickAdd(type: String, title: String) {
        descendants(matching: .any)["SidebarNew"].click()
        completeQuickAdd(type: type, title: title)
    }

    func completeQuickAdd(type: String, title: String) {
        let field = descendants(matching: .any)["NewItemLineTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        descendants(matching: .any)["NewItemLineKind"].click()
        menuItems[type].click()
        field.click()
        field.typeText(title)
        typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: itemPageTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 3), .completed)
    }
}
