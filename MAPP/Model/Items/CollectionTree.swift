import Foundation

/// An item other items are filed under (`child-of`), as the sidebar's Collections section lists it. Any type can be
/// one: what makes a collection is that something is filed under it, so the section reads the same on any Marfa.
nonisolated struct CollectionNode: Identifiable, Hashable, Sendable {
    let id: ItemID
    let title: String
    let symbol: String
    /// The collections filed directly under this one. The sidebar shows two levels, as the Human Interface
    /// Guidelines advise; deeper ones are reached by opening a collection.
    let children: [CollectionNode]
}

extension ItemLibrary {
    /// The collections filed under nothing, each with the collections filed directly under it, both by title. An
    /// item filed under one that is not active counts as filed under nothing, so its collection is not lost.
    var collectionTree: [CollectionNode] {
        let active = items(in: .allNotes).filter { !$0.isFile }
        let ids = Set(active.map(\.id))
        var parent: [ItemID: ItemID] = [:]
        var filed: [ItemID: [Item]] = [:]
        for item in active {
            guard let id = item.parentID, id != item.id, ids.contains(id) else { continue }
            parent[item.id] = id
            filed[id, default: []].append(item)
        }
        let catalogue = catalogue
        func node(_ item: Item, depth: Int) -> CollectionNode {
            let below = depth > 0 ? [] : (filed[item.id] ?? []).filter { filed[$0.id] != nil }
            return CollectionNode(
                id: item.id, title: item.title, symbol: TypeSymbol.name(for: item.type, in: catalogue),
                children: Self.byTitle(below).map { node($0, depth: depth + 1) })
        }
        let tops = active.filter { filed[$0.id] != nil && parent[$0.id] == nil }
        return Self.byTitle(tops).map { node($0, depth: 0) }
    }

    private static func byTitle(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id.rawValue < b.id.rawValue : order == .orderedAscending
        }
    }
}

nonisolated extension Item {
    /// The item this one is filed under: the target of its `child-of` edge.
    var parentID: ItemID? {
        edgesOut.lazy.compactMap { edge -> ItemID? in
            guard edge.type == "child-of", case .item(let id) = edge.target else { return nil }
            return id
        }.first
    }
}
