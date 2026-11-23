import Foundation

/// How many rows the table shows at first, and adds each time the person asks for more.
nonisolated enum TablePageSize: Int, CaseIterable, Hashable, Sendable {
    case twentyFive = 25, fifty = 50, oneHundred = 100, twoHundred = 200

    static let standard = TablePageSize.fifty
}

/// How many pages of rows the table has loaded, as the person asked for them. A page is of the whole place, grouped
/// or not. Sorting, filtering and grouping have already used every row by the time a page is cut, so a page is only
/// what the table draws.
nonisolated struct TablePaging: Hashable, Sendable {
    /// What a table draws of some rows: the first of them, and how many are left.
    struct Slice: Equatable, Sendable {
        let rows: [ItemTableRow]
        let remaining: Int
    }

    /// One group's share of the place's page: its heading's group, and the rows of it that fit.
    struct GroupSlice: Equatable, Sendable {
        let group: ItemTableGroup
        let rows: [ItemTableRow]
    }

    private(set) var pages = 1

    func slice(_ rows: [ItemTableRow], size: TablePageSize) -> Slice {
        let shown = min(rows.count, pages * size.rawValue)
        return Slice(rows: Array(rows.prefix(shown)), remaining: rows.count - shown)
    }

    /// One page of a grouped place. Groups stay in order. Only as many item rows as the page holds are drawn, and a
    /// group that begins after the page is left out. A group the person folded away shows its heading and none of
    /// its rows, and those rows are not part of the page.
    func slice(groups: [ItemTableGroup], collapsed: Set<String>, size: TablePageSize) -> (groups: [GroupSlice], remaining: Int) {
        var budget = pages * size.rawValue
        var shown: [GroupSlice] = []
        var remaining = 0
        var filling = true
        for group in groups {
            if collapsed.contains(group.id) {
                if filling { shown.append(GroupSlice(group: group, rows: [])) }
                continue
            }
            if !filling || budget == 0 {
                filling = false
                remaining += group.rows.count
                continue
            }
            let take = min(budget, group.rows.count)
            shown.append(GroupSlice(group: group, rows: Array(group.rows.prefix(take))))
            budget -= take
            remaining += group.rows.count - take
            if budget == 0 { filling = false }
        }
        return (shown, remaining)
    }

    /// Adds a page to the place.
    mutating func loadMore() { pages += 1 }

    /// Loads enough pages to show every one of `ids` that the table holds. A group the person folded away shows
    /// nothing, so it loads nothing. Nil `groups` is a table that is not grouped.
    mutating func reveal(
        _ ids: Set<ItemID>, rows: [ItemTableRow], groups: [ItemTableGroup]?, collapsed: Set<String>, size: TablePageSize
    ) {
        guard !ids.isEmpty else { return }
        let flat = groups.map { listed in listed.filter { !collapsed.contains($0.id) }.flatMap(\.rows) } ?? rows
        var needed = 1
        for (index, row) in flat.enumerated() where ids.contains(row.id) {
            needed = max(needed, index / size.rawValue + 1)
        }
        pages = max(pages, needed)
    }
}

/// What a page count belongs to. Anything that changes the rows or their order, or the page size, starts again at
/// one page; an edit to an item, a folded group or the selection does not.
nonisolated struct TablePagingKey: Hashable, Sendable {
    let place: SidebarItem
    let search: String
    let byRelevance: Bool
    let options: ItemTableOptions

    init(place: SidebarItem, search: String, byRelevance: Bool, options: ItemTableOptions) {
        self.place = place
        self.search = search
        self.byRelevance = byRelevance
        var options = options
        options.collapsed = nil
        self.options = options
    }
}
