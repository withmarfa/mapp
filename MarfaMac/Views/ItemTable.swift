import AppKit
import SwiftUI
import os

/// A place's items as a table, in the manner of a database view: a row for each item, a column for each field its
/// type has, and the place's own grouping, sort and filters from the View panel (`ViewPanelPopover`). Selecting a row shows it in Details, and
/// opening one shows its page in the table's place, as the gallery does. Choosing a row runs the table that holds the
/// selection, not this body, which pages the place.
struct ItemTable: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    /// Where the title stands, past the traffic lights while the sidebar is closed (`TopRowSpace.titleLead`), which the
    /// first column starts at.
    @Environment(\.topRowSpace.titleLead) private var titleLead
    /// Each place's column widths, as the person dragged them. The columns shown and their order are the Properties list's.
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()
    /// What this Mac keeps for each saved view, whose column widths the table records (`Browser.keepWidths`).
    @AppStorage(ViewLayouts.key) private var viewLayouts = ViewLayouts()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @State private var daysSeen = 0
    @State private var hover = ItemTableHover()
    @State private var placeTrace = TablePlaceTrace()
    /// The column widths last decoded, so a click does not decode them again.
    @State private var widthCache = ColumnWidthCache()
    /// Whether a person is dragging a column's divider, the only time the table stores a width.
    @State private var resizing = ColumnResizing()
    /// Where each row was last drawn, which the row under the pointer or the keyboard's is held at (`RowHold`).
    @State private var drawn = DrawnRows()
    /// The width inside the table's margin, which decides how many columns fit (`ItemTableRoom`); 0 until measured.
    @State private var tableWidth: CGFloat = 0

    /// The inset style's own margin before the first column.
    static let inset: CGFloat = 16
    /// The room between one column and the next.
    static let columnGap: CGFloat = 2
    /// With the inset, the first column starts where the title does and leaves room for group chevrons.
    private var margin: CGFloat { max(0, titleLead - Self.inset) }

    var body: some View {
        let _ = daysSeen
        let _ = placeTrace.bodyRan(for: browser.shown)
        Group {
            if let content = tableContent() { contents(content) }
            else { PlaceProgress() }
        }
        // The Archive names each item's source, which the server names after the items are read.
        .task(id: library.membershipRevision) { if browser.listsByOrigin { await library.refreshSources() } }
        .onClockChange { daysSeen += 1 }
    }

    private func contents(_ content: ItemTableContent) -> some View {
        let wanted = browser.shownColumns(content.columns)
        let fit = ItemTableFit.widths(
            of: wanted, rows: content.rows.prefix(ItemTableFit.sample), library: library, format: dateFormat, now: library.now(),
            scale: CGFloat(textSize) / CGFloat(InterfaceStyle.defaultTextSize))
        let shown = fitting(wanted, fit: fit)
        let (allRows, rows) = (content.allRows, content.rows)
        let _ = browser.rowHoldReleases
        let pages = Pages(
            content: content, paging: browser.tablePaging, size: browser.tablePageSize, expanded: browser.expandedHere,
            hold: &browser.rowHold)
        let _ = drawn.take(pages.anchors)

        return ItemTableSelection(browser: browser, content: content, drawn: drawn) { selection in
            table(selection: selection, columns: content.columns, shown: shown, fit: fit, pages: pages, grouping: content.grouping, collapsed: content.collapsed)
        }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tableWidth = $0 }
            .padding(.horizontal, margin)
            .searchStatus(browser)
            .overlay {
                if allRows.isEmpty {
                    if browser.narrowsBySearch {
                        SearchEmptyState(browser: browser)
                    } else {
                        PlaceEmptyState(browser: browser)
                    }
                } else if content.hidesEveryGroup {
                    HiddenGroupsEmptyState()
                } else if rows.isEmpty, browser.hasSearchTokens {
                    SearchEmptyState(browser: browser)
                } else if rows.isEmpty {
                    EmptyState(title: Text("No Matching Items"), detail: Text("No items match the filters.")) {
                        Button("Clear Filters") { browser.tableOptions[browser.shown, default: .init()].clearFilters() }
                    }
                }
            }
            .onChange(of: browser.isSearchExpanded) {
                if !browser.isSearchExpanded { browser.focusRequest = .list }
            }
            .onChange(of: allRows.count) { browser.revealSelectionInTable(content) }
            .background { PointerHold(hover: hover, browser: browser, drawn: drawn) }
            .onAppear { browser.restoreInPlace(.table(group: nil), in: library) }
            .onChange(of: browser.shown) { browser.restoreInPlace(.table(group: nil), in: library) }
    }

    /// The table's content, with its rows holding the links of the columns the person shows. A link column that was hidden
    /// before needs its rows made again, once.
    private func tableContent() -> ItemTableContent? {
        guard let content = browser.readyTable(in: library) else { return nil }
        guard browser.showRelations(of: browser.shownColumns(content.columns)) else { return content }
        return browser.readyTable(in: library)
    }

    private func table(
        selection: Binding<Set<ItemID>>, columns: [ItemTableColumn], shown: [ItemTableColumn], fit: [String: ItemTableFit.Width], pages: Pages,
        grouping: ItemTableColumn?, collapsed: Set<String>
    ) -> some View {
        let last = shown.last?.id
        return Table(of: ItemTableRow.self, selection: selection, sortOrder: sortBinding(columns), columnCustomization: customization(columns)) {
            // Only the columns showing. SwiftUI adds and hides every column it is given on live rows when the place
            // changes, which for the many columns of a mixed place costs far more than the few it shows.
            TableColumnForEach(shown) { column in
                tableColumn(column, fit: fit[column.id], endsRow: column.id == last, places: pages.places)
            }
        } rows: {
            if let grouping {
                ForEach(pages.groups) { groupRows($0, grouping: grouping, collapsed: collapsed) }
            } else {
                ForEach(pages.slice.rows) { TableRow($0) }
            }
            ForEach(pages.trailing) { TableRow($0) }
            if browser.typesInPlace(in: library) {
                newRow()
            }
            if pages.remaining > 0 {
                loadMoreRow(remaining: pages.remaining)
            }
        }
        .tableStyle(.inset)
        .onChange(of: browser.panelIsOut) { _, isOut in if isOut { hover.clear() } }
        .softSelection(rows: pages.shownIDs + collapsed.sorted(), hovers: true, inert: pages.headerPlaces(collapsed: collapsed), selection: { browser.selection })
        .quietTableHeader(resizing: resizing)
        .topRowTable()
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
        .onKeyPress(.rightArrow) { foldSubItems(open: true, places: pages.places) }
        .onKeyPress(.leftArrow) { foldSubItems(open: false, places: pages.places) }
        .onDeleteCommand {
            let ids = browser.selection
            library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
        }
    }

    /// A count has no sort control: it is asked for only the rows on screen (`ItemTableColumn.isSortable`).
    @TableColumnBuilder<ItemTableRow, ItemTableComparator>
    private func tableColumn(
        _ column: ItemTableColumn, fit: ItemTableFit.Width?, endsRow: Bool, places: [ItemID: ItemNesting.Place]
    ) -> some TableColumnContent<ItemTableRow, ItemTableComparator> {
        let widths = (min: fit?.minimum ?? column.widths.min, ideal: fit?.ideal ?? column.widths.ideal, max: column.widths.max)
        if column.isSortable {
            TableColumn(Text(verbatim: column.label), sortUsing: ItemTableComparator(column: column, order: column.firstOrder)) { row in
                cell(of: row, in: column, endsRow: endsRow, place: places[row.id])
            }
            .width(min: widths.min, ideal: widths.ideal, max: widths.max)
            .customizationID(column.id)
            // The order is the Properties list's to change, which the header cannot hold.
            .disabledCustomizationBehavior(Self.disabledCustomization(of: column))
        }
        if !column.isSortable {
            TableColumn(Text(verbatim: column.label)) { row in
                cell(of: row, in: column, endsRow: endsRow, place: places[row.id])
            }
            .width(min: widths.min, ideal: widths.ideal, max: widths.max)
            .customizationID(column.id)
            .disabledCustomizationBehavior(Self.disabledCustomization(of: column))
        }
    }

    private func cell(of row: ItemTableRow, in column: ItemTableColumn, endsRow: Bool, place: ItemNesting.Place?) -> some View {
        var cell = ItemTableCell(library: library, row: row, column: column, browser: browser, order: order, dateFormat: dateFormat, hover: hover)
        cell.endsRow = endsRow
        if column.content == .title { cell.nest = place }
        return cell
    }

    /// The Right Arrow opens the chosen parent's sub-items and the Left Arrow closes them, or chooses the parent of a
    /// chosen sub-item, as an outline does.
    private func foldSubItems(open: Bool, places: [ItemID: ItemNesting.Place]) -> KeyPress.Result {
        guard browser.selection.count == 1, let id = browser.selection.first, let place = places[id] else { return .ignored }
        if place.children > 0, place.isExpanded != open {
            browser.toggleSubItems(of: id, in: library, order: order)
            return .handled
        }
        let nestings = browser.tableContent(in: library).nestings
        guard !open, let parent = nestings.lazy.compactMap({ $0.parents[id] }).first else { return .ignored }
        browser.selection = [parent]
        return .handled
    }

    @TableRowBuilder<ItemTableRow>
    private func groupRows(_ page: Pages.GroupPage, grouping: ItemTableColumn, collapsed: Set<String>) -> some TableRowContent<ItemTableRow> {
        let id = page.group.id
        let isCollapsed = collapsed.contains(id)
        Section {
            if !isCollapsed {
                ForEach(page.rows) { TableRow($0) }
            }
        } header: {
            ItemTableGroupHeader(group: page.group, column: grouping, isCollapsed: isCollapsed) { toggle(id, collapsed: collapsed) }
        }
    }

    /// The table's last row, New, which a new item is typed in (`InPlaceRow`).
    @TableRowBuilder<ItemTableRow>
    private func newRow() -> some TableRowContent<ItemTableRow> {
        Section {
            ForEach([ItemTableRow]()) { TableRow($0) }
        } header: {
            InPlaceTableRow(browser: browser, library: library, undoManager: undoManager)
        }
    }

    @TableRowBuilder<ItemTableRow>
    private func loadMoreRow(remaining: Int) -> some TableRowContent<ItemTableRow> {
        Section {
            ForEach([ItemTableRow]()) { TableRow($0) }
        } header: {
            ItemTableLoadMore(remaining: remaining) { browser.loadMoreTableRows() }
        }
    }

    private func toggle(_ group: String, collapsed: Set<String>) {
        var next = collapsed
        if next.contains(group) { next.remove(group) } else { next.insert(group) }
        browser.tableOptions[browser.shown, default: .init()].collapsed = next
    }

    /// What the header may not do with a column. The name always shows and stays first. Any other column can be hidden
    /// or reordered, and both write the Properties list. One call sets the whole set, as a second would replace the first.
    static func disabledCustomization(of column: ItemTableColumn) -> TableColumnCustomizationBehavior {
        column.content == .title ? [.visibility, .reorder] : []
    }

    /// The header's sort: a click puts its column first, and only the last few columns clicked are kept.
    private func sortBinding(_ columns: [ItemTableColumn]) -> Binding<[ItemTableComparator]> {
        Binding {
            browser.ordersByRelevance ? [] : ItemTableLayout.sort(
                browser.tableOptions[browser.shown] ?? ItemTableOptions(), columns: columns, keepsGivenOrder: browser.keepsPlaceOrder,
                listsByOrigin: browser.listsByOrigin)
        } set: { sort in
            if !sort.isEmpty { browser.orderSearch(byRelevance: false) }
            browser.tableOptions[browser.shown, default: .init()].sort = Array(sort.prefix(ViewDraft.maxSortKeys))
        }
    }

    // MARK: Column layouts

    private var viewID: ItemID? {
        if let id = browser.shown.savedView { id } else { nil }
    }

    /// The table's column widths, which a place keeps for itself and a saved view keeps on its own. The table reads and
    /// writes it directly, so a change of place never shows the previous place's columns. The shown columns and their
    /// order are the Properties list's (`ViewProperties`), so a header that hides or reorders one is routed there, and
    /// what is left for the table to keep is the widths alone.
    private func customization(_ columns: [ItemTableColumn]) -> Binding<TableColumnCustomization<ItemTableRow>> {
        Binding {
            Self.widthsOnly(decodedWidths(), columns)
        } set: { next in
            if let data = try? JSONEncoder().encode(next), let header = Self.headerOrder(in: data) {
                browser.changeProperties { $0.adoptHeaderOrder(header, in: columns) }
            }
            for column in columns where column.content != .title && next[visibility: column.id] == .hidden {
                browser.setColumn(column, shown: false)
            }
            // AppKit gives the columns widths of its own as the table appears and changes, which are not the person's.
            guard resizing.isDragging else { return }
            let widths = Self.widthsOnly(next, columns)
            guard let id = viewID else {
                storedColumns = ItemTableColumnLayouts.storing(widths, for: browser.shown, in: storedColumns, setAsideIn: browser.defaults)
                return
            }
            do {
                browser.keepWidths(try JSONEncoder().encode(widths), of: id)
            } catch {
                Telemetry.logger(.navigation).error("Could not encode the table column widths")
            }
        }
    }

    /// The columns that fit the table's width, in order. Tells the table's header what width each starts at, which is the
    /// width the person kept or one between the column's least and its ideal (`ItemTableRoom`, `ColumnResizing`).
    private func fitting(_ wanted: [ItemTableColumn], fit: [String: ItemTableFit.Width]) -> [ItemTableColumn] {
        let kept = (try? JSONEncoder().encode(decodedWidths())).map(Self.keptWidths(in:)) ?? [:]
        let title = ItemTableColumn.title.widths
        let parts = wanted.map { column in
            let isName = column.content == .title
            let own = kept[column.id]
            let ideal = own ?? fit[column.id]?.ideal ?? column.widths.ideal
            let least = own ?? (isName ? title.min : fit[column.id]?.minimum ?? column.widths.min)
            return ItemTableRoom.Column(id: column.id, isName: isName, minimum: least, ideal: ideal, isKept: own != nil)
        }
        // The inset style keeps its room before the first column and after the last, and the table a gap between columns.
        let plan = ItemTableRoom.plan(parts, available: tableWidth > 0 ? tableWidth - 2 * Self.inset : 0, gap: Self.columnGap)
        let widths = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.width) })
        let shown = wanted.filter { widths[$0.id] != nil }
        resizing.widths = shown.map { widths[$0.id] ?? 0 }
        // The name takes what the other columns leave, until a person drags its divider.
        resizing.flexible = shown.firstIndex { $0.content == .title && kept[$0.id] == nil }
        resizing.flexibleMinimum = title.min
        return shown
    }

    /// The stored widths for the place showing now. Decoded when the place or the stored data changes, and kept until
    /// then, so reading the binding does not decode again.
    private func decodedWidths() -> TableColumnCustomization<ItemTableRow> {
        let data: Data
        let place: String
        if let id = viewID {
            // A new view's draft made from the view keeps its own widths (`Browser.keepWidths`).
            data = (browser.newViewPanel(from: id)?.mac ?? viewLayouts.settings(for: id))?.widths ?? Data()
            place = id.rawValue
        } else {
            data = storedColumns
            place = browser.shown.storageKey
        }
        if widthCache.data != data || widthCache.place != place {
            widthCache.decoded = viewID == nil
                ? ItemTableColumnLayouts.layout(for: browser.shown, in: data)
                : (try? JSONDecoder().decode(TableColumnCustomization<ItemTableRow>.self, from: data)) ?? .init()
            widthCache.data = data
            widthCache.place = place
        }
        return widthCache.decoded
    }

    /// The customization without what the Properties list owns: every column's visibility and the order.
    private static func widthsOnly(
        _ layout: TableColumnCustomization<ItemTableRow>, _ columns: [ItemTableColumn]
    ) -> TableColumnCustomization<ItemTableRow> {
        var widths = layout
        for column in columns where column.content != .title { widths[visibility: column.id] = .automatic }
        widths.resetOrder()
        return widths
    }

    /// The width each column was left at, by the column's identifier. `TableColumnCustomization` keeps them only in the
    /// data it encodes, under `perColumnState`, as alternating identifiers and states.
    nonisolated static func keptWidths(in data: Data) -> [String: CGFloat] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = object["perColumnState"] as? [[String: Any]] else { return [:] }
        var widths: [String: CGFloat] = [:]
        for index in stride(from: 0, to: states.count - 1, by: 2) {
            let explicit = (states[index]["base"] as? [String: Any])?["explicit"] as? [String: Any]
            if let id = explicit?["_0"] as? String, let width = states[index + 1]["currentWidth"] as? Double { widths[id] = width }
        }
        return widths
    }

    /// The column identifiers a header drag wrote, or nil when this customization has no order (a resize or a hide).
    /// `TableColumnCustomization` keeps the order only in the data it encodes, under `columnOrder`.
    nonisolated static func headerOrder(in data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let order = object["columnOrder"] else { return nil }
        let entries = order as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            let base = entry["base"] as? [String: Any]
            let explicit = base?["explicit"] as? [String: Any]
            return explicit?["_0"] as? String
        }
    }
}

/// Times what a table costs when it shows another place: from the first pass that builds it for the place until the
/// main queue is free again, which is the pause a person feels. The signpost is `table.place`, in `navigation`. The
/// table's first pass only notes the place: a table that has just been mounted, by switching from the list or the
/// gallery or by launching, is a layout change, which is not a place change.
@MainActor
private final class TablePlaceTrace {
    private var place: PlaceView?
    private var current: (id: Int, interval: Telemetry.Interval)?
    private var counter = 0

    func bodyRan(for place: PlaceView) {
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

/// Each place's column widths as the person dragged them, kept together in the defaults under one key.
///
/// Stored data that cannot be read is never written over: a change that would replace it moves it aside under a key of its
/// own first (`setAsideKey`), and a Reset View leaves it as it is.
enum ItemTableColumnLayouts {
    static let key = "itemTableColumns"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "itemTableColumnsSetAside"

    static func key(for place: PlaceView) -> String { place.storageKey }

    static func layout(for place: PlaceView, in stored: Data) -> TableColumnCustomization<ItemTableRow> {
        layouts(in: stored)?[key(for: place)] ?? .init()
    }

    /// Whether the person arranged the place's columns: an entry with nothing in it is the table's own arrangement.
    static func isChanged(for place: PlaceView, in stored: Data) -> Bool {
        layouts(in: stored)?[key(for: place)].map { $0 != .init() } ?? false
    }

    /// The stored layouts without the place's, so its table starts again from its own columns. Data that cannot be read
    /// holds no layout of the place to remove, so it comes back as it was.
    static func removing(_ place: PlaceView, in stored: Data) -> Data {
        guard var layouts = layouts(in: stored), layouts[key(for: place)] != nil else { return stored }
        layouts[key(for: place)] = nil
        return (try? JSONEncoder().encode(layouts)) ?? stored
    }

    /// The stored layouts with the place's changed. Data that cannot be read is kept aside in `defaults` first, since the
    /// layouts then start again from this one.
    static func storing(
        _ layout: TableColumnCustomization<ItemTableRow>, for place: PlaceView, in stored: Data,
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

    /// The stored layouts: none where nothing is stored, and nil where what is stored cannot be read.
    private static func layouts(in stored: Data) -> [String: TableColumnCustomization<ItemTableRow>]? {
        if stored.isEmpty { return [:] }
        return try? JSONDecoder().decode([String: TableColumnCustomization<ItemTableRow>].self, from: stored)
    }

    /// Copies the columns earlier copies kept for each place to the new keys (`EarlierPlace.readIn`). Data that cannot
    /// be read is left as it is.
    static func readIn(in defaults: UserDefaults, done: inout Set<String>) {
        guard let stored = defaults.data(forKey: key), let layouts = layouts(in: stored) else { return }
        let carried = EarlierPlace.carried(layouts, setting: "columns", done: &done) { held, earlier in held == .init() ? earlier : held }
        guard carried != layouts, let data = try? JSONEncoder().encode(carried) else { return }
        defaults.set(data, forKey: key)
    }
}

extension ItemTableColumn {
    /// How wide the column starts and how far it can be dragged: wide for the name and for prose, narrow for marks.
    var widths: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch style {
        case .title: (240, 420, .infinity)
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

/// The table, apart from the body that pages the place. A table reads its selection as it is made, so a change of
/// selection runs this body rather than `ItemTable`'s, which would page the place again.
private struct ItemTableSelection<Content: View>: View {
    @Bindable var browser: Browser
    let content: ItemTableContent
    let drawn: DrawnRows
    let table: (Binding<Set<ItemID>>) -> Content

    var body: some View {
        table($browser.selection)
            .onChange(of: browser.selection, initial: true) {
                browser.revealSelectionInTable(content)
                // The one row the keyboard chose stays where it is drawn until another is chosen.
                let single = browser.selection.count == 1 ? browser.selection.first : nil
                browser.holdKeyboard(single.flatMap { drawn.anchors[$0] })
            }
    }
}

/// Holds the row under the pointer where it is drawn until the pointer goes to another (`RowHold`). A view of its own,
/// so a pointer that moves runs this body and not the table's.
private struct PointerHold: View {
    let hover: ItemTableHover
    let browser: Browser
    let drawn: DrawnRows

    var body: some View {
        Color.clear
            .onChange(of: hover.row) { _, row in browser.pointerMoved(to: row, anchors: drawn.anchors) }
    }
}

/// Where each row of the table was last drawn, kept apart from what the table observes, so a pointer that moves draws
/// nothing.
private final class DrawnRows {
    private(set) var anchors: [ItemID: HeldRow] = [:]

    func take(_ anchors: [ItemID: HeldRow]) { self.anchors = anchors }
}

/// Widths decoded for one place's stored columns. A class, so keeping the decoded value does not refresh the table.
private final class ColumnWidthCache {
    var data: Data?
    var place: String?
    var decoded = TableColumnCustomization<ItemTableRow>()
}

/// The rows the table draws: one page of the place. Groups stay in their order, and a group that begins after the
/// page is left out.
private struct Pages {
    struct GroupPage: Identifiable {
        let group: ItemTableGroup
        let rows: [ItemTableRow]
        var id: String { group.id }
    }

    /// The page of an ungrouped table.
    let slice: TablePaging.Slice
    let groups: [GroupPage]
    /// The item rows still to load, in the groups the person has not folded away.
    let remaining: Int
    /// Where each row drawn stands among its parents, where any nests (`ItemNesting`).
    let places: [ItemID: ItemNesting.Place]
    /// The items typed in place in a grouped table, which stand after the groups, where they were typed, until the row is
    /// left. An ungrouped table holds them at the end of `slice`.
    let trailing: [ItemTableRow]
    /// Where each row is drawn, which a row is held at (`RowHold`).
    let anchors: [ItemID: HeldRow]

    /// The page, with every held row put back where it was seen (`RowHold.holding`).
    @MainActor
    init(content: ItemTableContent, paging: TablePaging, size: TablePageSize, expanded: Set<ItemID>, hold: inout RowHold) {
        var anchors: [ItemID: HeldRow] = [:]
        if content.grouping == nil {
            let cut = paging.slice(content.rows, nesting: content.nesting, expanded: expanded, size: size)
            let held = hold.holding(cut.rows, group: nil, row: content.row)
            slice = TablePaging.Slice(rows: held, remaining: cut.remaining, places: cut.places)
            groups = []
            remaining = slice.remaining
            places = Dictionary(cut.places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            trailing = []
            for (index, row) in held.enumerated() { anchors[row.id] = HeldRow(id: row.id, group: nil, index: index) }
        } else {
            let drawn = paging.slice(
                groups: content.groups, nestings: content.groupNestings, collapsed: content.collapsed, expanded: expanded, size: size)
            slice = TablePaging.Slice(rows: [], remaining: 0)
            groups = drawn.groups.map { page in
                let held = hold.holding(page.rows, group: page.group.id, row: content.row)
                for (index, row) in held.enumerated() { anchors[row.id] = HeldRow(id: row.id, group: page.group.id, index: index) }
                return GroupPage(group: page.group, rows: held)
            }
            remaining = drawn.remaining
            places = Dictionary(drawn.groups.flatMap(\.places).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            trailing = hold.added.compactMap(content.row)
            // They stand apart from their groups, so letting them go draws them where they belong.
            hold.moved.formUnion(trailing.map(\.id))
        }
        self.anchors = anchors
    }

    var shownIDs: [String] {
        (slice.rows.map(\.id.rawValue) + groups.flatMap { $0.rows.map(\.id.rawValue) } + trailing.map(\.id.rawValue))
    }

    /// Where the groups' header rows fall among the table's rows: each group's header, then its rows unless it is folded.
    func headerPlaces(collapsed: Set<String>) -> Set<Int> {
        var places: Set<Int> = []
        var place = 0
        for page in groups {
            places.insert(place)
            place += 1
            if collapsed.contains(page.group.id) { continue }
            place += page.rows.count
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
