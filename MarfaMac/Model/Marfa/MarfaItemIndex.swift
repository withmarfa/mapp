import Foundation

/// Which items each place holds, and every edge in its canonical direction, kept up to date one item at a time so
/// a read costs what it returns rather than a pass over the library.
nonisolated struct MarfaItemIndex {
    /// An edge from its `from` end to its `to` end as its type names them, whichever end holds it.
    struct Link: Hashable, Sendable {
        let id: EdgeID
        let type: String
        let from: ItemID
        let to: ItemID
        let holder: ItemID
        var position: Double? = nil
    }

    /// Active and archived items, split by tier and state, so a place is counted without a pass over it.
    struct Split: Sendable {
        private var sets: [Tier: [ItemState: Set<ItemID>]] = [:]

        var isEmpty: Bool { sets.values.allSatisfy { $0.values.allSatisfy(\.isEmpty) } }

        mutating func insert(_ id: ItemID, tier: Tier, state: ItemState) {
            sets[tier, default: [:]][state, default: []].insert(id)
        }

        mutating func remove(_ id: ItemID, tier: Tier, state: ItemState) {
            sets[tier]?[state]?.remove(id)
        }

        func ids(in scope: ListScope, _ archived: ArchivedItems) -> Set<ItemID> {
            var found: Set<ItemID> = []
            for tier in Tier.allCases where scope.includes(tier) {
                for state in [ItemState.active, .archived] where archived.includes(state) {
                    found.formUnion(sets[tier]?[state] ?? [])
                }
            }
            return found
        }

        func count(in scope: ListScope, _ archived: ArchivedItems) -> Int {
            var count = 0
            for tier in Tier.allCases where scope.includes(tier) {
                for state in [ItemState.active, .archived] where archived.includes(state) {
                    count += sets[tier]?[state]?.count ?? 0
                }
            }
            return count
        }

        func contains(_ id: ItemID, in scope: ListScope, _ archived: ArchivedItems) -> Bool {
            Tier.allCases.contains { tier in
                scope.includes(tier) && [ItemState.active, .archived].contains { state in
                    archived.includes(state) && sets[tier]?[state]?.contains(id) == true
                }
            }
        }
    }

    private(set) var byState: [ItemState: Set<ItemID>] = [:]
    /// Every active and archived item.
    private(set) var listed = Split()
    private(set) var byType: [TypeID: Split] = [:]
    private(set) var bySource: [String: Split] = [:]
    /// Active and archived items tagged favorite.
    private(set) var favorites: Set<ItemID> = []
    /// How many active items carry each tag.
    private(set) var tagCounts: [String: Int] = [:]
    private(set) var links: [EdgeID: Link] = [:]
    /// The `attached-to` edges each file holds. A file with any is a part of the item it points at, so the lists leave
    /// it to that item's page; a file with none stands alone.
    private var attachments: [ItemID: Set<EdgeID>] = [:]
    private var linksFrom: [ItemID: Set<EdgeID>] = [:]
    private var linksTo: [ItemID: Set<EdgeID>] = [:]
    private var held: [ItemID: [EdgeID]] = [:]

    func ids(in state: ItemState) -> Set<ItemID> { byState[state] ?? [] }

    /// The active items of `type` alone, in both tiers.
    func active(ofType type: TypeID) -> Set<ItemID> { byType[type]?.ids(in: .all, .hidden) ?? [] }

    /// The files attached to an item the index holds, which the lists leave out (`standalone`).
    func attachedToHeld() -> [ItemID] {
        attachments.keys.filter(isAttachedToHeldItem)
    }

    /// `ids` without the files that are attached to an item the index holds, whatever state that item is in: a
    /// binned parent keeps its files out of the lists with it, as Marfa's bin does (`withmarfa/marfa#2498`). A file
    /// whose parent is not held (purged, or outside the slice) has nowhere to show, so it stays listed. Resolved here,
    /// at read time, so a parent arriving or leaving changes the answer without touching the file.
    func standalone(_ ids: Set<ItemID>) -> Set<ItemID> {
        attachments.isEmpty ? ids : ids.filter { !isAttachedToHeldItem($0) }
    }

    private func isAttachedToHeldItem(_ id: ItemID) -> Bool {
        attachments[id]?.contains { edge in links[edge].map { held[$0.to] != nil } ?? false } ?? false
    }

    mutating func insert(_ item: Item, catalogue: Catalogue) {
        byState[item.state, default: []].insert(item.id)
        if item.state != .trashed {
            listed.insert(item.id, tier: item.tier, state: item.state)
            byType[item.type, default: Split()].insert(item.id, tier: item.tier, state: item.state)
            if let source = item.source { bySource[source, default: Split()].insert(item.id, tier: item.tier, state: item.state) }
            if item.isFavorite { favorites.insert(item.id) }
        }
        if item.state == .active {
            for tag in item.tags { tagCounts[tag, default: 0] += 1 }
        }
        var holding: [EdgeID] = []
        for edge in item.edgesOut {
            guard let link = Self.link(edge, catalogue: catalogue) else { continue }
            links[link.id] = link
            linksFrom[link.from, default: []].insert(link.id)
            linksTo[link.to, default: []].insert(link.id)
            if link.type == MarfaMapping.attachmentEdge { attachments[link.from, default: []].insert(link.id) }
            holding.append(link.id)
        }
        held[item.id] = holding
    }

    mutating func remove(_ item: Item) {
        if item.state == .active {
            for tag in item.tags {
                if tagCounts[tag] == 1 { tagCounts[tag] = nil } else { tagCounts[tag]? -= 1 }
            }
        }
        byState[item.state]?.remove(item.id)
        listed.remove(item.id, tier: item.tier, state: item.state)
        byType[item.type]?.remove(item.id, tier: item.tier, state: item.state)
        if let source = item.source { bySource[source]?.remove(item.id, tier: item.tier, state: item.state) }
        favorites.remove(item.id)
        for id in held.removeValue(forKey: item.id) ?? [] {
            guard let link = links.removeValue(forKey: id) else { continue }
            linksFrom[link.from]?.remove(id)
            linksTo[link.to]?.remove(id)
            if link.type == MarfaMapping.attachmentEdge {
                attachments[link.from]?.remove(id)
                if attachments[link.from]?.isEmpty == true { attachments[link.from] = nil }
            }
        }
    }

    /// An edge sits with the item at the end its type is written at, under the reverse name there where the type
    /// has one; a type the catalogue does not know is taken as written at its from item.
    static func link(_ edge: Edge, catalogue: Catalogue) -> Link? {
        guard case .item(let other) = edge.to else { return nil }
        guard let (info, isReverse) = catalogue.edgeType(named: edge.type) else {
            return Link(id: edge.id, type: edge.type, from: edge.from, to: other, holder: edge.from, position: edge.position)
        }
        let atTo = isReverse || info.writtenFrom == .to
        return Link(
            id: edge.id, type: info.id, from: atTo ? other : edge.from, to: atTo ? edge.from : other,
            holder: edge.from, position: edge.position)
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

    func link(type: String, from: ItemID, to: ItemID) -> Link? {
        links(from: from, type: type).first { $0.to == to }
    }
}
