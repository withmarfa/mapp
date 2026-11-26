import Foundation

/// Sub-items under their parent, as a table or a list draws them: each item whose parent (`parent-of`) is listed beside it
/// stands under that parent, in the order the rows came in; every other item stands at the top. Worked out with no actor
/// from the rows in order, so a large place nests off the main actor with its sort.
///
/// - A child whose parent the filters, the search or the group leave out stands at the top, since nothing above it is
///   listed.
/// - An item stands once: an item has one parent, and a second row of the same item is left out.
/// - A `parent-of` cycle never recurses: the first item of the cycle, in the rows' order, stands at the top, and the rest
///   under it.
nonisolated struct ItemNesting: Equatable, Sendable {
    /// The items at the top, in order.
    private(set) var roots: [ItemID]
    /// The items under each parent, in order. An item with none has no entry.
    private(set) var children: [ItemID: [ItemID]]
    /// The parent each nested item stands under.
    private(set) var parents: [ItemID: ItemID]
    /// Where each item stands in the rows the nesting was made of, so a drawn place finds its row.
    private(set) var positions: [ItemID: Int]

    static let flat = ItemNesting(roots: [], children: [:], parents: [:], positions: [:])

    private init(roots: [ItemID], children: [ItemID: [ItemID]], parents: [ItemID: ItemID], positions: [ItemID: Int]) {
        self.roots = roots
        self.children = children
        self.parents = parents
        self.positions = positions
    }

    /// The nesting of `rows`, given in order as their ids and their parents' ids.
    init(_ rows: some Sequence<(id: ItemID, parent: ItemID?)>) {
        var order: [ItemID] = []
        var parentOf: [ItemID: ItemID] = [:]
        var positions: [ItemID: Int] = [:]
        for (index, row) in rows.enumerated() where positions[row.id] == nil {
            positions[row.id] = index
            order.append(row.id)
            if let parent = row.parent, parent != row.id { parentOf[row.id] = parent }
        }
        let seen = positions
        var offered: [ItemID: [ItemID]] = [:]
        for id in order {
            guard let parent = parentOf[id], seen[parent] != nil else { continue }
            offered[parent, default: []].append(id)
        }
        var roots: [ItemID] = []
        var children: [ItemID: [ItemID]] = [:]
        var parents: [ItemID: ItemID] = [:]
        var placed: Set<ItemID> = []
        func attach(_ root: ItemID) {
            roots.append(root)
            placed.insert(root)
            var stack = [root]
            while let node = stack.popLast() {
                let kids = (offered[node] ?? []).filter { placed.insert($0).inserted }
                guard !kids.isEmpty else { continue }
                children[node] = kids
                for kid in kids { parents[kid] = node }
                stack.append(contentsOf: kids)
            }
        }
        for id in order where parentOf[id].map({ seen[$0] == nil }) ?? true { attach(id) }
        // What is left stands in a cycle: each item's parent is listed and none reaches the top.
        if placed.count < order.count {
            for id in order where !placed.contains(id) { attach(id) }
            roots.sort { positions[$0, default: 0] < positions[$1, default: 0] }
        }
        self.init(roots: roots, children: children, parents: parents, positions: positions)
    }

    init(rows: [ItemTableRow]) {
        self.init(rows.lazy.map { (id: $0.id, parent: $0.item.parentID) })
    }

    init(items: [Item]) {
        self.init(items.lazy.map { (id: $0.id, parent: $0.parentID) })
    }

    /// Whether no item stands under another.
    var isFlat: Bool { children.isEmpty }

    /// Where an item is drawn: how deep, how many stand directly under it, and whether those are shown.
    struct Place: Hashable, Sendable {
        let id: ItemID
        /// Where its row stands in the rows the nesting was made of.
        let index: Int
        let depth: Int
        let children: Int
        let isExpanded: Bool
    }

    /// The items drawn with the parents in `expanded` open, in order, up to `limit`, and how many there are in all.
    func drawn(expanded: Set<ItemID>, limit: Int = .max) -> (places: [Place], total: Int) {
        var places: [Place] = []
        places.reserveCapacity(min(limit, roots.count))
        var stack: [(id: ItemID, depth: Int)] = roots.reversed().map { ($0, 0) }
        while places.count < limit, let next = stack.popLast() {
            let kids = children[next.id] ?? []
            let open = !kids.isEmpty && expanded.contains(next.id)
            places.append(Place(id: next.id, index: positions[next.id, default: 0], depth: next.depth, children: kids.count, isExpanded: open))
            if open { stack.append(contentsOf: kids.reversed().map { ($0, next.depth + 1) }) }
        }
        return (places, drawnCount(expanded: expanded))
    }

    /// How many items are drawn with the parents in `expanded` open, without walking those that are not.
    func drawnCount(expanded: Set<ItemID>) -> Int {
        var count = roots.count
        for id in expanded where isShown(id, expanded: expanded) { count += children[id]?.count ?? 0 }
        return count
    }

    /// Whether `id` is drawn: every parent above it is open.
    func isShown(_ id: ItemID, expanded: Set<ItemID>) -> Bool {
        var current = id
        var depth = 0
        while let parent = parents[current] {
            guard expanded.contains(parent), depth < parents.count else { return false }
            current = parent
            depth += 1
        }
        return true
    }

    /// The parents above `id`, nearest first.
    func ancestors(of id: ItemID) -> [ItemID] {
        var found: [ItemID] = []
        var current = id
        while let parent = parents[current], found.count < parents.count {
            found.append(parent)
            current = parent
        }
        return found
    }
}
