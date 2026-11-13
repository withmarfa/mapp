import AppKit
import SwiftUI

/// A place's items as a table, in the manner of a database view: a row for each item, a column for each field its
/// type has, and the place's own grouping, sort and filters from its toolbar (`ItemTableViewOptions`). Selecting a row shows it in Details, and
/// opening one shows its page in the table's place, as the gallery does.
struct ItemTable: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.openWindow) private var openWindow
    @Bindable var browser: Browser
    let order: NoteOrder
    var pane: FocusState<Browser.Pane?>.Binding
    /// Each place's columns as the person arranged them: shown or hidden, in their order, at their widths.
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()
    /// What this Mac keeps for each saved view, whose column widths the table records (`Browser.keepWidths`).
    @AppStorage(ViewLayouts.key) private var viewLayouts = ViewLayouts()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @State private var daysSeen = 0
    @State private var hover = ItemTableHover()
    @State private var placeTrace = TablePlaceTrace()

    /// Where the table's first column starts: the inset style's own margin, measured from the table's edge. The filter
    /// chips, the group names and Load More line up here, so the table reads as one left edge.
    static let leadingEdge: CGFloat = 16

    var body: some View {
        let _ = daysSeen
        let _ = placeTrace.bodyRan(for: browser.item)
        let content = browser.tableContent(in: library)
        let (allRows, rows) = (content.allRows, content.rows)
        let pages = Pages(content: content, paging: browser.tablePaging, size: browser.tablePageSize)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        table(columns: content.columns, pages: pages, grouping: content.grouping, collapsed: content.collapsed)
            .searchStatus(browser)
            .overlay {
                if allRows.isEmpty {
                    if browser.isSearching {
                        SearchEmptyState(browser: browser)
                    } else {
                        EmptyState("No Items")
                    }
                } else if rows.isEmpty {
                    EmptyState(title: Text("No Matching Items"), detail: Text("No items match the filters.")) {
                        Button("Clear Filters") { browser.tableOptions[browser.item, default: .init()].clearFilters() }
                    }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle(shown: rows.count, of: allRows.count).editedSubtitle(browser.hasViewChanges))
            .toolbar(removing: browser.isSearchExpanded ? .title : nil)
            .onChange(of: browser.isSearchExpanded) {
                if !browser.isSearchExpanded { browser.focusRequest = .list }
            }
            // A row the selection names that is not loaded yet, such as one reached by Back or a link, loads its page.
            .onChange(of: browser.selection, initial: true) { browser.revealSelectionInTable(content) }
            .onChange(of: allRows.count) { browser.revealSelectionInTable(content) }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
            }
    }

    private func table(
        columns: [ItemTableColumn], pages: Pages, grouping: ItemTableColumn?, collapsed: Set<String>
    ) -> some View {
        let isView = viewID != nil
        return Table(of: ItemTableRow.self, selection: $browser.selection, sortOrder: sortBinding(columns), columnCustomization: customization(columns)) {
            // Only the columns showing. SwiftUI adds and hides every column it is given on live rows when the place
            // changes, which for the many columns of a mixed place costs far more than the few it shows.
            TableColumnForEach(browser.shownColumns(columns, stored: storedColumns)) { column in
                TableColumn(Text(verbatim: column.label), sortUsing: ItemTableComparator(column: column, order: column.firstOrder)) { row in
                    ItemTableCell(library: library, row: row, column: column, browser: browser, order: order, dateFormat: dateFormat, hover: hover)
                }
                .width(min: column.widths.min, ideal: column.widths.ideal, max: column.widths.max)
                .customizationID(column.id)
                // A view's order is the panel's to change, since the header cannot hold an arrangement Save waits for.
                .disabledCustomizationBehavior(Self.disabledCustomization(of: column, inView: isView))
            }
        } rows: {
            if let grouping {
                ForEach(pages.groups) { groupRows($0, grouping: grouping, collapsed: collapsed) }
            } else {
                ForEach(pages.slice.rows) { TableRow($0) }
                if pages.slice.remaining > 0 {
                    loadMoreRow(remaining: pages.slice.remaining, group: nil)
                }
            }
        }
        .tableStyle(.inset)
        .onChange(of: browser.panelIsOut) { _, isOut in if isOut { hover.clear() } }
        .softSelection(rows: pages.shownIDs + collapsed.sorted(), selection: { browser.selection })
        .remembersScroll(in: browser.listMemory)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
        .accessibilityIdentifier("ItemTable")
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if !ids.isEmpty {
                Button("Open") { open(ids) }
                    .disabled(ids.count != 1)
                Button("Open in New Window", systemImage: "macwindow") {
                    ItemWindows.open(library.idsForWindows(ids)) { openWindow(value: $0) }
                }
                Divider()
                NoteActions(ids: ids, undoManager: undoManager)
            }
        } primaryAction: { ids in
            open(ids)
        }
        .quickLooksOnSpace(browser)
        .onKeyPress(.return) {
            guard browser.selection.count == 1 else { return .ignored }
            browser.openCollectionSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            browser.selection = []
            return .handled
        }
        .onDeleteCommand {
            let ids = browser.selection
            library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
        }
    }

    @TableRowBuilder<ItemTableRow>
    private func groupRows(_ page: Pages.GroupPage, grouping: ItemTableColumn, collapsed: Set<String>) -> some TableRowContent<ItemTableRow> {
        let id = page.group.id
        let isCollapsed = collapsed.contains(id)
        Section {
            if !isCollapsed {
                ForEach(page.slice.rows) { TableRow($0) }
            }
        } header: {
            ItemTableGroupHeader(group: page.group, column: grouping, isCollapsed: isCollapsed) { toggle(id, collapsed: collapsed) }
        }
        if page.slice.remaining > 0, !isCollapsed {
            loadMoreRow(remaining: page.slice.remaining, group: id)
        }
    }

    @TableRowBuilder<ItemTableRow>
    private func loadMoreRow(remaining: Int, group: String?) -> some TableRowContent<ItemTableRow> {
        Section {
            ForEach([ItemTableRow]()) { TableRow($0) }
        } header: {
            ItemTableLoadMore(remaining: remaining) { browser.loadMoreTableRows(group: group) }
        }
    }

    private func open(_ ids: Set<ItemID>) {
        guard ids.count == 1 else { return }
        browser.selection = ids
        browser.openCollectionSelection()
    }

    private func toggle(_ group: String, collapsed: Set<String>) {
        var next = collapsed
        if next.contains(group) { next.remove(group) } else { next.insert(group) }
        browser.tableOptions[browser.item, default: .init()].collapsed = next
    }

    /// What the header may not do with a column: the name always shows, and a view's order is the panel's to change,
    /// since the header cannot hold an arrangement Save waits for. One call sets the whole set, as a second would
    /// replace the first.
    static func disabledCustomization(of column: ItemTableColumn, inView isView: Bool) -> TableColumnCustomizationBehavior {
        var disabled: TableColumnCustomizationBehavior = []
        if column.content == .title { disabled.insert(.visibility) }
        if isView { disabled.insert(.reorder) }
        return disabled
    }

    /// How many items show, and of how many once a filter hides some.
    private func subtitle(shown: Int, of count: Int) -> Text {
        if browser.isSearching { return Text("^[\(count) result](inflect: true)") }
        return shown == count ? Text("^[\(count) item](inflect: true)") : Text("\(shown) of \(count) items")
    }

    /// The header's sort: a click puts its column first, and only the last few columns clicked are kept.
    private func sortBinding(_ columns: [ItemTableColumn]) -> Binding<[ItemTableComparator]> {
        Binding {
            browser.ordersByRelevance ? [] : ItemTableLayout.sort(
                browser.tableOptions[browser.item] ?? ItemTableOptions(), columns: columns, keepsGivenOrder: browser.keepsPlaceOrder)
        } set: { sort in
            if !sort.isEmpty { browser.orderSearch(byRelevance: false) }
            browser.tableOptions[browser.item, default: .init()].sort = Array(sort.prefix(ViewDraft.maxSortKeys))
        }
    }

    // MARK: Column layouts

    private var viewID: ItemID? {
        if case .view(let id) = browser.item { id } else { nil }
    }

    /// The table's column widths, which a place keeps for itself and a saved view keeps on its own. The table reads and
    /// writes it directly, so a change of place never shows the previous place's columns. A saved view's shown
    /// columns and their order are the window's (`ViewColumns`), so a header that hides one is routed there, and what is
    /// left for the table to keep is the widths alone.
    private func customization(_ columns: [ItemTableColumn]) -> Binding<TableColumnCustomization<ItemTableRow>> {
        Binding {
            guard let id = viewID else { return ItemTableColumnLayouts.layout(for: browser.item, in: storedColumns) }
            return viewLayouts.settings(for: id)?.widths.flatMap { try? JSONDecoder().decode(TableColumnCustomization<ItemTableRow>.self, from: $0) }
                ?? .init()
        } set: { next in
            guard let id = viewID else {
                storedColumns = ItemTableColumnLayouts.storing(next, for: browser.item, in: storedColumns)
                return
            }
            var widths = next
            for column in columns where column.content != .title && widths[visibility: column.id] == .hidden {
                browser.changeViewSettings(id) { $0.columns.setShown(column, false) }
                widths[visibility: column.id] = .automatic
            }
            widths.resetOrder()
            browser.keepWidths(try? JSONEncoder().encode(widths), of: id)
        }
    }
}

/// Times what a table costs when it shows another place: from the first pass that builds it for the place until the
/// main queue is free again, which is the pause a person feels. The signpost is `table.place`, in `navigation`. The
/// table's first pass only notes the place: a table that has just been mounted, by switching from the list or the
/// gallery or by launching, is a layout change, which is not a place change.
@MainActor
private final class TablePlaceTrace {
    private var place: SidebarItem?
    private var current: (id: Int, interval: Telemetry.Interval)?
    private var counter = 0

    func bodyRan(for place: SidebarItem) {
        guard place != self.place else { return }
        let isMount = self.place == nil
        self.place = place
        current?.interval.end()
        current = nil
        guard !isMount else { return }
        counter += 1
        let id = counter
        current = (id, Telemetry.begin(.navigation, "table.place"))
        // The pass that updates the table runs when the runloop is about to wait, so this block comes after it. It
        // ends only the interval it began, not one a later change has begun since.
        DispatchQueue.main.async { [weak self] in
            guard let self, current?.id == id else { return }
            current?.interval.end()
            current = nil
        }
    }
}

/// Each place's columns as the person arranged them (shown or hidden, in their order, at their widths), kept
/// together in the defaults under one key.
enum ItemTableColumnLayouts {
    static let key = "itemTableColumns"

    static func key(for place: SidebarItem) -> String { place.storageKey }

    static func layout(for place: SidebarItem, in stored: Data) -> TableColumnCustomization<ItemTableRow> {
        layouts(in: stored)[key(for: place)] ?? .init()
    }

    static func storing(_ layout: TableColumnCustomization<ItemTableRow>, for place: SidebarItem, in stored: Data) -> Data {
        var layouts = layouts(in: stored)
        layouts[key(for: place)] = layout
        return (try? JSONEncoder().encode(layouts)) ?? stored
    }

    /// The columns the table is given: those the layout shows, and always the name. A hidden column stays out of the
    /// table, so its width and place in the order wait in the layout and come back when the Columns menu shows it.
    static func shown(_ columns: [ItemTableColumn], in layout: TableColumnCustomization<ItemTableRow>) -> [ItemTableColumn] {
        columns.filter { $0.content == .title || layout.shows($0) }
    }

    private static func layouts(in stored: Data) -> [String: TableColumnCustomization<ItemTableRow>] {
        (try? JSONDecoder().decode([String: TableColumnCustomization<ItemTableRow>].self, from: stored)) ?? [:]
    }
}

extension ItemTableColumn {
    /// How wide the column starts and how far it can be dragged: wide for the name and for prose, narrow for marks.
    var widths: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch style {
        case .title: (240, 420, 800)
        case .status: (110, 140, 220)
        case .priority: (90, 110, 160)
        case .choice, .text: (90, 150, 320)
        case .longText: (160, 280, 900)
        case .date: (90, 116, 200)
        case .duration: (70, 92, 140)
        case .number: (60, 90, 160)
        case .boolean: (50, 70, 120)
        case .link: (120, 200, 360)
        }
    }
}

/// A group's header row: its mark and name, how many it holds, and a chevron that folds it away. The name starts at the
/// table's left edge, where the rows' marks do, and the chevron hangs in the margin to its left.
private struct ItemTableGroupHeader: View {
    let group: ItemTableGroup
    let column: ItemTableColumn
    let isCollapsed: Bool
    let toggle: () -> Void

    private static let gap: CGFloat = 4

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Self.gap) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: ItemTable.leadingEdge - Self.gap)
                ItemTableCategory(column: column, value: group.value, title: group.title, isGroup: true)
                    .fontWeight(.semibold)
                Text(group.rows.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            // The cell starts at the edge, so the chevron's width and gap bring it back to the table's own.
            .padding(.leading, -ItemTable.leadingEdge)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .interfaceFont(.body)
        .accessibilityLabel(Text("\(group.title), \(group.rows.count)"))
        .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
        .accessibilityHint(isCollapsed ? Text("Shows the group’s items") : Text("Hides the group’s items"))
    }
}

/// The rows the table draws: a page of them, or a page of each group.
private struct Pages {
    struct GroupPage: Identifiable {
        let group: ItemTableGroup
        let slice: TablePaging.Slice
        var id: String { group.id }
    }

    /// The page of an ungrouped table.
    let slice: TablePaging.Slice
    let groups: [GroupPage]

    @MainActor
    init(content: ItemTableContent, paging: TablePaging, size: TablePageSize) {
        if content.grouping == nil {
            slice = paging.slice(content.rows, size: size)
            groups = []
        } else {
            slice = TablePaging.Slice(rows: [], remaining: 0)
            groups = content.groups.map { GroupPage(group: $0, slice: paging.slice($0.rows, size: size, group: $0.id)) }
        }
    }

    var shownIDs: [String] {
        (slice.rows + groups.flatMap(\.slice.rows)).map(\.id.rawValue)
    }
}

/// The row at the foot of a table, or of a group, that shows the next page. It reads as a quiet row, as Notion's
/// does, and is a button, so the keyboard and VoiceOver can reach it.
private struct ItemTableLoadMore: View {
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Load More")
                Text("\(remaining) remaining")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .interfaceFont(.body)
        .accessibilityLabel(Text("Load More, \(remaining) remaining"))
        .accessibilityIdentifier("ItemTableLoadMore")
    }
}
