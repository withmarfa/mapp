import AppKit
import SwiftUI

/// A place's items as a table, in the manner of a database view: a row for each item, a column for each field its
/// type has, and the place's own grouping, sort and filters from its toolbar (`ItemTableFilterMenu`, `ItemTableViewOptions`). Selecting a row shows it in Details, and
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
    @State private var columnCustomization = TableColumnCustomization<ItemTableRow>()
    @State private var daysSeen = 0
    @State private var hover = ItemTableHover()

    var body: some View {
        let _ = daysSeen
        let content = ItemTableContent(browser: browser, library: library)
        let (allRows, rows) = (content.allRows, content.rows)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        table(columns: content.columns, rows: rows, groups: content.groups, grouping: content.grouping, collapsed: content.collapsed)
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
                        Button("Clear Filters") { browser.tableOptions[browser.item, default: .init()].filters = [:] }
                    }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle(shown: rows.count, of: allRows.count))
            .toolbar(removing: browser.isSearchExpanded ? .title : nil)
            .onChange(of: browser.isSearchExpanded) {
                if !browser.isSearchExpanded { browser.focusRequest = .list }
            }
            .onChange(of: placeKey, initial: true) { loadColumns() }
            // The toolbar's Columns menu changes the stored layout.
            .onChange(of: storedColumns) { loadColumns() }
            .onChange(of: columnCustomization) {
                storedColumns = ItemTableColumnLayouts.storing(columnCustomization, for: browser.item, in: storedColumns)
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
            }
    }

    private func table(
        columns: [ItemTableColumn], rows: [ItemTableRow], groups: [ItemTableGroup], grouping: ItemTableColumn?,
        collapsed: Set<String>
    ) -> some View {
        Table(of: ItemTableRow.self, selection: $browser.selection, sortOrder: sortBinding(columns), columnCustomization: $columnCustomization) {
            TableColumnForEach(columns) { column in
                TableColumn(Text(verbatim: column.label), sortUsing: ItemTableComparator(column: column, order: column.firstOrder)) { row in
                    ItemTableCell(library: library, row: row, column: column, browser: browser, order: order, hover: hover)
                }
                .width(min: column.widths.min, ideal: column.widths.ideal, max: column.widths.max)
                .customizationID(column.id)
                .defaultVisibility(column.isShownByDefault ? .automatic : .hidden)
                .disabledCustomizationBehavior(column.content == .title ? .visibility : [])
            }
        } rows: {
            if let grouping {
                ForEach(groups) { group in
                    Section {
                        if !collapsed.contains(group.id) {
                            ForEach(group.rows) { TableRow($0) }
                        }
                    } header: {
                        ItemTableGroupHeader(
                            group: group, column: grouping, isCollapsed: collapsed.contains(group.id)
                        ) { toggle(group.id, collapsed: collapsed) }
                    }
                }
            } else {
                ForEach(rows) { TableRow($0) }
            }
        }
        .tableStyle(.inset)
        .softSelection(rows: rows.map(\.id.rawValue) + collapsed.sorted(), selection: browser.selection)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .focused(pane, equals: .list)
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
            browser.tableOptions[browser.item, default: .init()].sort = Array(sort.prefix(3))
        }
    }

    // MARK: Column layouts

    private var placeKey: String { ItemTableColumnLayouts.key(for: browser.item) }

    private func loadColumns() {
        let stored = ItemTableColumnLayouts.layout(for: browser.item, in: storedColumns)
        if stored != columnCustomization { columnCustomization = stored }
    }
}

/// What a place's table shows, worked out alike by the table and its toolbar's controls. The columns, the sort and
/// the grouping come from the items alone; the rows the filters keep, their groups and what is folded away are
/// worked out when first read, so the controls and the command palette, which need only the columns, never sort.
@MainActor
final class ItemTableContent {
    /// Every row before the filters.
    let allRows: [ItemTableRow]
    let columns: [ItemTableColumn]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    private let options: ItemTableOptions

    /// The rows the filters keep, in order.
    lazy var rows: [ItemTableRow] = ItemTableLayout.sorted(ItemTableLayout.filter(allRows, by: options.filters, columns: columns), by: sort)
    lazy var groups: [ItemTableGroup] = grouping.map { ItemTableLayout.groups(of: rows, by: $0) } ?? []
    lazy var collapsed: Set<String> = grouping.map { ItemTableLayout.collapsed(options, groups: groups, by: $0) } ?? []

    init(browser: Browser, library: any ItemLibrary) {
        allRows = ItemTableRow.rows(of: browser.items(in: library), in: library)
        let hidden = allRows.first.map { library.hiddenPropertyKeys(of: $0.item) } ?? []
        columns = ItemTableLayout.columns(for: allRows, catalogue: library.catalogue, hidden: hidden)
        options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        // Relevance is the order the rows come in, which the sort leaves alone when it is empty.
        sort = browser.ordersByRelevance ? [] : ItemTableLayout.sort(options, columns: columns, keepsGivenOrder: browser.keepsPlaceOrder)
        grouping = ItemTableLayout.grouping(options, columns: columns)
    }

    /// The columns a table can be filtered and grouped by: those with a few values to pick from, where some row
    /// holds one.
    var categoricalColumns: [ItemTableColumn] {
        columns.filter { column in column.isCategorical && allRows.contains { column.category(of: $0) != nil } }
    }
}

/// Each place's columns as the person arranged them (shown or hidden, in their order, at their widths), kept
/// together in the defaults under one key.
enum ItemTableColumnLayouts {
    static let key = "itemTableColumns"

    static func key(for place: SidebarItem) -> String {
        (try? JSONEncoder().encode(place)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func layout(for place: SidebarItem, in stored: Data) -> TableColumnCustomization<ItemTableRow> {
        layouts(in: stored)[key(for: place)] ?? .init()
    }

    static func storing(_ layout: TableColumnCustomization<ItemTableRow>, for place: SidebarItem, in stored: Data) -> Data {
        var layouts = layouts(in: stored)
        layouts[key(for: place)] = layout
        return (try? JSONEncoder().encode(layouts)) ?? stored
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
        case .person: (100, 140, 240)
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

/// A group's header row: its mark and name, how many it holds, and a chevron that folds it away.
private struct ItemTableGroupHeader: View {
    let group: ItemTableGroup
    let column: ItemTableColumn
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                ItemTableCategory(column: column, value: group.value, title: group.title)
                    .fontWeight(.semibold)
                Text(group.rows.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .interfaceFont(.body)
        .accessibilityLabel(Text("\(group.title), \(group.rows.count)"))
        .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
        .accessibilityHint(isCollapsed ? Text("Shows the group’s items") : Text("Hides the group’s items"))
    }
}
