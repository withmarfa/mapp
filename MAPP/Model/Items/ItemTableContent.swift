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
    /// How `grouping` groups: by each value, or by a date's span.
    let groupMode: GroupMode
    private let options: ItemTableOptions
    /// The calendar dates are grouped on: a saved view's weeks start on Monday, a place's where Settings says.
    let calendar: Calendar
    private let catalogue: Catalogue

    /// The rows the filters keep, in the order the items came in: what a layout that sorts and groups the items
    /// itself (the list, the board, the timeline) works from.
    lazy var kept: [ItemTableRow] = options.isFiltering
        ? ItemTableLayout.filter(allRows, by: options.filters, negated: options.negated, columns: columns) : allRows

    /// The rows the filters keep, in order.
    lazy var rows: [ItemTableRow] = Cost.measure(.tableRows) {
        ItemTableLayout.sorted(kept, by: sort)
    }
    /// Every group in order, the hidden and the empty ones too: what Edit View lists to order and hide. A grouping the
    /// person or the view chose lists its empty groups (`declared`), which a place's own grouping by status does not.
    lazy var allGroups: [ItemTableGroup] = Cost.measure(.tableGroups) {
        guard let grouping else { return [] }
        let made = ItemTableLayout.groups(
            of: rows, by: grouping, mode: groupMode, catalogue: catalogue, declared: options.grouping != .automatic, calendar: calendar)
        return ItemTableLayout.ordered(made, by: options.groupOrder)
    }
    /// The groups shown: all but the hidden ones (`device/view-group-hidden`), and the empty ones where Hide Empty Groups is on.
    lazy var groups: [ItemTableGroup] = {
        let hidden = options.hiddenGroups ?? []
        return allGroups.filter { !hidden.contains($0.id) && !(hidesEmptyGroups && $0.rows.isEmpty) }
    }()
    lazy var collapsed: Set<String> = grouping.map { ItemTableLayout.collapsed(options, groups: groups, by: $0, mode: groupMode) } ?? []
    /// Whether the rows are all in hidden groups, which says so rather than that the place is empty.
    var hidesEveryGroup: Bool { grouping != nil && !rows.isEmpty && groups.allSatisfy(\.rows.isEmpty) }
    /// Whether a group with no items is left out (Hide Empty Groups).
    let hidesEmptyGroups: Bool

    /// Works the table out for `items`, which are what `browser` shows in `library`. Nothing is kept: ask the
    /// browser, which keeps the last one while its inputs stand.
    init(browser: Browser, library: any ItemLibrary, items: [Item]) {
        let start = ContinuousClock.now
        defer { Cost.record(.tableContent, since: start) }
        let looks = browser.looks(in: library)
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let wanted = ItemTableLayout.relations(
            of: Set(items.map(\.type)), looks: looks, options: options, shown: browser.shownRelations)
        allRows = ItemTableRow.rows(of: items, in: library, wanting: wanted, looks: looks)
        let hidden = allRows.first.map { library.hiddenPropertyKeys(of: $0.item) } ?? []
        columns = ItemTableLayout.columns(
            for: allRows, types: browser.listedTypes(in: library), catalogue: library.catalogue, hidden: hidden, looks: looks)
        catalogue = library.catalogue
        self.options = options
        // Relevance is the order the rows come in, which the sort leaves alone when it is empty.
        sort = browser.ordersByRelevance ? [] : ItemTableLayout.sort(options, columns: columns, keepsGivenOrder: browser.keepsPlaceOrder)
        grouping = ItemTableLayout.grouping(options, columns: columns)
        // A place's own grouping is by the status's groups, as a board of mixed types is.
        groupMode = options.grouping == .automatic ? .statusGroups : options.grouping.mode
        hidesEmptyGroups = browser.hidesEmptyGroups
        calendar = browser.isViewPlace ? DateGroups.viewCalendar() : WeekStart.calendar(.current, in: browser.defaults)
    }

    /// The columns Add Sort offers: those of the types the view shows after its filters, in a sensible order.
    var sortChoices: [ItemTableColumn] {
        ItemTableLayout.sortChoices(from: columns, types: Set(kept.map(\.item.type)), catalogue: catalogue)
    }

    /// The columns a table can be filtered and grouped by: those with a few values to pick from, where some row
    /// holds one.
    var categoricalColumns: [ItemTableColumn] {
        columns.filter { column in column.isCategorical && allRows.contains { column.category(of: $0) != nil } }
    }
}
