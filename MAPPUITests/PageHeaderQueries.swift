import XCTest

extension XCUIElement {
    /// The item's title, drawn by the editor page as a text box named "Title".
    var itemPageTitle: XCUIElement { pageHeaderElement("ItemPageTitle", named: "Title", type: .textField) }

    /// The status chip in the page's header, a pop-up button named "Status".
    var itemStatusChip: XCUIElement { pageHeaderElement("ItemStatusChip", named: "Status", type: .any) }

    // The header is web content, where WebKit may not expose the DOM id as the identifier, so its accessible name
    // also finds it. Only the web view is searched, so no native control with the same name matches.
    private func pageHeaderElement(_ id: String, named name: String, type: XCUIElement.ElementType) -> XCUIElement {
        webViews.descendants(matching: type)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@ OR title == %@", id, name, name))
            .firstMatch
    }
}
