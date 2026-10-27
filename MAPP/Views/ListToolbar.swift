import SwiftUI

/// What acts on the list: Search and View Options together, and, for a type that has subtypes, the switch that
/// includes their items. View As is on the page's toolbar, at the trailing side,
/// so the order across the window is the one every view has (`GalleryToolbar`).
struct ListToolbar: ToolbarContent {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some ToolbarContent {
        let stacks = browser.stackableType(in: library) != nil
        if stacks {
            ToolbarItem(id: "listSubtypes") { IncludeSubtypesButton(browser: browser) }
        }
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            // The search field gives up the room the extra button takes beside it.
            layout: .column(width: stacks ? columnWidth - ColumnSearchMetrics.buttonChrome : columnWidth),
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            ViewOptionsMenu(browser: browser)
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
