import SwiftUI

/// The View menu's filter commands: Show or Hide Filters, Add Filter… and Clear Filters.
struct FilterCommands: View {
    @Bindable var browser: Browser
    let shortcuts: ShortcutBindings

    var body: some View {
        Button(browser.toggleFiltersTitle) { browser.toggleFilterRow() }
            .shortcut(.toggleFilters, shortcuts)
        Button("Add Filter…") { browser.requestAddFilter() }
            .shortcut(.addFilter, shortcuts)
        if browser.filterCount > 0 {
            Button("Clear Filters") { browser.clearFilters() }
                .shortcut(.clearFilters, shortcuts)
        }
    }
}

/// The table's part of View Options (`CurrentViewOptions`): Sort, Group and the columns shown. Sort and Group are the
/// place's, kept in its default view or written to its saved view; the columns shown are kept for the place
/// (`ItemTableColumnLayouts`), or stored for a saved view (`Browser.setColumn`). The list and the gallery of every place
/// take the same Sort and Group, without the table's rows at a time and columns (`columns` false), and show the starting
/// order Settings > Lists gives until the place has its own.
struct ItemTableViewOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var columns = true
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()

    var body: some View {
        let content = browser.tableContent(in: library)
        let controls = Controls(browser: browser, content: content, stored: $storedColumns, choosesFromFields: !columns)
        controls.sortPicker
            .disabled(browser.keepsPlaceOrder)
        Divider()
        GroupByMenu(browser: browser)
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
    let browser: Browser
    @Binding var stored: Data
    /// The columns Sort by offers: those the table shows, or for a list or gallery every field its types can sort by.
    private let choices: [ItemTableColumn]

    init(browser: Browser, content: ItemTableContent, stored: Binding<Data>, choosesFromFields: Bool) {
        self.browser = browser
        _options = Binding { browser.tableOptions[browser.item] ?? ItemTableOptions() } set: { browser.tableOptions[browser.item] = $0 }
        columns = content.columns
        sort = SavedViews.arrangement(browser, content: content, order: browser.storedOrder).sort
        relevance = browser.isSearching ? Binding { browser.ordersByRelevance } set: { browser.orderSearch(byRelevance: $0) } : nil
        _stored = stored
        choices = choosesFromFields ? content.sortChoices : browser.shownColumns(content.columns, stored: stored.wrappedValue)
    }

    /// Whether the rows are in search order, where the window searches; nil where it does not.
    private let relevance: Binding<Bool>?

    // MARK: Sort

    var sortPicker: some View {
        let first = browser.ordersByRelevance ? nil : sort.first
        return Group {
            Picker("Sort by", systemImage: "arrow.up.arrow.down", selection: Binding { first?.column.id ?? "" } set: { id in
                guard let column = columns.first(where: { $0.id == id }) else {
                    // Relevance has no column, so its tag is empty.
                    if id.isEmpty { relevance?.wrappedValue = true }
                    return
                }
                relevance?.wrappedValue = false
                browser.chooseSort([ItemTableComparator(column: column, order: column.firstOrder)])
            }) {
                if relevance != nil {
                    Text("Relevance").tag("")
                    Divider()
                }
                ForEach(choices) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ItemTableSort")
            Picker("Order", selection: Binding { first?.order ?? .forward } set: { order in
                guard let first else { return }
                browser.chooseSort([ItemTableComparator(column: first.column, order: order)] + sort.dropFirst())
            }) {
                Text(first?.column.ascendingTitle ?? String(localized: "Ascending")).tag(SortOrder.forward)
                Text(first?.column.descendingTitle ?? String(localized: "Descending")).tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
            .disabled(first == nil)
        }
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
