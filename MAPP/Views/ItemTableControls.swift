import SwiftUI

/// The table's controls on its toolbar: Filter, then View Options, which holds Sort, Group and the columns shown.
/// They read the table as it reads itself (`ItemTableContent`), and each choice is the place's, kept for the
/// window; the columns shown are kept for the place (`ItemTableColumnLayouts`).
struct ItemTableControls: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()

    var body: some View {
        let content = ItemTableContent(browser: browser, library: library)
        Controls(
            options: Binding { browser.tableOptions[browser.item] ?? ItemTableOptions() } set: { browser.tableOptions[browser.item] = $0 },
            columns: content.columns, rows: content.allRows, sort: content.sort, grouping: content.grouping,
            customization: Binding {
                ItemTableColumnLayouts.layout(for: browser.item, in: storedColumns)
            } set: {
                storedColumns = ItemTableColumnLayouts.storing($0, for: browser.item, in: storedColumns)
            })
    }
}

private struct Controls: View {
    @Binding var options: ItemTableOptions
    let columns: [ItemTableColumn]
    /// Every row before the filters, so a filter can offer values it is hiding.
    let rows: [ItemTableRow]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    @Binding var customization: TableColumnCustomization<ItemTableRow>

    /// The columns a table can be filtered and grouped by: those with a few values to pick from, where some row
    /// holds one.
    private var categorical: [ItemTableColumn] {
        columns.filter { column in column.isCategorical && rows.contains { column.category(of: $0) != nil } }
    }

    var body: some View {
        filterMenu
            .menuIndicator(.hidden)
        Menu {
            sortPicker
            Divider()
            groupPicker
            Divider()
            columnsMenu
        } label: {
            Label("View Options", systemImage: "slider.horizontal.3")
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }

    // MARK: Filter

    private var filterMenu: some View {
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

    private var sortPicker: some View {
        let first = sort.first
        return Group {
            Picker("Sort By", systemImage: "arrow.up.arrow.down", selection: Binding { first?.column.id ?? "" } set: { id in
                guard let column = columns.first(where: { $0.id == id }) else { return }
                options.sort = [ItemTableComparator(column: column, order: column.firstOrder)]
            }) {
                ForEach(shownColumns) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ItemTableSort")
            Picker("Order", selection: Binding { first?.order ?? .forward } set: { order in
                guard let first else { return }
                options.sort = [ItemTableComparator(column: first.column, order: order)] + sort.dropFirst()
            }) {
                Text(first.map(ascendingTitle) ?? String(localized: "Ascending")).tag(SortOrder.forward)
                Text(first.map(descendingTitle) ?? String(localized: "Descending")).tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        }
    }

    private func ascendingTitle(_ comparator: ItemTableComparator) -> String {
        switch comparator.column.style {
        case .date: String(localized: "Oldest First")
        case .number, .duration, .priority: String(localized: "Lowest First")
        case .status: String(localized: "In Progress First")
        default: String(localized: "A to Z")
        }
    }

    private func descendingTitle(_ comparator: ItemTableComparator) -> String {
        switch comparator.column.style {
        case .date: String(localized: "Newest First")
        case .number, .duration, .priority: String(localized: "Highest First")
        case .status: String(localized: "Finished First")
        default: String(localized: "Z to A")
        }
    }

    // MARK: Group

    private var groupPicker: some View {
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

    private var shownColumns: [ItemTableColumn] { columns.filter(isShown) }

    private func isShown(_ column: ItemTableColumn) -> Bool {
        switch customization[visibility: column.id] {
        case .visible: true
        case .hidden: false
        default: column.isShownByDefault
        }
    }

    private var columnsMenu: some View {
        Menu("Columns", systemImage: "tablecells") {
            ForEach(columns.filter { $0.content != .title }) { column in
                Toggle(column.label, isOn: Binding { isShown(column) } set: {
                    customization[visibility: column.id] = $0 ? .visible : .hidden
                })
            }
            Divider()
            Button("Reset Columns") { customization = TableColumnCustomization() }
        }
        .accessibilityIdentifier("ItemTableColumns")
    }
}
