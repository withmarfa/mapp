import Foundation

nonisolated struct DigestChoices: Codable, Hashable, Sendable {
    static let lineCounts = 1...10
    var stack: Bool?
    var lineCount: Int?
    var pictures: Bool?

    var stacks: Bool { stack ?? true }
    var lines: Int { Self.lineCounts.contains(lineCount ?? 3) ? lineCount ?? 3 : 3 }
    var showsPictures: Bool { pictures ?? true }
}

nonisolated enum DigestLayout {
    static let order = ItemOrder(sort: .dateCreated, groupsByDate: false)

    enum Kind: String, Hashable, Sendable {
        case thread, excerpt
    }

    struct Relationship: Hashable, Sendable {
        let kind: Kind
        let target: ItemID

        init?(_ item: Item) {
            for edge in item.edgesOut {
                guard case .item(let id) = edge.to, id != item.id else { continue }
                switch edge.type {
                case MarfaMapping.threadEdge: kind = .thread
                case MarfaMapping.excerptEdge: kind = .excerpt
                default: continue
                }
                target = id
                return
            }
            return nil
        }
    }

    struct Pile: Identifiable, Sendable {
        enum ID: Hashable, Sendable {
            case item(ItemID), relationship(Relationship)
        }

        let id: ID
        let newest: Item
        var earlier: [Item] = []
    }

    struct Section: Identifiable, Sendable {
        let group: ItemGroup?
        let piles: [Pile]
        var id: ItemGroup? { group }
    }

    struct Display: Sendable {
        let place: PlaceView
        let sections: [Section]
        let topItems: [ItemID]
        let itemOrder: [ItemID]
        let itemIDs: Set<ItemID>

        init(place: PlaceView, sections: [Section]) {
            self.place = place
            self.sections = sections
            topItems = sections.flatMap { $0.piles.map(\.newest.id) }
            itemOrder = sections.flatMap { $0.piles.flatMap { [$0.newest.id] + $0.earlier.map(\.id) } }
            itemIDs = Set(itemOrder)
        }
    }

    /// Each pile takes the place of its newest member in the list's order. The relationship is its identity, so
    /// removing that member leaves the same pile, and two sources can contribute to the same thread.
    static func sections(_ sections: [ItemSection], stacking: Bool) -> [Section] {
        let visible = sections.filter { !$0.isCollapsed }
        var relationships: [ItemID: Relationship] = [:]
        var members: [Relationship: [Item]] = [:]
        if stacking {
            for section in visible {
                for item in section.items {
                    guard let relationship = Relationship(item) else { continue }
                    relationships[item.id] = relationship
                    members[relationship, default: []].append(item)
                }
            }
            for relationship in members.keys {
                members[relationship]?.sort {
                    ($0.occurred ?? $0.created, $0.created, $0.id.rawValue)
                        > ($1.occurred ?? $1.created, $1.created, $1.id.rawValue)
                }
            }
        }
        return visible.compactMap { section in
            let piles = section.items.compactMap { item -> Pile? in
                guard let relationship = relationships[item.id], let related = members[relationship] else {
                    return Pile(id: .item(item.id), newest: item)
                }
                guard related.first?.id == item.id else { return nil }
                return Pile(id: .relationship(relationship), newest: item, earlier: Array(related.dropFirst()))
            }
            return piles.isEmpty ? nil : Section(group: section.group, piles: piles)
        }
    }
}
