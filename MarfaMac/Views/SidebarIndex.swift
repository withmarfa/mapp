import SwiftUI

/// Indexes navigate to the library's collections and the sources of readable items, never synthetic item records.
struct SidebarIndex: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let details: DetailsPresentation
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var model = IndexRowsModel()
    @State private var choice = IndexChoice()
    @State private var editing: SourceEditRequest?
    @State private var deleting: IndexRow?
    /// The title of the collection last asked about, kept while the alert goes away so its title never empties.
    @State private var deletingTitle = ""
    @AppStorage private var tab: IndexTab

    init(browser: Browser, details: DetailsPresentation, order: ItemOrder, pane: FocusState<Browser.Pane?>.Binding) {
        self.browser = browser
        self.details = details
        self.order = order
        self.pane = pane
        _tab = AppStorage(wrappedValue: .all, (browser.indexPlace ?? .sources).tabKey)
    }

    private var place: IndexPlace { browser.indexPlace ?? .sources }

    var body: some View {
        let rows = model.rows(for: place)
        IndexContent(
            place: place, title: library.name(of: browser.shown), rows: rows, isBuilt: model.isBuilt(for: place), browser: browser, pane: pane, tab: tabBinding, choice: choice,
            edit: place == .sources ? { editing = $0 } : nil, delete: place == .collections ? { ask($0) } : nil,
            newCollection: place == .collections ? { browser.openQuickAddFromIndex(remembered: "", in: library) } : nil
        ) { row in
            browser.show(PlaceView(row.place), in: library, order: order)
        }
        .inspector(isPresented: Binding { details.isPresented } set: { details.isPresented = $0 }) {
            IndexInspector(choice: choice, place: place, rows: rows) { browser.show(PlaceView($0.place), in: library, order: order) }
                .inspectorColumnWidth(min: 260, ideal: 310, max: 440)
                .toolbar { InspectorToolbar(details: details, editor: nil, browser: browser) }
        }
        .task(id: Following(place: place, library: ObjectIdentifier(library))) {
            choice.chosen = nil
            model.follow(place, in: library)
        }
        // A container that goes (deleted here or by another app, or gone on a sync) takes the right sidebar's content
        // with it, and a place built again starts with nothing chosen.
        .onChange(of: rows) { choice.keep(within: rows) }
        // The names and counts are the server's, so they are asked again whenever the items change while the page is
        // open, and when the page opens. A collection's source is named from the same answer.
        .task(id: SourceRefresh(place: place, library: ObjectIdentifier(library), membership: library.membershipRevision)) {
            await library.refreshSources()
        }
        .sheet(item: $editing) { request in
            switch request.mode {
            case .name: SourceNameSheet(request: request, library: library)
            case .mark: SourceMarkSheet(request: request, library: library)
            }
        }
        .alert(
            DeletionWords.collectionTitle(deletingTitle), isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
            presenting: deleting
        ) { row in
            Button("Delete", role: .destructive) { delete(row) }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text(DeletionWords.collectionMessage(keeping: row.count))
        }
        .focusedSceneValue(\.indexActions, actions(in: rows))
        .onDisappear { model.stop() }
        .accessibilityIdentifier("SidebarIndex")
    }

    /// The tab, whatever is kept, which is read as All when it is not one of the page's tabs.
    private var tabBinding: Binding<IndexTab> {
        Binding { place.tabs.contains(tab) ? tab : .all } set: { tab = $0 }
    }

    /// What the File menu offers for the chosen row: the same as its row menu.
    private func actions(in rows: [IndexRow]) -> IndexActions {
        guard let row = choice.row(in: rows) else { return IndexActions() }
        let code = place == .sources ? row.sourceCode : nil
        return IndexActions(
            rename: code.map { code in { editing = SourceEditRequest(code: code, mode: .name) } },
            chooseMark: code.map { code in { editing = SourceEditRequest(code: code, mode: .mark) } },
            delete: place == .collections && row.canDelete ? { ask(row) } : nil)
    }

    /// Asks before deleting a collection, unless it is read-only.
    private func ask(_ row: IndexRow) {
        guard row.canDelete else { return }
        deletingTitle = row.title
        deleting = row
    }

    /// Removes the collection and no member: a collection's members hold their own edges to it, and those stay, so
    /// Undo, or Recently Deleted, brings the collection back with its members.
    private func delete(_ row: IndexRow) {
        guard row.canDelete, case .collection(let id) = row.place else { return }
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
}

/// The rows of one index page under their tabs, searched.
private struct IndexContent: View {
    @CurrentLibrary private var library
    let place: IndexPlace
    let title: String
    let rows: [IndexRow]
    let isBuilt: Bool
    let browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
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
            let narrowed = place == .collections && !browser.collectionSourceFilter.isEmpty
                ? rows.filter { browser.collectionSourceFilter.contains($0.sourceName) } : rows
            let searched = browser.isSearching ? narrowed.filter(matches) : narrowed
            let shown = tab.rows(in: searched)
            IndexPage(
                place: place, title: title, browser: browser, pane: pane,
                sources: Set(rows.map(\.sourceName)).filter { !$0.isEmpty }.sorted(), rows: shown, tabs: place.tabs.map { (tab: $0, count: $0.rows(in: searched).count) }, tab: $tab,
                choice: choice, open: open, edit: edit, delete: delete, newCollection: newCollection, emptyTab: emptyTab)
        }
    }

    private func matches(_ row: IndexRow) -> Bool {
        let query = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return row.title.localizedStandardContains(query) || row.types.localizedStandardContains(query)
    }

    /// What the table says when the chosen tab, or the search, leaves nothing.
    private var emptyTab: EmptyState<EmptyView> {
        if browser.isSearching { return .search() }
        return switch tab {
        case .all: EmptyState("No Results")
        case .library: EmptyState("No Collections in the Library", detail: "Collections you make show here.")
        case .feed: EmptyState("No Collections in the Feed", detail: "Collections that apps make show here.")
        case .apps: EmptyState("No Apps", detail: "Apps you sign in show here.")
        case .keys: EmptyState("No Keys", detail: "Keys you make show here.")
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch place {
        case .sources:
            EmptyState("No Sources", detail: "Sources show where items came from.")
        default:
            if library.catalogue.collectionTypes.isEmpty {
                EmptyState("No Collections", detail: "This library has no collection type.")
            } else {
                EmptyState("No Collections", detail: "Collections you make show here.")
            }
        }
    }
}
