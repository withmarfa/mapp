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

/// Search and what sets up the view shown, in the order every view has them.
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
            // Items' rows are items, so Down goes into its table; the other indexes list places, which a search filters.
            onDown: { if !browser.showsSidebarIndex || browser.showsItemsIndex { browser.focusRequest = .list } }
        )
        .hidden(isHidden)
        ToolbarItem(id: "viewOptions") {
            if let place = browser.indexPlace {
                IndexViewOptionsMenu(place: place, browser: browser)
            } else {
                ViewOptionsMenu(browser: browser)
            }
        }
        .hidden(isHidden)
    }
}
