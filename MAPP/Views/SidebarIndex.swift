import SwiftUI

/// Indexes navigate to the library's collections and the sources of readable items, never synthetic item records.
struct SidebarIndex: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let details: DetailsPresentation
    let order: ItemOrder
    @State private var model = IndexRowsModel()
    @State private var choice = IndexChoice()
    @State private var editing: SourceEditRequest?
    @State private var deleting: IndexRow?
    @AppStorage private var tab: IndexTab

    init(browser: Browser, details: DetailsPresentation, order: ItemOrder) {
        self.browser = browser
        self.details = details
        self.order = order
        _tab = AppStorage(wrappedValue: .all, (browser.indexPlace ?? .sources).tabKey)
    }

    private var place: IndexPlace { browser.indexPlace ?? .sources }

    var body: some View {
        let rows = model.rows(for: place)
        IndexContent(
            place: place, rows: rows, isBuilt: model.isBuilt(for: place), browser: browser, tab: tabBinding, choice: choice,
            edit: place == .sources ? { editing = $0 } : nil, delete: place == .collections ? { deleting = $0 } : nil,
            newCollection: place == .collections ? { browser.openQuickAdd(in: library) } : nil
        ) { row in
            browser.show(row.place, in: library, order: order)
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            IndexInspector(choice: choice, rows: rows) { browser.show($0.place, in: library, order: order) }
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
                .toolbar(id: WindowToolbarLayout.index) { InspectorToolbar(details: details, editor: nil, browser: browser) }
        }
        .task(id: Following(place: place, library: ObjectIdentifier(library))) {
            choice.chosen = nil
            model.follow(place, in: library)
        }
        // A container that goes (deleted here or by another app, or gone on a sync) takes the right sidebar's content
        // with it, and a place built again starts with nothing chosen.
        .onChange(of: rows) { choice.keep(within: rows) }
        // The names and counts are the server's, so they are asked again whenever the items change while the page is
        // open, and when the page opens.
        .task(id: SourceRefresh(place: place, library: ObjectIdentifier(library), membership: library.membershipRevision)) {
            if place == .sources { await library.refreshSources() }
        }
        .sheet(item: $editing) { request in
            switch request.mode {
            case .name: SourceNameSheet(request: request, library: library)
            case .mark: SourceMarkSheet(request: request, library: library)
            }
        }
        .alert(
            DeletionWords.collectionTitle(deleting?.title ?? ""), isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
            presenting: deleting
        ) { row in
            Button("Delete", role: .destructive) { delete(row) }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text(DeletionWords.collectionMessage(keeping: row.count))
        }
        .onDisappear { model.stop() }
        .navigationTitle(library.name(of: browser.item))
        .navigationSubtitle(summary)
        .accessibilityIdentifier("SidebarIndex")
    }

    /// The tab, whatever is kept, which is read as All when it is not one of the page's tabs.
    private var tabBinding: Binding<IndexTab> {
        Binding { place.tabs.contains(tab) ? tab : .all } set: { tab = $0 }
    }

    /// Removes the collection and no member: a collection's members hold their own edges to it, and those stay, so
    /// Undo, or Recently Deleted, brings the collection back with its members.
    private func delete(_ row: IndexRow) {
        guard case .collection(let id) = row.place else { return }
        library.deleteAfterSaving([id], undoManager: undoManager, asking: details, naming: row.title)
    }

    private struct SourceRefresh: Hashable {
        let place: IndexPlace
        let library: ObjectIdentifier
        let membership: Int
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

/// The rows of one index page under their tabs, searched.
private struct IndexContent: View {
    @CurrentLibrary private var library
    let place: IndexPlace
    let rows: [IndexRow]
    let isBuilt: Bool
    let browser: Browser
    @Binding var tab: IndexTab
    let choice: IndexChoice
    let edit: ((SourceEditRequest) -> Void)?
    let delete: ((IndexRow) -> Void)?
    let newCollection: (() -> Void)?
    let open: (IndexRow) -> Void

    var body: some View {
        if !isBuilt {
            Color.clear
        } else if rows.isEmpty {
            empty
        } else {
            let searched = browser.isSearching ? rows.filter(matches) : rows
            let shown = tab.rows(in: searched)
            IndexPage(
                place: place, rows: shown, tabs: place.tabs.map { (tab: $0, count: $0.rows(in: searched).count) }, tab: $tab,
                choice: choice, open: open, edit: edit, delete: delete, newCollection: newCollection, emptyTab: emptyTab)
        }
    }

    private func matches(_ row: IndexRow) -> Bool {
        let query = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return row.title.localizedStandardContains(query) || row.types.localizedStandardContains(query)
    }

    /// What the table says when the chosen tab, or the search, leaves nothing.
    private var emptyTab: EmptyState<EmptyView> {
        if browser.isSearching { return .search(browser.searchText) }
        return switch tab {
        case .all: EmptyState("No Results")
        case .yours: EmptyState("No Collections Of Yours", detail: "Collections you make appear here.")
        case .fromApps: EmptyState("No Collections From Apps", detail: "Collections that apps make appear here.")
        case .apps: EmptyState("No Apps", detail: "Apps you sign in appear here.")
        case .keys: EmptyState("No Keys", detail: "Keys you make appear here.")
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
