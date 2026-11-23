import Foundation

/// How many rows the table shows at first, and adds each time the person asks for more.
nonisolated enum TablePageSize: Int, CaseIterable, Hashable, Sendable {
    case twentyFive = 25, fifty = 50, oneHundred = 100, twoHundred = 200

    static let standard = TablePageSize.fifty
}

/// How many pages of rows the table has loaded, as the person asked for them: one for the whole table, or one for
/// each group when it is grouped. Sorting, filtering and grouping have already used every row by the time a page
/// is cut, so a page is only what the table draws.
nonisolated struct TablePaging: Hashable, Sendable {
    /// What a table draws of some rows: the first of them, and how many are left.
    struct Slice: Equatable, Sendable {
        let rows: [ItemTableRow]
        let remaining: Int
    }

    private(set) var pages = 1
    private(set) var groupPages: [String: Int] = [:]

    func pages(of group: String?) -> Int {
        group.map { groupPages[$0, default: 1] } ?? pages
    }

    func slice(_ rows: [ItemTableRow], size: TablePageSize, group: String? = nil) -> Slice {
        let shown = min(rows.count, pages(of: group) * size.rawValue)
        return Slice(rows: Array(rows.prefix(shown)), remaining: rows.count - shown)
    }

    /// Adds a page to the whole table, or to one group.
    mutating func loadMore(group: String? = nil) {
        if let group { groupPages[group, default: 1] += 1 } else { pages += 1 }
    }

    /// Loads enough pages to show every one of `ids` that the table holds. A group the person folded away shows
    /// nothing, so it loads nothing. Nil `groups` is a table that is not grouped.
    mutating func reveal(
        _ ids: Set<ItemID>, rows: [ItemTableRow], groups: [ItemTableGroup]?, collapsed: Set<String>, size: TablePageSize
    ) {
        guard !ids.isEmpty else { return }
        func pagesNeeded(_ rows: [ItemTableRow]) -> Int {
            var needed = 1
            for (index, row) in rows.enumerated() where ids.contains(row.id) {
                needed = max(needed, index / size.rawValue + 1)
            }
            return needed
        }
        guard let groups else {
            pages = max(pages, pagesNeeded(rows))
            return
        }
        for group in groups where !collapsed.contains(group.id) {
            groupPages[group.id] = max(groupPages[group.id, default: 1], pagesNeeded(group.rows))
        }
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
