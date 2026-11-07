import SwiftUI

/// The values one column can be filtered by, as its menu offers them: Is or Is Not, then each value with how many
/// rows hold it, then Remove Filter where the column is filtered. It reads the place's `ItemTableOptions`, which
/// every layout shares, and is the same menu in the toolbar's Filter and in a chip.
struct ColumnFilterMenu: View {
    @Bindable var browser: Browser
    let column: ItemTableColumn
    /// Every row before the filters, so a filter can offer values it is hiding.
    let rows: [ItemTableRow]

    var body: some View {
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let isNegated = options.negated.contains(column.id)
        Toggle("Is", isOn: Binding { !isNegated } set: { if $0 { setNegated(false) } })
        Toggle("Is Not", isOn: Binding { isNegated } set: { if $0 { setNegated(true) } })
        Divider()
        ForEach(ItemTableLayout.offered(in: rows, by: column, keeping: options.filters[column.id] ?? []), id: \.id) { category in
            Toggle(isOn: binding(for: category.id)) {
                ItemTableMenuLabel(
                    column: column, value: category.id.isEmpty ? nil : category.id, title: "\(category.title)  \(category.rows.count)")
            }
        }
        if options.filters[column.id]?.isEmpty == false {
            Divider()
            Button("Remove Filter") { browser.tableOptions[browser.item, default: .init()].clearFilter(column.id) }
        }
    }

    private func setNegated(_ negated: Bool) {
        if negated {
            browser.tableOptions[browser.item, default: .init()].negated.insert(column.id)
        } else {
            browser.tableOptions[browser.item, default: .init()].negated.remove(column.id)
        }
    }

    private func binding(for value: String) -> Binding<Bool> {
        Binding {
            browser.tableOptions[browser.item]?.filters[column.id]?.contains(value) ?? false
        } set: { isOn in
            var kept = browser.tableOptions[browser.item]?.filters[column.id] ?? []
            if isOn { kept.insert(value) } else { kept.remove(value) }
            browser.tableOptions[browser.item, default: .init()].setFilter(column.id, values: kept)
        }
    }
}

/// What the Filter menu holds: each column that can be filtered, as a submenu (`ColumnFilterMenu`), and Clear
/// Filters. The toolbar's Filter, the View menu and the chip row's + chip all show it. It works the place's table
/// out only when its items are drawn, which a menu does when it opens, so a list that nobody filters builds none.
struct FilterMenuItems: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let content = browser.tableContent(in: library)
        ForEach(content.categoricalColumns) { column in
            Menu(column.label) { ColumnFilterMenu(browser: browser, column: column, rows: content.allRows) }
        }
        if browser.tableOptions[browser.item]?.isFiltering == true {
            Divider()
            Button("Clear Filters") { browser.tableOptions[browser.item, default: .init()].clearFilters() }
        }
    }
}

/// A chip for each column the place filters, above whichever layout the place shows, ending in a + chip that opens
/// the Filter menu. It shows nothing while the place has no filters, and reads the place's table only then, so a
/// place nobody filtered never works its table out for a layout that does not need it.
struct FilterChipRow: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        if browser.tableOptions[browser.item]?.isFiltering == true {
            let content = browser.tableContent(in: library)
            let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
            let filtered = content.columns.filter { options.filters[$0.id]?.isEmpty == false }
            if !filtered.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(filtered) { column in
                            FilterChip(browser: browser, content: content, column: column, options: options)
                        }
                        Menu {
                            FilterMenuItems(browser: browser)
                        } label: {
                            Label("Add Filter", systemImage: "plus").labelStyle(.iconOnly)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("Add a filter")
                        .accessibilityIdentifier("FilterChipAdd")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("FilterChips")
            }
        }
    }
}

/// One column's filter as a chip. Choosing it opens that column's menu.
private struct FilterChip: View {
    @Bindable var browser: Browser
    let content: ItemTableContent
    let column: ItemTableColumn
    let options: ItemTableOptions

    var body: some View {
        Menu {
            ColumnFilterMenu(browser: browser, column: column, rows: content.allRows)
        } label: {
            Text(verbatim: summary)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityIdentifier("FilterChip")
    }

    /// The column and what it keeps: "Status: Done", "Status is not: Done, Open" and, past two values, "Status: Done +2".
    private var summary: String {
        let kept = options.filters[column.id] ?? []
        let titles = ItemTableLayout.offered(in: content.allRows, by: column, keeping: kept).filter { kept.contains($0.id) }.map(\.title)
        let shown = titles.prefix(2).joined(separator: ", ")
        let rest = titles.count - 2
        let values = rest > 0 ? String(localized: "\(shown) +\(rest)") : shown
        return options.isNegated(column.id)
            ? String(localized: "\(column.label) is not: \(values)")
            : String(localized: "\(column.label): \(values)")
    }
}

/// The answer to filters that hide every item, in the layouts that have no empty state of their own for it.
struct FilteredEmptyState: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        if browser.filtersHideEverything(in: library) {
            EmptyState(title: Text("No Matching Items"), detail: Text("No items match the filters.")) {
                Button("Clear Filters") { browser.tableOptions[browser.item, default: .init()].clearFilters() }
            }
            .background(.background)
            .accessibilityIdentifier("FilteredEmptyState")
        }
    }
}

extension View {
    /// The place's filter chips above the content, while it has filters.
    func filterChips(_ browser: Browser) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            FilterChipRow(browser: browser)
        }
    }

    /// Says so, with Clear Filters, where the place's filters hide every item.
    func filteredEmptyState(_ browser: Browser) -> some View {
        overlay { FilteredEmptyState(browser: browser) }
    }
}
