import XCTest

extension XCUIElement {
    /// Makes an item through quick add: New Item, its kind, its title, then Command-Return, which opens it.
    func quickAdd(type: String, title: String) {
        buttons["NewItemToolbar"].click()
        let field = descendants(matching: .any)["QuickAddTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let chip = descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'QuickAddType.' AND label == %@", type)).firstMatch
        if chip.exists {
            chip.click()
        } else {
            descendants(matching: .any)["QuickAddMoreTypes"].click()
            menuItems[type].click()
        }
        field.click()
        field.typeText(title)
        typeKey(.return, modifierFlags: .command)
    }
}
