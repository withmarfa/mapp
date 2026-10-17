import Foundation

/// Which items each place holds, and every edge in its canonical direction, kept up to date one item at a time so
/// a read costs what it returns rather than a pass over the library.
nonisolated struct MarfaItemIndex {
    /// An edge from its source to its target as its type names them, whichever end holds it.
    struct Link: Hashable, Sendable {
        let id: EdgeID
        let type: String
        let source: ItemID
        let target: ItemID
        let holder: ItemID
    }

    private(set) var byState: [ItemState: Set<ItemID>] = [:]
    private(set) var activeByType: [TypeID: Set<ItemID>] = [:]
    private(set) var favorites: Set<ItemID> = []
    /// Active items in the feed tier, which the Inbox shows.
    private(set) var feed: Set<ItemID> = []
    private(set) var links: [EdgeID: Link] = [:]
    private var linksFrom: [ItemID: Set<EdgeID>] = [:]
    private var linksTo: [ItemID: Set<EdgeID>] = [:]
    private var held: [ItemID: [EdgeID]] = [:]

    func ids(in state: ItemState) -> Set<ItemID> { byState[state] ?? [] }

    mutating func insert(_ item: Item, catalogue: Catalogue) {
        byState[item.state, default: []].insert(item.id)
        if item.state == .active {
            activeByType[item.type, default: []].insert(item.id)
            if item.isFavorite { favorites.insert(item.id) }
            if item.tier == .feed { feed.insert(item.id) }
        }
        var holding: [EdgeID] = []
        for edge in item.edgesOut {
            guard let link = Self.link(edge, catalogue: catalogue) else { continue }
            links[link.id] = link
            linksFrom[link.source, default: []].insert(link.id)
            linksTo[link.target, default: []].insert(link.id)
            holding.append(link.id)
        }
        held[item.id] = holding
    }

    mutating func remove(_ item: Item) {
        byState[item.state]?.remove(item.id)
        activeByType[item.type]?.remove(item.id)
        favorites.remove(item.id)
        feed.remove(item.id)
        for id in held.removeValue(forKey: item.id) ?? [] {
            guard let link = links.removeValue(forKey: id) else { continue }
            linksFrom[link.source]?.remove(id)
            linksTo[link.target]?.remove(id)
        }
    }

    /// An edge sits with the item at the end its type is written at, under the reverse name there where the type
    /// has one; a type the catalogue does not know is taken as written at its source.
    static func link(_ edge: Edge, catalogue: Catalogue) -> Link? {
        guard case .item(let other) = edge.target else { return nil }
        guard let (info, isReverse) = catalogue.edgeType(named: edge.type) else {
            return Link(id: edge.id, type: edge.type, source: edge.source, target: other, holder: edge.source)
        }
        let atTarget = isReverse || info.writtenAt == .target
        return Link(
            id: edge.id, type: info.id, source: atTarget ? other : edge.source, target: atTarget ? edge.source : other,
            holder: edge.source)
    }

    func links(from id: ItemID, type: String) -> [Link] {
        (linksFrom[id] ?? []).compactMap { links[$0] }.filter { $0.type == type }
    }

    func links(to id: ItemID, type: String) -> [Link] {
        (linksTo[id] ?? []).compactMap { links[$0] }.filter { $0.type == type }
    }

    /// Every edge touching the item, either way.
    func links(touching id: ItemID) -> [Link] {
        (linksFrom[id] ?? []).union(linksTo[id] ?? []).compactMap { links[$0] }
    }

    func link(type: String, source: ItemID, target: ItemID) -> Link? {
        links(from: source, type: type).first { $0.target == target }
    }

    /// Every item reached from `id` following `type` from source to target, not including `id` unless a cycle
    /// leads back to it.
    func reachable(from id: ItemID, type: String) -> Set<ItemID> {
        walk(from: id) { links(from: $0, type: type).map(\.target) }
    }

    /// Every item from which `id` is reached following `type`.
    func reaching(_ id: ItemID, type: String) -> Set<ItemID> {
        walk(from: id) { links(to: $0, type: type).map(\.source) }
    }

    private func walk(from start: ItemID, next: (ItemID) -> [ItemID]) -> Set<ItemID> {
        var found: Set<ItemID> = []
        var pending = [start]
        while let current = pending.popLast() {
            for other in next(current) where found.insert(other).inserted {
                pending.append(other)
            }
        }
        return found
    }
}
