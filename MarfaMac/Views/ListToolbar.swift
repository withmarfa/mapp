import SwiftUI

/// What acts on a list beside its page, in the list column: Back and Forward while the sidebar that holds them is
/// closed, then Search and View. The rest of the window's items are the page column's (`WindowToolbar`).
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat
    /// Whether Back and Forward lead this column, because the sidebar that holds them is closed.
    var leadsWithHistory = false

    var body: some ToolbarContent {
        if leadsWithHistory {
            ToolbarItem(placement: .navigation) { SidebarHistory(browser: browser) }
                .sharedBackgroundVisibility(.hidden)
        }
        ViewToolbarItems(browser: browser, layout: .column(width: columnWidth))
    }
}

/// Search and what sets up the view shown, in the order every view has them. The index pages have their own
/// (`IndexToolbarItems`).
struct ViewToolbarItems: ToolbarContent {
    @Bindable var browser: Browser
    let layout: ColumnSearch.Layout

    var body: some ToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: layout,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        )
        ToolbarItem {
            ViewOptionsMenu(browser: browser)
        }
    }
}
