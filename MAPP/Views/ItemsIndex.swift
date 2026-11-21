import AppKit
import SwiftUI

/// Items as an index: every item of the library under the tabs All, Yours (the library tier) and From Apps (the feed
/// tier), as a table with no list column. The chosen row is the window's selection, which the right sidebar shows
/// (`ItemInspectorHost`), and opening one follows Settings > General > Open Items (`Browser.open`).
///
/// A library may hold tens of thousands of items, so the page works none of them out itself: the rows of each tab are
/// the window's `ItemIndexModel`'s, worked out once and kept while the page is away, and a change of tab reads one of
/// them. The table draws a page of them at a time. This body never reads the selection, so choosing a row runs no other
/// row's body.
struct ItemsIndex: View {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @AppStorage private var storedTab: IndexTab
    @AppStorage private var storedSort: IndexSort

    init(browser: Browser, pane: FocusState<Browser.Pane?>.Binding) {
        self.browser = browser
        self.pane = pane
        _storedTab = AppStorage(wrappedValue: .all, IndexPlace.items.tabKey)
        _storedSort = AppStorage(wrappedValue: IndexPlace.items.defaultSort, IndexPlace.items.sortKey)
    }

    private static let place = IndexPlace.items

    /// The kept tab, read as All where it is not one of the page's tabs.
    private var tab: IndexTab { Self.place.tabs.contains(storedTab) ? storedTab : .all }

    /// The kept sort, or the page's own while what is kept is of a column the page lacks.
    private var sort: IndexSort { Self.place.columns.contains(storedSort.column) ? storedSort : Self.place.defaultSort }

    var body: some View {
        let model = browser.itemIndex
        let searching = browser.isSearching
        // The tabs of a search are the search's own, at most `SearchResults.limit` items worked out here; otherwise the model's.
        let tabs = searching ? browser.searchedItemTabs(in: library) : model.tabs
        content(tabs: tabs, searching: searching)
            .searchStatus(browser)
            .toolbar(removing: browser.isSearchExpanded ? .title : nil)
            .onChange(of: browser.isSearchExpanded) {
                if !browser.isSearchExpanded { browser.focusRequest = .list }
            }
            .task(id: Following(library: ObjectIdentifier(library), sort: sort)) { model.follow(library, sort: sort) }
            // The names of the sources a row shows are the server's, so they are asked again when the items change.
            .task(id: SourceRefresh(library: ObjectIdentifier(library), membership: library.membershipRevision)) {
                await library.refreshSources()
            }
            // An item that goes (deleted here or by another app, or gone on a sync) takes the right sidebar's content with it.
            .onChange(of: library.membershipRevision, initial: true) { browser.keepItemChoice(in: library) }
            .onDisappear { if browser.item != .allItems { model.stop() } }
            .navigationTitle(library.name(of: browser.item))
            .navigationSubtitle(subtitle(of: tabs, searching: searching))
            .accessibilityIdentifier("ItemsIndex")
    }

    @ViewBuilder
    private func content(tabs: ItemIndexTabs?, searching: Bool) -> some View {
        // A library that has not loaded lists nothing, which says nothing about it.
        if let tabs, library.isLoaded || !tabs.all.isEmpty {
            let shown = tabs.rows(for: tab)
            VStack(spacing: 0) {
                IndexTabBar(
                    tabs: Self.place.tabs.map { (tab: $0, count: tabs.count(for: $0)) },
                    tab: Binding { tab } set: { storedTab = $0 }
                ) {
                    Button("New Item", systemImage: "plus") { browser.openQuickAdd(remembered: lastType, in: library) }
                        .mappButton(.secondary)
                        .disabled(!QuickAdd.isAvailable(in: library))
                        .accessibilityIdentifier("NewItem")
                }
                if shown.isEmpty {
                    emptyState(allCount: tabs.all.count, searching: searching)
                } else {
                    ItemsTable(browser: browser, rows: shown, sort: sortBinding, pane: pane)
                        // A change of tab, of search or of sort starts the table at its first page.
                        .id(Paging(tab: tab, search: searching ? browser.searchText : "", sort: sort, byRelevance: browser.ordersByRelevance))
                }
            }
        } else {
            ProgressView("Loading…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// What the page says while the chosen tab, or the search, lists nothing.
    @ViewBuilder
    private func emptyState(allCount: Int, searching: Bool) -> some View {
        if searching {
            SearchEmptyState(browser: browser)
        } else if allCount == 0 {
            EmptyState("No Items", detail: "Items you make or apps send show here.")
        } else {
            switch tab {
            case .yours: EmptyState("No Items Of Yours", detail: "Items you make show here.")
            case .fromApps: EmptyState("No Items From Apps", detail: "Items that apps send show here.")
            case .all, .apps, .keys: EmptyState("No Items")
            }
        }
    }

    private var sortBinding: Binding<IndexSort> {
        Binding { sort } set: { storedSort = $0 }
    }

    /// How many items the page lists: every item, or what the search found.
    private func subtitle(of tabs: ItemIndexTabs?, searching: Bool) -> Text {
        guard let tabs else { return Text(verbatim: "") }
        let count = tabs.all.count
        if searching { return Text("^[\(count) result](inflect: true)") }
        return count == 0 ? Text("No items") : Text("^[\(count) item](inflect: true)")
    }

    private struct Following: Hashable {
        let library: ObjectIdentifier
        let sort: IndexSort
    }

    private struct SourceRefresh: Hashable {
        let library: ObjectIdentifier
        let membership: Int
    }

    /// What the table's pages belong to: another tab, search or order starts again at the first page.
    private struct Paging: Hashable {
        let tab: IndexTab
        let search: String
        let sort: IndexSort
        let byRelevance: Bool
    }
}

/// The rows of one tab as a table, a page at a time. Its cells are views of plain values, so a change of the chosen row
/// finds each unchanged and runs none of their bodies: the selection is read only by the table's own closures and the
/// soft selection's marks, never by this body. The rows arrive in the order of the sort, which the table does not repeat.
private struct ItemsTable: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser
    let rows: [ItemIndexRow]
    @Binding var sort: IndexSort
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var pages = 1

    /// How many rows each page adds.
    private static let pageSize = TablePageSize.twoHundred.rawValue

    /// The header's arrow: none while a search lists its results by relevance, until the person clicks a column.
    private var sortOrder: Binding<[KeyPathComparator<ItemIndexRow>]> {
        Binding {
            browser.ordersByRelevance ? [] : sort.itemComparators
        } set: { comparators in
            guard let next = IndexSort(comparators: comparators) else { return }
            sort = next
            browser.orderSearch(byRelevance: false)
        }
    }

    /// The rows chosen: one shows in the right sidebar, several are acted on together by the menu and the keys.
    private var selection: Binding<Set<ItemID>> {
        Binding { browser.selection } set: { if browser.selection != $0 { browser.selection = $0 } }
    }

    var body: some View {
        let shown = Array(rows.prefix(pages * Self.pageSize))
        let remaining = rows.count - shown.count
        Table(of: ItemIndexRow.self, selection: selection, sortOrder: sortOrder) {
            TableColumn(IndexColumn.name.title(in: .items), value: \.title, comparator: .localizedStandard) { row in
                ItemsNameCell(title: row.title, icon: row.icon).tableCellRoom()
            }
            .width(min: 160, ideal: 360)
            TableColumn(IndexColumn.types.title(in: .items), value: \.typeLabel, comparator: .localizedStandard) { row in
                Text(verbatim: row.typeLabel).foregroundStyle(.secondary).lineLimit(1).tableCellRoom()
            }
            .width(min: 100, ideal: 160)
            TableColumn(IndexColumn.source.title(in: .items), value: \.sourceName, comparator: .localizedStandard) { row in
                Text(verbatim: row.sourceName).foregroundStyle(.secondary).lineLimit(1).tableCellRoom()
            }
            .width(min: 100, ideal: 160)
            TableColumn(IndexColumn.latest.title(in: .items), value: \.modified) { row in
                IndexLatest(date: row.modified).foregroundStyle(.secondary).tableCellRoom()
            }
            .width(min: 100, ideal: 140, max: 200)
        } rows: {
            ForEach(shown) { TableRow($0) }
            if remaining > 0 {
                Section {
                    ForEach([ItemIndexRow]()) { TableRow($0) }
                } header: {
                    ItemTableLoadMore(remaining: remaining) { pages += 1 }
                }
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .softSelection(rows: shown.map(\.id), hovers: true, selection: { browser.selection })
        .quietTableHeader()
        .background { RevealChoice(browser: browser, rows: rows, pages: $pages) }
        .remembersScroll(in: browser.listMemory)
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            ItemRowMenu(browser: browser, ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            browser.open(ids)
        }
        .quickLooksOnSpace(browser)
        .onKeyPress(.return) { browser.openSelection() ? .handled : .ignored }
        .onKeyPress(.escape) {
            browser.selection = []
            return .handled
        }
        .onDeleteCommand {
            library.deleteAfterSaving(browser.selection, undoManager: undoManager, asking: details)
        }
        .contentMargins(.horizontal, IndexMetrics.side, for: .scrollContent)
        .accessibilityIdentifier("ItemsTable")
    }
}

/// Looks after the chosen row: loads the pages that hold it, so one reached by Back, a link or a restored window is
/// drawn and marked, scrolls to one a reveal asked for, and has the model keep it where it is while the rows are worked
/// out again. A view of its own, since it reads the selection, which the table's body must not.
private struct RevealChoice: View {
    let browser: Browser
    let rows: [ItemIndexRow]
    @Binding var pages: Int
    /// The row to bring into view, and which request it answers.
    @State private var scroll: (row: Int, request: Int)?
    @State private var requests = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: browser.selection, initial: true) {
                browser.itemIndex.pin(browser.selection.count == 1 ? browser.selection.first : nil)
                reveal()
            }
            // The tab a reveal switches to, and a search's rows, arrive after the request.
            .onChange(of: browser.itemToScrollTo, initial: true) { reveal() }
            .onChange(of: rows.count) { reveal() }
            .background { RowScroller(row: scroll?.row, request: scroll?.request ?? 0) }
    }

    private func reveal() {
        guard browser.selection.count == 1, let id = browser.selection.first else {
            browser.itemToScrollTo = nil
            return
        }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let needed = index / TablePageSize.twoHundred.rawValue + 1
        if needed > pages { pages = needed }
        guard browser.itemToScrollTo == id else { return }
        browser.itemToScrollTo = nil
        requests += 1
        scroll = (index, requests)
    }
}

/// Brings a row of the table behind it into view when asked, waiting for the table to hold it, which a page just
/// loaded does a moment after.
private struct RowScroller: NSViewRepresentable {
    let row: Int?
    let request: Int

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        guard let row, probe.answered != request else { return }
        probe.answered = request
        Task { @MainActor [weak probe] in
            for _ in 0..<20 {
                if let table = probe?.nearestTable(), table.numberOfRows > row {
                    table.scrollRowToVisible(row)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    final class Probe: NSView {
        var answered = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The type's mark in its color, then the item's name.
private struct ItemsNameCell: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String?

    var body: some View {
        HStack(spacing: 8) {
            TypeGlyph(id: icon)
                .font(.system(size: IndexMetrics.icon * 0.8))
                .foregroundStyle(TypeTone(icon: icon).color(for: scheme))
                .frame(width: IndexMetrics.icon, height: IndexMetrics.icon)
                .accessibilityHidden(true)
            Text(verbatim: title).lineLimit(1)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}
