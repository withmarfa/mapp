import SwiftUI

/// The table's Filter, on its toolbar just after Search and in the View menu. It reads the table as the table reads
/// itself (`ItemTableContent`), and what it keeps is the place's, for the window.
struct ItemTableFilterMenu: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let content = ItemTableContent(browser: browser, library: library)
        Controls(browser: browser, content: content, customization: .constant(.init())).filterMenu
            .menuIndicator(.hidden)
    }
}

/// The table's part of View Options (`CurrentViewOptions`): Sort, Group and the columns shown. Sort and Group are the
/// place's, for the window; the columns shown are kept for the place (`ItemTableColumnLayouts`).
struct ItemTableViewOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()

    var body: some View {
        let content = ItemTableContent(browser: browser, library: library)
        let controls = Controls(browser: browser, content: content, customization: Binding {
            ItemTableColumnLayouts.layout(for: browser.item, in: storedColumns)
        } set: {
            storedColumns = ItemTableColumnLayouts.storing($0, for: browser.item, in: storedColumns)
        })
        controls.sortPicker
        Divider()
        controls.groupPicker
        Divider()
        controls.columnsMenu
    }
}

private struct Controls {
    @Binding var options: ItemTableOptions
    let columns: [ItemTableColumn]
    /// Every row before the filters, so a filter can offer values it is hiding.
    let rows: [ItemTableRow]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    @Binding var customization: TableColumnCustomization<ItemTableRow>

    init(browser: Browser, content: ItemTableContent, customization: Binding<TableColumnCustomization<ItemTableRow>>) {
        _options = Binding { browser.tableOptions[browser.item] ?? ItemTableOptions() } set: { browser.tableOptions[browser.item] = $0 }
        columns = content.columns
        rows = content.allRows
        sort = content.sort
        grouping = content.grouping
        categorical = content.categoricalColumns
        relevance = browser.isSearching ? Binding { browser.ordersByRelevance } set: { browser.orderSearch(byRelevance: $0) } : nil
        _customization = customization
    }

    private let categorical: [ItemTableColumn]
    /// Whether the rows are in search order, where the window searches; nil where it does not.
    private let relevance: Binding<Bool>?

    // MARK: Filter

    var filterMenu: some View {
        Menu {
            ForEach(categorical) { column in
                Menu(column.label) {
                    ForEach(categories(of: column), id: \.value) { category in
                        Toggle(isOn: filterBinding(column, category.value)) {
                            ItemTableMenuLabel(column: column, value: category.value.isEmpty ? nil : category.value,
                                               title: "\(category.title)  \(category.count)")
                        }
                    }
                }
            }
            if !options.filters.isEmpty {
                Divider()
                Button("Clear Filters") { options.filters = [:] }
            }
        } label: {
            Label("Filter", systemImage: options.filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Show only some items")
        .accessibilityIdentifier("ItemTableFilter")
    }

    /// A column's values with how many rows hold each, in its groups' order, then the empty cells.
    private func categories(of column: ItemTableColumn) -> [(value: String, title: String, count: Int)] {
        ItemTableLayout.groups(of: rows, by: column).map { ($0.id, $0.title, $0.rows.count) }
    }

    private func filterBinding(_ column: ItemTableColumn, _ value: String) -> Binding<Bool> {
        Binding {
            options.filters[column.id]?.contains(value) ?? false
        } set: { isOn in
            var kept = options.filters[column.id] ?? []
            if isOn { kept.insert(value) } else { kept.remove(value) }
            options.filters[column.id] = kept.isEmpty ? nil : kept
        }
    }

    // MARK: Sort

    var sortPicker: some View {
        let first = sort.first
        return Group {
            Picker("Sort By", systemImage: "arrow.up.arrow.down", selection: Binding { first?.column.id ?? "" } set: { id in
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
        Picker("Group By", systemImage: "rectangle.grid.1x2", selection: Binding { grouping?.id ?? "" } set: { id in
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

    // MARK: Columns

    private var shownColumns: [ItemTableColumn] { columns.filter(customization.shows) }

    var columnsMenu: some View {
        Menu("Columns", systemImage: "tablecells") {
            ForEach(columns.filter { $0.content != .title }) { column in
                Toggle(column.label, isOn: Binding { customization.shows(column) } set: {
                    customization[visibility: column.id] = $0 ? .visible : .hidden
                })
            }
            Divider()
            Button("Reset Columns") { customization = TableColumnCustomization() }
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
