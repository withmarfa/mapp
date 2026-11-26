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
    /// What a table draws of some rows: the first of them, where each stands among its parents, and how many are left.
    struct Slice: Equatable, Sendable {
        let rows: [ItemTableRow]
        let remaining: Int
        /// Where each of `rows` is drawn, in the same order, where any row nests; empty where none does.
        var places: [ItemNesting.Place] = []
    }

    /// One group's share of the place's page: its heading's group, and the rows of it that fit.
    struct GroupSlice: Equatable, Sendable {
        let group: ItemTableGroup
        let rows: [ItemTableRow]
        var places: [ItemNesting.Place] = []
    }

    private(set) var pages = 1

    /// The first pages of `rows`, nested as `nesting` says with the parents in `expanded` open. A page counts every row
    /// it draws, sub-items too; a closed parent's sub-items are drawn nowhere and count toward nothing.
    func slice(_ rows: [ItemTableRow], nesting: ItemNesting = .flat, expanded: Set<ItemID> = [], size: TablePageSize) -> Slice {
        let budget = pages * size.rawValue
        guard !nesting.isFlat else {
            let shown = min(rows.count, budget)
            return Slice(rows: Array(rows.prefix(shown)), remaining: rows.count - shown)
        }
        let drawn = nesting.drawn(expanded: expanded, limit: budget)
        return Slice(rows: drawn.places.map { rows[$0.index] }, remaining: drawn.total - drawn.places.count, places: drawn.places)
    }

    /// One page of a grouped place. Groups stay in order. Only as many item rows as the page holds are drawn, sub-items
    /// of an open parent among them (`nestings`, by group). A group the person folded away shows its heading and none of
    /// its rows, wherever it falls, and those rows are not part of the page. An open group whose first row is past the
    /// page is left out, and its rows count toward what is left.
    func slice(
        groups: [ItemTableGroup], nestings: [String: ItemNesting] = [:], collapsed: Set<String>, expanded: Set<ItemID> = [],
        size: TablePageSize
    ) -> (groups: [GroupSlice], remaining: Int) {
        var budget = pages * size.rawValue
        var shown: [GroupSlice] = []
        var remaining = 0
        var filling = true
        for group in groups {
            if collapsed.contains(group.id) {
                shown.append(GroupSlice(group: group, rows: []))
                continue
            }
            let nesting = nestings[group.id] ?? .flat
            let count = nesting.isFlat ? group.rows.count : nesting.drawnCount(expanded: expanded)
            if !filling || budget == 0 {
                filling = false
                remaining += count
                continue
            }
            let take = min(budget, count)
            if nesting.isFlat {
                shown.append(GroupSlice(group: group, rows: Array(group.rows.prefix(take))))
            } else {
                let places = nesting.drawn(expanded: expanded, limit: take).places
                shown.append(GroupSlice(group: group, rows: places.map { group.rows[$0.index] }, places: places))
            }
            budget -= take
            remaining += count - take
            if budget == 0 { filling = false }
        }
        return (shown, remaining)
    }

    /// Adds a page to the place.
    mutating func loadMore() { pages += 1 }

    /// Loads enough pages to show every one of `ids` that the table holds, as drawn with the parents in `expanded` open.
    /// A group the person folded away shows nothing, so it loads nothing; nor does a sub-item under a closed parent. Nil
    /// `groups` is a table that is not grouped.
    mutating func reveal(
        _ ids: Set<ItemID>, rows: [ItemTableRow], nesting: ItemNesting = .flat, groups: [ItemTableGroup]?,
        nestings: [String: ItemNesting] = [:], collapsed: Set<String>, expanded: Set<ItemID> = [], size: TablePageSize
    ) {
        guard !ids.isEmpty else { return }
        var remaining = ids
        var position = 0
        func reveal(_ rows: [ItemTableRow], _ nesting: ItemNesting) {
            let drawn = nesting.isFlat ? rows.map(\.id) : nesting.drawnIDs(expanded: expanded)
            for id in drawn {
                if remaining.remove(id) != nil {
                    pages = max(pages, position / size.rawValue + 1)
                    if remaining.isEmpty { return }
                }
                position += 1
            }
        }
        if let groups {
            for group in groups where !collapsed.contains(group.id) {
                reveal(group.rows, nestings[group.id] ?? .flat)
                if remaining.isEmpty { return }
            }
        } else {
            reveal(rows, nesting)
        }
    }
}

/// What a page count belongs to. Anything that changes the rows or their order, or the page size, starts again at
/// one page; an edit to an item, a folded group or the selection does not.
nonisolated struct TablePagingKey: Hashable, Sendable {
    let place: PlaceView
    let search: String
    let byRelevance: Bool
    let options: ItemTableOptions

    init(place: PlaceView, search: String, byRelevance: Bool, options: ItemTableOptions) {
        self.place = place
        self.search = search
        self.byRelevance = byRelevance
        var options = options
        options.collapsed = nil
        self.options = options
    }
}
