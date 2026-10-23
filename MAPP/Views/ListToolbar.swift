import SwiftUI

/// What acts on the list, on the list column's toolbar: View Options and Search together, then New Item. In the
/// gallery, which has no list column, the gallery's own toolbar holds them.
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some ToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            columnWidth: columnWidth,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            ViewOptionsMenu(browser: browser)
        }
        // The field spans the column, so there is no room beside it.
        if !browser.isSearchExpanded {
            ToolbarSpacer(.fixed)
            ToolbarItem { NewItemButton(browser: browser) }
        }
    }
}

/// Starts an item in the place being shown.
struct NewItemButton: View {
    @CurrentLibrary private var library
    let browser: Browser?

    var body: some View {
        Button("New Item", systemImage: "square.and.pencil") {
            browser?.startItemDraft()
        }
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded)
    }
}
