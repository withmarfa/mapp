import SwiftUI

/// Indexes navigate to the library's collections and the sources of readable items, never synthetic item records.
struct SidebarIndex: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    let showsCreation: Bool
    @State private var model = IndexRowsModel()

    private var place: IndexPlace { browser.indexPlace ?? .sources }

    var body: some View {
        IndexContent(
            place: place, rows: model.rows(for: place), isBuilt: model.isBuilt(for: place), slots: model.slots, browser: browser,
            order: order) { row in
            browser.show(row.place, in: library, order: order)
        }
        .task(id: Following(place: place, library: ObjectIdentifier(library))) { model.follow(place, in: library) }
        .onDisappear { model.stop() }
        .navigationTitle(library.name(of: browser.item))
        .navigationSubtitle(summary)
        .toolbar {
            if showsCreation {
                ToolbarItem(id: "indexNewItem") {
                    NewItemButton(browser: browser)
                }
            }
            ToolbarSpacer(.flexible)
            IndexToolbar(browser: browser, place: place)
        }
        .accessibilityIdentifier("SidebarIndex")
    }

    private struct Following: Hashable {
        let place: IndexPlace
        let library: ObjectIdentifier
    }

    /// How many places the page lists, and for sources how many items they hold between them.
    private var summary: String {
        let rows = model.rows(for: place)
        guard !rows.isEmpty else { return "" }
        switch place {
        case .sources:
            let items = rows.reduce(0) { $0 + $1.count }
            return String(localized: "\(rows.count) sources") + ", " + String(localized: "\(items) items")
        case .collections:
            return String(localized: "\(rows.count) collections")
        }
    }
}

/// The rows of one index page, searched, in the layout and width the person chose for the page.
private struct IndexContent: View {
    @CurrentLibrary private var library
    let place: IndexPlace
    let rows: [IndexRow]
    let isBuilt: Bool
    let slots: IndexSlots
    let browser: Browser
    let order: NoteOrder
    let open: (IndexRow) -> Void
    @AppStorage private var layout: IndexLayout
    @AppStorage private var width: IndexWidth

    init(
        place: IndexPlace, rows: [IndexRow], isBuilt: Bool, slots: IndexSlots, browser: Browser, order: NoteOrder,
        open: @escaping (IndexRow) -> Void
    ) {
        self.place = place
        self.rows = rows
        self.isBuilt = isBuilt
        self.slots = slots
        self.browser = browser
        self.order = order
        self.open = open
        _layout = AppStorage(wrappedValue: .default, place.layoutKey)
        _width = AppStorage(wrappedValue: .default, place.widthKey)
    }

    var body: some View {
        if !isBuilt {
            Color.clear
        } else if rows.isEmpty {
            empty
        } else {
            let shown = browser.isSearching ? rows.filter(matches) : rows
            if shown.isEmpty {
                EmptyState("No Results")
            } else {
                IndexPage(
                    rows: shown, palette: IndexPalette(slots: slots), layout: layout, width: width, typesTitle: typesTitle,
                    showsSecondaryOnCards: place != .sources,
                    drop: place == .collections ? IndexDrop(browser: browser, order: order) : nil, open: open)
            }
        }
    }

    private func matches(_ row: IndexRow) -> Bool {
        let query = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return row.title.localizedStandardContains(query) || row.secondary.localizedStandardContains(query)
            || row.types.localizedStandardContains(query)
    }

    private var typesTitle: LocalizedStringKey {
        switch place {
        case .sources: "Writes"
        case .collections: "Contains"
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch place {
        case .sources:
            EmptyState("No Sources", detail: "Sources appear here when items identify where they came from.")
        case .collections:
            if library.catalogue.collectionTypes.isEmpty {
                EmptyState("No Collections", detail: "This library has no collection type.")
            } else {
                EmptyState("No Collections", detail: "Collections you make appear here.")
            }
        }
    }
}

/// Search and the page's options, as the gallery and the table have them at the toolbar's trailing side.
private struct IndexToolbar: ToolbarContent {
    @Bindable var browser: Browser
    let place: IndexPlace

    var body: some ToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: .item,
            focusRequests: browser.searchFocusRequests
        ) {
            IndexViewOptionsMenu(place: place)
        }
    }
}
