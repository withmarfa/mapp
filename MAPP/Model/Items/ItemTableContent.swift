import Foundation

/// What a place's table shows, worked out once for the window (`Browser.tableContent(in:)`) and shared by the table,
/// its toolbar's controls, the menu bar and the command palette. The columns, the sort and the grouping come from
/// the items alone; the rows the filters keep, their groups and what is folded away are worked out when first
/// read, so the controls and the command palette, which need only the columns, never sort.
@MainActor
final class ItemTableContent {
    /// Every row before the filters.
    let allRows: [ItemTableRow]
    let columns: [ItemTableColumn]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    private let options: ItemTableOptions

    /// The rows the filters keep, in order.
    lazy var rows: [ItemTableRow] = Cost.measure(.tableRows) {
        ItemTableLayout.sorted(ItemTableLayout.filter(allRows, by: options.filters, columns: columns), by: sort)
    }
    lazy var groups: [ItemTableGroup] = Cost.measure(.tableGroups) { grouping.map { ItemTableLayout.groups(of: rows, by: $0) } ?? [] }
    lazy var collapsed: Set<String> = grouping.map { ItemTableLayout.collapsed(options, groups: groups, by: $0) } ?? []

    /// Works the table out for `items`, which are what `browser` shows in `library`. Nothing is kept: ask the
    /// browser, which keeps the last one while its inputs stand.
    init(browser: Browser, library: any ItemLibrary, items: [Item]) {
        let start = ContinuousClock.now
        defer { Cost.record(.tableContent, since: start) }
        allRows = ItemTableRow.rows(of: items, in: library)
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
