import SwiftUI

/// What acts on the list, on the list column's toolbar: the view switch, then View Options and Search together,
/// then New Item. In the gallery and the table, which have no list column, their own toolbar holds them.
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some ToolbarContent {
        // The field spans the column, so the switch gives way to it.
        if !browser.isSearchExpanded {
            ToolbarItem { ViewModePicker(browser: browser) }
            ToolbarSpacer(.fixed)
        }
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            columnWidth: columnWidth,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            ViewOptionsMenu()
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
