import SwiftUI

/// What acts on the list: Search and View Options, in the list column. The rest of
/// the window's items are the page column's (`WindowToolbar`).
struct ListToolbar: CustomizableToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some CustomizableToolbarContent {
        ViewToolbarItems(browser: browser, layout: .column(width: columnWidth))
    }
}

/// Search and what sets up the view shown, in the order every view has them. The index pages have their own
/// (`IndexToolbarItems`).
struct ViewToolbarItems: CustomizableToolbarContent {
    @Bindable var browser: Browser
    let layout: ColumnSearch.Layout
    var isHidden = false

    var body: some CustomizableToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: layout,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        )
        .hidden(isHidden)
        ToolbarItem(id: "viewOptions") {
            ViewOptionsMenu(browser: browser)
        }
        .hidden(isHidden)
    }
}
