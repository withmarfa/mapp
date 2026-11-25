import AppKit
import SwiftUI

/// Library › Types, Collections and Sources: the places the Library holds, as a table under the Library's top row. A
/// row opens its place; its menu has what a person does with that place. The rows are the browser's
/// (`Browser.indexRows(in:)`), so a draw reads no item.
struct PlaceIndex: View {
    @CurrentLibrary private var library
    let browser: Browser
    let details: DetailsPresentation
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding

    var body: some View {
        let place = browser.shown.place
        let rows = browser.indexRows(in: library)
        Group {
            if !library.isLoaded, rows.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                PlaceEmptyState(browser: browser)
            } else {
                let shown = searched(rows)
                if shown.isEmpty {
                    EmptyState.search()
                } else {
                    PlaceIndexTable(place: place, rows: shown, browser: browser, details: details, order: order, pane: pane)
                        // Each place has its own columns and order.
                        .id(place)
                }
            }
        }
        // The names, marks and counts are the server's, so they are asked again when the items change and when the page
        // opens; which source is a connector is read once for the library.
        .task(id: SourceRefresh(library: ObjectIdentifier(library), membership: library.membershipRevision)) {
            guard place != .types else { return }
            await library.refreshSources()
            if place == .sources { await library.readConnectors() }
        }
        .accessibilityIdentifier("PlaceIndex")
    }

    private func searched(_ rows: [IndexRow]) -> [IndexRow] {
        let query = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.title.localizedStandardContains(query) }
    }

    private struct SourceRefresh: Hashable {
        let library: ObjectIdentifier
        let membership: Int
    }
}

/// The measures of the tables, on a 4 point grid.
private enum PlaceIndexMetrics {
    static let side: CGFloat = 16
    static let icon: CGFloat = 16
    /// How far a kind's name stands in from its type's: the mark's width and the gap after it.
    static let nesting: CGFloat = 23
    /// The room after a count's digits, so the numbers sit clear of the next column's.
    static let countRoom: CGFloat = 10
    /// A source's Writes names this many types and counts the rest.
    static let writesShown = 3
}

/// One place's table. Its cells are views of plain values, so choosing a row runs no other row's body.
private struct PlaceIndexTable: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    let place: Place
    let rows: [IndexRow]
    let browser: Browser
    let details: DetailsPresentation
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var chosen: Place?
    /// The order the person chose by a column's heading, kept while the window shows the place.
    @State private var sortOrder: [KeyPathComparator<IndexRow>] = []
    @State private var editing: SourceEditRequest?
    @State private var deleting: IndexRow?
    /// The title of the collection last asked about, kept while the alert goes away so its title never empties.
    @State private var deletingTitle = ""
    @State private var renaming: IndexRow?
    @State private var newName = ""

    /// Each place's own order until the person chooses: types and sources by how much they hold, collections by their
    /// latest change.
    private var defaultOrder: [KeyPathComparator<IndexRow>] {
        switch place {
        case .collections: [KeyPathComparator(\IndexRow.latestOrOldest, order: .reverse)]
        default: [KeyPathComparator(\IndexRow.count, order: .reverse)]
        }
    }

    private var sortBinding: Binding<[KeyPathComparator<IndexRow>]> {
        Binding { sortOrder.isEmpty ? defaultOrder : sortOrder } set: { sortOrder = $0 }
    }

    private var ordered: [IndexRow] {
        let order = sortOrder.isEmpty ? defaultOrder : sortOrder
        if place == .types { return IndexRows.nested(rows, by: order) }
        return rows.sorted(using: order + [KeyPathComparator(\IndexRow.title, comparator: .localizedStandard)])
    }

    var body: some View {
        let ordered = ordered
        table(ordered)
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .softSelection(rows: ordered.map(\.id), hovers: true, selection: { chosen })
            .quietTableHeader()
            .topRowTable()
            .scrollContentBackground(.hidden)
            .focused(pane, equals: .list)
            .takesKeyboardOnClick { browser.focusRequest = .list }
            .contextMenu(forSelectionType: Place.self) { ids in
                if ids.count == 1, let row = ordered.first(where: { ids.contains($0.id) }) { menu(for: row) }
            } primaryAction: { ids in
                if let row = ordered.first(where: { ids.contains($0.id) }) { open(row) }
            }
            .onKeyPress(.return) {
                guard let row = chosenRow(in: ordered) else { return .ignored }
                open(row)
                return .handled
            }
            .onDeleteCommand {
                if let row = chosenRow(in: ordered), canDelete(row) { ask(row) }
            }
            .contentMargins(.horizontal, PlaceIndexMetrics.side, for: .scrollContent)
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
            .alert("Rename Collection", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }, presenting: renaming) { row in
                TextField("Name", text: $newName)
                Button("Rename") { rename(row) }
                Button("Cancel", role: .cancel) {}
            }
            // A row that goes, deleted here or elsewhere, is no longer chosen.
            .onChange(of: rows) { if let chosen, !rows.contains(where: { $0.id == chosen }) { self.chosen = nil } }
            .accessibilityIdentifier("PlaceIndexTable")
    }

    @ViewBuilder
    private func table(_ ordered: [IndexRow]) -> some View {
        switch place {
        case .types:
            Table(ordered, selection: $chosen, sortOrder: sortBinding) {
                TableColumn("Name", value: \.title, comparator: .localizedStandard) { row in
                    PlaceIndexName(row: row, tinted: true).padding(.leading, CGFloat(row.depth) * PlaceIndexMetrics.nesting).tableCellRoom()
                }
                .width(min: 180, ideal: 420)
                TableColumn("Items", value: \.count) { row in PlaceIndexCount(count: row.count) }
                    .width(min: 76, ideal: 96, max: 140)
                    .alignment(.numeric)
                TableColumn("Views", value: \.views) { row in
                    Group {
                        if row.views > 0 { Text("^[\(row.views) view](inflect: true)").foregroundStyle(.secondary) }
                    }
                    .tableCellRoom()
                }
                .width(min: 80, ideal: 120, max: 160)
                TableColumn("Latest", value: \.latestOrOldest) { row in PlaceIndexLatest(date: row.latest) }
                    .width(min: 100, ideal: 140, max: 200)
            }
        case .collections:
            Table(ordered, selection: $chosen, sortOrder: sortBinding) {
                TableColumn("Name", value: \.title, comparator: .localizedStandard) { row in
                    PlaceIndexName(row: row, tinted: false).tableCellRoom()
                }
                .width(min: 180, ideal: 480)
                TableColumn("Items", value: \.count) { row in PlaceIndexCount(count: row.count) }
                    .width(min: 76, ideal: 96, max: 140)
                    .alignment(.numeric)
                TableColumn("Source", value: \.sourceName, comparator: .localizedStandard) { row in
                    Text(verbatim: row.sourceName).foregroundStyle(.secondary).lineLimit(1).tableCellRoom()
                }
                .width(min: 100, ideal: 200)
                TableColumn("Edited", value: \.latestOrOldest) { row in PlaceIndexLatest(date: row.latest) }
                    .width(min: 100, ideal: 140, max: 200)
            }
        default:
            Table(ordered, selection: $chosen, sortOrder: sortBinding) {
                TableColumn("Source", value: \.title, comparator: .localizedStandard) { row in
                    PlaceIndexName(row: row, tinted: false).tableCellRoom()
                }
                .width(min: 160, ideal: 360)
                TableColumn("Kind", value: \.kindTitle, comparator: .localizedStandard) { row in
                    Text(verbatim: row.kindTitle).foregroundStyle(.secondary).lineLimit(1).tableCellRoom()
                }
                .width(min: 80, ideal: 120, max: 160)
                TableColumn("Writes", value: \.writes.count) { row in PlaceIndexWrites(shares: row.writes).tableCellRoom() }
                    .width(min: 160, ideal: 340)
                TableColumn("Items", value: \.count) { row in PlaceIndexCount(count: row.count) }
                    .width(min: 76, ideal: 96, max: 140)
                    .alignment(.numeric)
                TableColumn("Latest", value: \.latestOrOldest) { row in PlaceIndexLatest(date: row.latest) }
                    .width(min: 100, ideal: 140, max: 200)
            }
        }
    }

    // MARK: The row's menu

    @ViewBuilder
    private func menu(for row: IndexRow) -> some View {
        Group {
            Button("Open", systemImage: "arrow.up.right.square") { open(row) }
            Button("Open in New Window", systemImage: "macwindow") { openInNewWindow(row) }
            Divider()
            if let type = row.typeID, let made = newTitle(of: type) {
                Button(made, systemImage: "square.and.pencil") { browser.openNewItem(kind: type.rawValue, in: library) }
            }
            if row.sourceCode == nil {
                Button("New View…", systemImage: "plus") { newView(on: row) }
                    .disabled(!library.reachesServer)
            }
            Divider()
            Button("Add to Sidebar", systemImage: "pin") { addToSidebar(row) }
            if let id = row.collectionID {
                Button("Copy Link", systemImage: "link") { Task { await library.copyLink(of: id) } }
            }
            if let code = row.sourceCode {
                Button("Copy Code", systemImage: "doc.on.doc") { copy(code) }
            }
            if let type = row.typeID {
                Divider()
                Button("Edit Type…", systemImage: "slider.horizontal.3") { editType(type, named: row.title) }
            }
            if let code = row.sourceCode {
                Divider()
                Button("Rename…", systemImage: "pencil") { editing = SourceEditRequest(code: code, mode: .name) }
                Button("Choose Mark…", systemImage: "face.smiling") { editing = SourceEditRequest(code: code, mode: .mark) }
            }
            if row.collectionID != nil {
                Divider()
                Button("Rename…", systemImage: "pencil") { askRename(row) }
                    .disabled(!canRename(row))
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive) { ask(row) }
                    .disabled(!canDelete(row))
            }
        }
        // On macOS a menu item draws its symbol only when the menu asks for it.
        .labelStyle(.titleAndIcon)
    }

    private func chosenRow(in ordered: [IndexRow]) -> IndexRow? {
        chosen.flatMap { chosen in ordered.first { $0.id == chosen } }
    }

    private func open(_ row: IndexRow) {
        browser.show(PlaceView(row.place), in: library, order: order)
    }

    private func openInNewWindow(_ row: IndexRow) {
        PlaceWindows.ask(PlaceView(row.place))
        openWindow(id: MarfaMacApp.mainWindowID)
    }

    /// New and the type’s name, where a new item can be one.
    private func newTitle(of type: TypeID) -> String? {
        guard QuickAdd.isAvailable(in: library), QuickAdd.types(in: library).contains(where: { $0.id == type }) else { return nil }
        return String(localized: "New \(library.catalogue.label(for: type))")
    }

    /// A new view starts at the place it is made for, which the window shows first.
    private func newView(on row: IndexRow) {
        browser.show(PlaceView(row.place), in: library, order: order)
        browser.openNewViewPanel(in: library)
    }

    private func addToSidebar(_ row: IndexRow) {
        let place: SidebarPlace? = switch row.place {
        case .type(let type): .type(type.rawValue)
        case .collection(let id): .collection(id)
        case .source(let code): .source(code)
        default: nil
        }
        guard let place else { return }
        libraries.updateSidebarLayout { $0.put(place, in: SidebarGroup.pinnedID) }
    }

    private func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private func editType(_ type: TypeID, named title: String) {
        browser.showSettings(.types, subpage: SettingsSubpage(id: "type:" + type.rawValue, title: title))
    }

    // MARK: A collection

    private func canRename(_ row: IndexRow) -> Bool {
        guard let id = row.collectionID, let item = library.item(id) else { return false }
        return !row.readOnly && library.canSetTitle(of: item)
    }

    private func canDelete(_ row: IndexRow) -> Bool { row.collectionID != nil && !row.readOnly }

    private func askRename(_ row: IndexRow) {
        guard canRename(row) else { return }
        newName = row.title
        renaming = row
    }

    private func rename(_ row: IndexRow) {
        let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = row.collectionID, !title.isEmpty, title != row.title else { return }
        _ = library.setItemProperty(id, key: "title", value: .string(title), undoManager: undoManager)
    }

    private func ask(_ row: IndexRow) {
        guard canDelete(row) else { return }
        deletingTitle = row.title
        deleting = row
    }

    /// Removes the collection and no member: a collection's members hold their own edges to it, and those stay, so Undo,
    /// or Recently Deleted, brings the collection back with its members.
    private func delete(_ row: IndexRow) {
        guard canDelete(row), let id = row.collectionID else { return }
        library.deleteAfterSaving([id], undoManager: undoManager, asking: details, naming: row.title)
    }
}

// MARK: Cells

/// A place's mark and name. A type's mark has the type's color; a collection's and a source's are gray.
private struct PlaceIndexName: View {
    @Environment(\.colorScheme) private var scheme
    let row: IndexRow
    let tinted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if tinted, case .type(let icon) = row.icon {
                    TypeGlyph(id: icon).foregroundStyle(TypeTone(icon: icon).color(for: scheme))
                } else {
                    RowIconImage(icon: row.icon).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: PlaceIndexMetrics.icon * 0.8))
            .frame(width: PlaceIndexMetrics.icon, height: PlaceIndexMetrics.icon)
            .accessibilityHidden(true)
            Text(verbatim: row.title).lineLimit(1)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

private struct PlaceIndexCount: View {
    let count: Int

    var body: some View {
        Text(count, format: .number).monospacedDigit().tableCellRoom(alignment: .trailing)
            .padding(.trailing, PlaceIndexMetrics.countRoom)
    }
}

/// A latest change as every table's date column reads it (`DateDisplay.Place.table`), so the time of a change today moves
/// to a day at midnight.
private struct PlaceIndexLatest: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var format = DateFormat.standard
    @State private var daysSeen = 0
    let date: Date?

    var body: some View {
        let _ = daysSeen
        Group {
            if let date {
                Text(verbatim: DateDisplay.text(of: date, hasTime: true, place: .table, format: format, now: library.now()))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.secondary)
        .tableCellRoom()
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
    }
}

/// The types a source writes, each its mark and name, three and then how many more.
private struct PlaceIndexWrites: View {
    let shares: [TypeShare]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(shares.prefix(PlaceIndexMetrics.writesShown)) { share in
                MarkedName(text: share.label, icon: share.icon, size: .row)
            }
            if shares.count > PlaceIndexMetrics.writesShown {
                Text(verbatim: "+\(shares.count - PlaceIndexMetrics.writesShown)").foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}
