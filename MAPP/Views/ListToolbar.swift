import SwiftUI

/// What acts on the list: Search, Filter and View Options, in the list column. The rest of
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
            onDown: { if !browser.showsSidebarIndex { browser.focusRequest = .list } }
        )
        .hidden(isHidden)
        ToolbarItem(id: "viewFilter") {
            if showsFilter {
                ItemTableFilterMenu(browser: browser)
            } else {
                Menu("Filter", systemImage: "line.3.horizontal.decrease") {}.disabled(true)
            }
        }
        .hidden(isHidden || !showsFilter)
        ToolbarItem(id: "viewOptions") {
            if let place = browser.indexPlace {
                IndexViewOptionsMenu(place: place)
            } else {
                ViewOptionsMenu(browser: browser)
            }
        }
        .hidden(isHidden)
    }

    private var showsFilter: Bool { browser.offersViewOptions && !browser.showsSidebarIndex }
}

/// Opens quick add, to make an item in the place being shown.
struct NewItemButton: View {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let browser: Browser?

    var body: some View {
        Button("New Item", systemImage: "plus") {
            browser?.openQuickAdd(remembered: lastType, in: library)
        }
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !QuickAdd.isAvailable(in: library))
    }
}
