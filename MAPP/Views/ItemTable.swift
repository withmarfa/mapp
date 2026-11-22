import AppKit
import SwiftUI

/// A place's items as a table, in the manner of a database view: a row for each item, a column for each field its
/// type has, and the place's own grouping, sort and filters from its toolbar (`ItemTableViewOptions`). Selecting a row shows it in Details, and
/// opening one shows its page in the table's place, as the gallery does.
struct ItemTable: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Bindable var browser: Browser
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    /// Each place's columns as the person arranged them: shown or hidden, in their order, at their widths.
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()
    /// What this Mac keeps for each saved view, whose column widths the table records (`Browser.keepWidths`).
    @AppStorage(ViewLayouts.key) private var viewLayouts = ViewLayouts()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @State private var daysSeen = 0
    /// Whether rows have scrolled up past the headings, under the toolbar.
    @State private var isUnderToolbar = false
    @State private var hover = ItemTableHover()
    @State private var placeTrace = TablePlaceTrace()

    /// The inset style's own margin before the first column.
    static let inset: CGFloat = 16
    /// The room the table leaves at each side of the pane, so a group's chevron, which hangs in the margin, sits inside
    /// the window and a selected row's highlight stops short of its edge.
    static let margin: CGFloat = 8
    /// Where the table's first column starts, measured from the pane's edge. The filter chips, the group names and
    /// Load More line up here, so the table reads as one left edge.
    static let leadingEdge: CGFloat = inset + margin

    var body: some View {
        let _ = daysSeen
        let _ = placeTrace.bodyRan(for: browser.item)
        let content = tableContent()
        let (allRows, rows) = (content.allRows, content.rows)
        let pages = Pages(content: content, paging: browser.tablePaging, size: browser.tablePageSize)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        table(columns: content.columns, pages: pages, grouping: content.grouping, collapsed: content.collapsed)
            .padding(.horizontal, Self.margin)
            .searchStatus(browser)
            .overlay {
                if allRows.isEmpty {
                    if browser.isSearching {
                        SearchEmptyState(browser: browser)
                    } else {
                        PlaceEmptyState(browser: browser)
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

    /// The table's content, with its rows holding the links of the columns the person shows. A link column that was hidden
    /// before needs its rows made again, once.
    private func tableContent() -> ItemTableContent {
        let content = browser.tableContent(in: library)
        guard browser.showRelations(of: browser.shownColumns(content.columns, stored: storedColumns)) else { return content }
        return browser.tableContent(in: library)
    }

    private func table(
        columns: [ItemTableColumn], pages: Pages, grouping: ItemTableColumn?, collapsed: Set<String>
    ) -> some View {
        let isView = viewID != nil
        return Table(of: ItemTableRow.self, selection: $browser.selection, sortOrder: sortBinding(columns), columnCustomization: customization(columns)) {
            // Only the columns showing. SwiftUI adds and hides every column it is given on live rows when the place
            // changes, which for the many columns of a mixed place costs far more than the few it shows.
            TableColumnForEach(browser.shownColumns(columns, stored: storedColumns)) { column in
                tableColumn(column, isView: isView)
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
        .softSelection(rows: pages.shownIDs + collapsed.sorted(), hovers: true, inert: pages.headerPlaces(collapsed: collapsed), selection: { browser.selection })
        .quietTableHeader(isUnderToolbar: $isUnderToolbar)
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBand(isUnderToolbar: isUnderToolbar)
        .remembersScroll(in: browser.listMemory)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
        .accessibilityIdentifier("ItemTable")
        .contextMenu(forSelectionType: ItemID.self) { ids in
            ItemRowMenu(browser: browser, ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            browser.open(ids)
        }
        .quickLooksOnSpace(browser)
        .onKeyPress(.return) {
            browser.openSelection() ? .handled : .ignored
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

    /// A count has no sort control: it is asked for only the rows on screen (`ItemTableColumn.isSortable`).
    @TableColumnBuilder<ItemTableRow, ItemTableComparator>
    private func tableColumn(_ column: ItemTableColumn, isView: Bool) -> some TableColumnContent<ItemTableRow, ItemTableComparator> {
        if column.isSortable {
            TableColumn(Text(verbatim: column.label), sortUsing: ItemTableComparator(column: column, order: column.firstOrder)) { row in
                cell(of: row, in: column)
            }
            .width(min: column.widths.min, ideal: column.widths.ideal, max: column.widths.max)
            .customizationID(column.id)
            // A view's order is the panel's to change, since the header cannot hold an arrangement Save waits for.
            .disabledCustomizationBehavior(Self.disabledCustomization(of: column, inView: isView))
        }
        if !column.isSortable {
            TableColumn(Text(verbatim: column.label)) { row in
                cell(of: row, in: column)
            }
            .width(min: column.widths.min, ideal: column.widths.ideal, max: column.widths.max)
            .customizationID(column.id)
            .disabledCustomizationBehavior(Self.disabledCustomization(of: column, inView: isView))
        }
    }

    private func cell(of row: ItemTableRow, in column: ItemTableColumn) -> some View {
        ItemTableCell(library: library, row: row, column: column, browser: browser, order: order, dateFormat: dateFormat, hover: hover)
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
                storedColumns = ItemTableColumnLayouts.storing(
                    next, for: browser.item, in: storedColumns, setAsideIn: browser.defaults)
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
///
/// Stored data that cannot be read is never written over: a change that would replace it moves it aside under a key of its
/// own first (`setAsideKey`), and a Reset View leaves it as it is.
enum ItemTableColumnLayouts {
    static let key = "itemTableColumns"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "itemTableColumnsSetAside"

    static func key(for place: SidebarItem) -> String { place.storageKey }

    static func layout(for place: SidebarItem, in stored: Data) -> TableColumnCustomization<ItemTableRow> {
        layouts(in: stored)?[key(for: place)] ?? .init()
    }

    /// Whether the person arranged the place's columns: an entry with nothing in it is the table's own arrangement.
    static func isChanged(for place: SidebarItem, in stored: Data) -> Bool {
        layouts(in: stored)?[key(for: place)].map { $0 != .init() } ?? false
    }

    /// The stored layouts without the place's, so its table starts again from its own columns. Data that cannot be read
    /// holds no layout of the place to remove, so it comes back as it was.
    static func removing(_ place: SidebarItem, in stored: Data) -> Data {
        guard var layouts = layouts(in: stored), layouts[key(for: place)] != nil else { return stored }
        layouts[key(for: place)] = nil
        return (try? JSONEncoder().encode(layouts)) ?? stored
    }

    /// The stored layouts with the place's changed. Data that cannot be read is kept aside in `defaults` first, since the
    /// layouts then start again from this one.
    static func storing(
        _ layout: TableColumnCustomization<ItemTableRow>, for place: SidebarItem, in stored: Data,
        setAsideIn defaults: UserDefaults = .standard
    ) -> Data {
        var layouts = layouts(in: stored)
        if layouts == nil {
            defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [stored], forKey: setAsideKey)
            layouts = [:]
        }
        layouts?[key(for: place)] = layout
        return (try? JSONEncoder().encode(layouts)) ?? stored
    }

    /// The columns the table is given: those the layout shows, and always the name. A hidden column stays out of the
    /// table, so its width and place in the order wait in the layout and come back when the Columns menu shows it.
    static func shown(_ columns: [ItemTableColumn], in layout: TableColumnCustomization<ItemTableRow>) -> [ItemTableColumn] {
        columns.filter { $0.content == .title || layout.shows($0) }
    }

    /// The stored layouts: none where nothing is stored, and nil where what is stored cannot be read.
    private static func layouts(in stored: Data) -> [String: TableColumnCustomization<ItemTableRow>]? {
        if stored.isEmpty { return [:] }
        return try? JSONDecoder().decode([String: TableColumnCustomization<ItemTableRow>].self, from: stored)
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
        case .date: (90, 116, 200)
        case .duration: (70, 92, 140)
        case .number: (60, 90, 160)
        case .count: (80, 110, 180)
        case .boolean: (50, 70, 120)
        case .link, .links: (120, 200, 360)
        }
    }
}

/// A group's header row: its mark and name, how many it holds, and a chevron that folds it away. The name starts at the
/// table's left edge, where the rows' marks do, and the chevron hangs in the margin to its left. Only the chevron is
/// a control, so only it reacts to the pointer; the rest of the row is a heading and does nothing.
private struct ItemTableGroupHeader: View {
    let group: ItemTableGroup
    let column: ItemTableColumn
    let isCollapsed: Bool
    let toggle: () -> Void
    @State private var isOverChevron = false

    private static let gap: CGFloat = 2
    private static let chevronWidth: CGFloat = 10

    var body: some View {
        HStack(spacing: Self.gap) {
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOverChevron ? .secondary : .tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: Self.chevronWidth)
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.primary.opacity(isOverChevron ? 0.047 : 0))
                            .padding(-5)
                    }
                    .contentShape(.rect.inset(by: -5))
            }
            .buttonStyle(.plain)
            .onHover { isOverChevron = $0 }
            .accessibilityLabel(Text("\(group.title), \(group.rows.count)"))
            .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
            .accessibilityHint(isCollapsed ? Text("Shows the group’s items") : Text("Hides the group’s items"))
            ItemTableCategory(column: column, value: group.value, title: group.title, isGroup: true)
                .fontWeight(.semibold)
            Text(group.rows.count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        // The cell starts at the inset style's margin, so the chevron's width and gap bring the name back to it.
        .padding(.leading, -(Self.chevronWidth + Self.gap))
        .interfaceFont(.body)
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

    /// Where the groups' header rows fall among the table's rows: each group's header, then its rows unless it is
    /// folded, then its Load More row while it has more to show.
    func headerPlaces(collapsed: Set<String>) -> Set<Int> {
        var places: Set<Int> = []
        var place = 0
        for page in groups {
            places.insert(place)
            place += 1
            if collapsed.contains(page.group.id) { continue }
            place += page.slice.rows.count + (page.slice.remaining > 0 ? 1 : 0)
        }
        return places
    }
}

/// The row at the foot of a table, or of a group, that shows the next page. It reads as a quiet row, as Notion's
/// does, and is a button, so the keyboard and VoiceOver can reach it.
struct ItemTableLoadMore: View {
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
