import SwiftUI

/// What acts on the list: Search and View Options together. View As
/// is on the page's toolbar, at the trailing side, where the gallery and the table have it too. In the gallery and
/// the table, which have no list column, their own toolbar holds all of it.
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some ToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: .column(width: columnWidth),
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            ViewOptionsMenu()
        }
    }
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
        .labelStyle(.iconOnly)
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded || QuickAdd.types(in: library).isEmpty)
    }
}
