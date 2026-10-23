import AppKit
import SwiftUI

/// A place's items as a table, in the manner of a database view: a row for each item, a column for each field its
/// type has, and the place's own grouping, sort and filters above it. Selecting a row shows it in Details, and
/// opening one shows its page in the table's place, as the gallery does.
struct ItemTable: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Bindable var browser: Browser
    let order: NoteOrder
    var pane: FocusState<Browser.Pane?>.Binding
    /// Each place's columns as the person arranged them: shown or hidden, in their order, at their widths.
    @AppStorage("itemTableColumns") private var storedColumns = Data()
    @State private var columnCustomization = TableColumnCustomization<ItemTableRow>()
    @State private var daysSeen = 0

    var body: some View {
        let _ = daysSeen
        let allRows = ItemTableRow.rows(of: browser.items(in: library), in: library)
        let columns = ItemTableLayout.columns(
            for: allRows, catalogue: library.catalogue, place: browser.item, hidden: hiddenKeys(allRows))
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let sort = ItemTableLayout.sort(options, columns: columns)
        let rows = ItemTableLayout.sorted(ItemTableLayout.filter(allRows, by: options.filters, columns: columns), by: sort)
        let grouping = ItemTableLayout.grouping(options, columns: columns)
        let groups = grouping.map { ItemTableLayout.groups(of: rows, by: $0) } ?? []
        let collapsed = grouping.map { ItemTableLayout.collapsed(options, groups: groups, by: $0) } ?? []
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        table(columns: columns, rows: rows, groups: groups, grouping: grouping, collapsed: collapsed)
            .safeAreaInset(edge: .top, spacing: 0) {
                ItemTableBar(
                    options: optionsBinding, columns: columns, rows: allRows, shownCount: rows.count,
                    sort: sort, grouping: grouping, customization: $columnCustomization)
            }
            .overlay {
                if allRows.isEmpty {
                    if browser.isSearching {
                        ContentUnavailableView.search(text: browser.searchText)
                    } else {
                        ContentUnavailableView("No Items", systemImage: "tablecells")
                    }
                } else if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Items", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("No items match the filters.")
                    } actions: {
                        Button("Clear Filters") { browser.tableOptions[browser.item, default: .init()].filters = [:] }
                    }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(browser.isSearching ? Text("^[\(allRows.count) result](inflect: true)") : Text("^[\(allRows.count) item](inflect: true)"))
            .toolbar(removing: browser.isSearchExpanded ? .title : nil)
            .onChange(of: browser.isSearchExpanded) {
                if !browser.isSearchExpanded { browser.focusRequest = .list }
            }
            .onChange(of: placeKey, initial: true) { columnCustomization = storedLayouts[placeKey] ?? .init() }
            .onChange(of: columnCustomization) { storeColumns() }
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
                    ItemTableCell(library: library, row: row, column: column, browser: browser, order: order)
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
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(.windowBackground)
        .focused(pane, equals: .list)
        .accessibilityIdentifier("ItemTable")
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if !ids.isEmpty {
                Button("Open") { open(ids) }
                    .disabled(ids.count != 1)
                Button("Open in New Window", systemImage: "macwindow") {
                    for id in library.idsForWindows(ids) { openWindow(value: id) }
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
            EditorController.flushAll(leaving: false) { [library, undoManager] kept in
                guard kept else { return }
                Browser.delete(ids, in: library, undoManager: undoManager)
            }
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

    private func hiddenKeys(_ rows: [ItemTableRow]) -> Set<String> {
        rows.first.map { library.hiddenPropertyKeys(of: $0.item) } ?? []
    }

    private var optionsBinding: Binding<ItemTableOptions> {
        Binding { browser.tableOptions[browser.item] ?? ItemTableOptions() } set: { browser.tableOptions[browser.item] = $0 }
    }

    /// The header's sort: a click puts its column first, and only the last few columns clicked are kept.
    private func sortBinding(_ columns: [ItemTableColumn]) -> Binding<[ItemTableComparator]> {
        Binding {
            ItemTableLayout.sort(browser.tableOptions[browser.item] ?? ItemTableOptions(), columns: columns)
        } set: { sort in
            browser.tableOptions[browser.item, default: .init()].sort = Array(sort.prefix(3))
        }
    }

    // MARK: Column layouts

    private var placeKey: String {
        (try? JSONEncoder().encode(browser.item)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private var storedLayouts: [String: TableColumnCustomization<ItemTableRow>] {
        (try? JSONDecoder().decode([String: TableColumnCustomization<ItemTableRow>].self, from: storedColumns)) ?? [:]
    }

    private func storeColumns() {
        var layouts = storedLayouts
        layouts[placeKey] = columnCustomization
        if let data = try? JSONEncoder().encode(layouts) { storedColumns = data }
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
