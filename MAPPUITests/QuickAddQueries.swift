import XCTest

extension XCUIElement {
    /// Makes an item through quick add: New Item, its kind from the footer's menu, its title, then Command-Return,
    /// which opens it.
    func quickAdd(type: String, title: String) {
        buttons["NewItemToolbar"].click()
        completeQuickAdd(type: type, title: title)
    }

    func completeQuickAdd(type: String, title: String) {
        let field = descendants(matching: .any)["QuickAddTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        descendants(matching: .any)["QuickAddType"].click()
        menuItems[type].click()
        field.click()
        field.typeText(title)
        typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: itemPageTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 3), .completed)
    }
}
