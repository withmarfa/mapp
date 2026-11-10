import SwiftUI

/// The Filter, on the toolbar just after Search: it shows or hides the row of filters above the list, tinted and counting
/// the filters where the place has any. What the row keeps is the place's, for the window, in every layout.
struct ItemTableFilterMenu: View {
    @Bindable var browser: Browser

    var body: some View {
        let count = browser.filterCount
        Button {
            browser.toggleFilterRow()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease")
                if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
            }
            .foregroundStyle(count > 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .help(browser.showsFilterRow ? "Hide the filters" : "Show the filters")
        .accessibilityLabel(count > 0 ? Text("Filter, \(count) applied") : Text("Filter"))
        .accessibilityIdentifier("ItemTableFilter")
    }
}

/// The View menu's filter commands: Show or Hide Filters, Add Filter… and Clear Filters.
struct FilterCommands: View {
    @Bindable var browser: Browser

    var body: some View {
        Button(browser.showsFilterRow ? "Hide Filters" : "Show Filters") { browser.toggleFilterRow() }
        Button("Add Filter…") { browser.requestAddFilter() }
        if browser.filterCount > 0 {
            Button("Clear Filters") { browser.clearFilters() }
        }
    }
}

/// The table's part of View Options (`CurrentViewOptions`): Sort, Group and the columns shown. Sort and Group are the
/// place's, for the window; the columns shown are kept for the place (`ItemTableColumnLayouts`), or held for a saved
/// view until Save (`Browser.setColumn`). A saved view's list
/// and gallery take its Sort and Group too, without the table's rows at a time and columns (`columns` false).
struct ItemTableViewOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var columns = true
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()

    var body: some View {
        let content = browser.tableContent(in: library)
        let controls = Controls(browser: browser, content: content, stored: $storedColumns)
        controls.sortPicker
        Divider()
        controls.groupPicker
        if columns {
            Divider()
            controls.pageSizePicker
            Divider()
            controls.columnsMenu
        }
    }
}

private struct Controls {
    @Binding var options: ItemTableOptions
    let columns: [ItemTableColumn]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    let browser: Browser
    @Binding var stored: Data

    init(browser: Browser, content: ItemTableContent, stored: Binding<Data>) {
        self.browser = browser
        _options = Binding { browser.tableOptions[browser.item] ?? ItemTableOptions() } set: { browser.tableOptions[browser.item] = $0 }
        columns = content.columns
        sort = content.sort
        grouping = content.grouping
        categorical = content.categoricalColumns
        relevance = browser.isSearching ? Binding { browser.ordersByRelevance } set: { browser.orderSearch(byRelevance: $0) } : nil
        _stored = stored
    }

    private let categorical: [ItemTableColumn]
    /// Whether the rows are in search order, where the window searches; nil where it does not.
    private let relevance: Binding<Bool>?

    // MARK: Sort

    var sortPicker: some View {
        let first = sort.first
        return Group {
            Picker("Sort by", systemImage: "arrow.up.arrow.down", selection: Binding { first?.column.id ?? "" } set: { id in
                guard let column = columns.first(where: { $0.id == id }) else {
                    // Relevance has no column, so its tag is empty.
                    if id.isEmpty { relevance?.wrappedValue = true }
                    return
                }
                relevance?.wrappedValue = false
                options.sort = [ItemTableComparator(column: column, order: column.firstOrder)]
            }) {
                if relevance != nil {
                    Text("Relevance").tag("")
                    Divider()
                }
                ForEach(shownColumns) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ItemTableSort")
            Picker("Order", selection: Binding { first?.order ?? .forward } set: { order in
                guard let first else { return }
                options.sort = [ItemTableComparator(column: first.column, order: order)] + sort.dropFirst()
            }) {
                Text(first?.column.ascendingTitle ?? String(localized: "Ascending")).tag(SortOrder.forward)
                Text(first?.column.descendingTitle ?? String(localized: "Descending")).tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
            .disabled(first == nil)
        }
    }

    // MARK: Group

    var groupPicker: some View {
        Picker("Group by", systemImage: "rectangle.grid.1x2", selection: Binding { grouping?.id ?? "" } set: { id in
            options.grouping = id.isEmpty ? .none : .column(id)
            options.collapsed = nil
        }) {
            Text("None").tag("")
            Divider()
            ForEach(categorical) { Text($0.label).tag($0.id) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("ItemTableGroup")
    }

    // MARK: Page size

    var pageSizePicker: some View {
        Picker("Rows at a Time", systemImage: "list.number", selection: Binding { options.pageSize } set: { options.pageSize = $0 }) {
            ForEach(TablePageSize.allCases, id: \.self) { Text($0.rawValue, format: .number).tag($0) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("ItemTablePageSize")
    }

    // MARK: Columns

    private var shownColumns: [ItemTableColumn] { browser.shownColumns(columns, stored: stored) }

    var columnsMenu: some View {
        Menu("Columns", systemImage: "tablecells") {
            ForEach(columns.filter { $0.content != .title }) { column in
                Toggle(column.label, isOn: Binding { browser.showsColumn(column, stored: stored) } set: {
                    browser.setColumn(column, shown: $0, stored: $stored)
                })
            }
            Divider()
            Button("Reset Columns") { browser.resetColumns(stored: $stored) }
        }
        .accessibilityIdentifier("ItemTableColumns")
    }
}

extension TableColumnCustomization<ItemTableRow> {
    /// Whether the table shows a column: as the person set it, or as the column is by default.
    func shows(_ column: ItemTableColumn) -> Bool {
        switch self[visibility: column.id] {
        case .visible: true
        case .hidden: false
        default: column.isShownByDefault
        }
    }
}

extension ItemTableColumn {
    /// The name of a column's forward order, in the words its values call for.
    var ascendingTitle: String {
        switch style {
        case .date: String(localized: "Oldest First")
        case .number, .duration, .priority: String(localized: "Lowest First")
        case .status: String(localized: "In Progress First")
        default: String(localized: "A to Z")
        }
    }

    var descendingTitle: String {
        switch style {
        case .date: String(localized: "Newest First")
        case .number, .duration, .priority: String(localized: "Highest First")
        case .status: String(localized: "Finished First")
        default: String(localized: "Z to A")
        }
    }
}
