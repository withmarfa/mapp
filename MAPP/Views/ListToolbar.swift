import SwiftUI

/// What acts on the list: Search and View Options together, then New Item when the sidebar is hidden. View As
/// is on the page's toolbar, at the trailing side, where the gallery and the table have it too. In the gallery and
/// the table, which have no list column, their own toolbar holds all of it.
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat
    var showsCreation = true

    var body: some ToolbarContent {
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
        if showsCreation && !browser.isSearchExpanded {
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
        Menu {
            if browser?.itemDraft != nil {
                Button("Continue Draft") { browser?.startItemDraft() }
            } else {
                ForEach(library.creatableTypes) { type in
                    Button {
                        browser?.startItemDraft(typeID: type.id.rawValue)
                    } label: {
                        Label(type.label, systemImage: TypeSymbol.name(for: type.id, in: library.catalogue))
                    }
                }
            }
        } label: {
            Label("New Item", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded || (browser?.itemDraft == nil && library.creatableTypes.isEmpty))
    }
}
