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

/// Makes an item of the chosen type in the place being shown, and opens it.
struct NewItemButton: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser?

    var body: some View {
        Menu {
            ForEach(library.creatableTypes) { type in
                Button {
                    browser?.startNewItem(typeID: type.id.rawValue, in: library, undoManager: undoManager)
                } label: {
                    Label(type.label, systemImage: TypeSymbol.name(for: type.id, in: library.catalogue))
                }
                .disabled(browser?.isAwaitingNewItem == true)
            }
        } label: {
            Label("New Item", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded || library.creatableTypes.isEmpty)
    }
}
