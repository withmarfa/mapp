import Foundation

nonisolated struct DigestChoices: Codable, Hashable, Sendable {
    static let lineCounts = 1...10
    var stack: Bool?
    var lineCount: Int?
    var pictures: Bool?

    var stacks: Bool { stack ?? true }
    var lines: Int {
        guard let lineCount, Self.lineCounts.contains(lineCount) else { return 3 }
        return lineCount
    }
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

    struct Section: Sendable {
        let group: ItemGroup?
        let piles: [Pile]
    }

    struct Display: Sendable {
        let id = UUID()
        let place: PlaceView
        let sections: [Section]
        let counts: [Int]
        let topItems: [ItemID]
        let itemOrder: [ItemID]
        /// Earlier cards share their pile's position for paging.
        let positions: [ItemID: Int]
        let earlierMembers: [ItemID: Pile.ID]

        init(place: PlaceView, sections: [Section]) {
            self.place = place
            self.sections = sections
            counts = sections.map { $0.piles.count }
            var topItems: [ItemID] = []
            var itemOrder: [ItemID] = []
            var positions: [ItemID: Int] = [:]
            var earlierMembers: [ItemID: Pile.ID] = [:]
            for pile in sections.lazy.flatMap(\.piles) {
                let position = topItems.count
                topItems.append(pile.newest.id)
                itemOrder.append(pile.newest.id)
                positions[pile.newest.id] = position
                for item in pile.earlier {
                    itemOrder.append(item.id)
                    positions[item.id] = position
                    earlierMembers[item.id] = pile.id
                }
            }
            self.topItems = topItems
            self.itemOrder = itemOrder
            self.positions = positions
            self.earlierMembers = earlierMembers
        }

        func shows(_ id: ItemID, expanded: Set<Pile.ID>) -> Bool {
            guard positions[id] != nil else { return false }
            return earlierMembers[id].map(expanded.contains) ?? true
        }

        func visibleIDs(expanded: Set<Pile.ID>) -> [ItemID] {
            guard !expanded.isEmpty, !earlierMembers.isEmpty else { return topItems }
            return itemOrder.filter { earlierMembers[$0].map(expanded.contains) ?? true }
        }

        func drawn(_ drawn: ListDrawn) -> [DrawnPart] {
            drawn.parts(of: counts).map { part in
                let section = sections[part.section]
                return DrawnPart(group: section.group, piles: section.piles[part.items], part: part)
            }
        }
    }

    struct DrawnPart: Identifiable, Sendable {
        let group: ItemGroup?
        let piles: ArraySlice<Pile>
        let part: ListDrawn.Part

        var id: String { "\(part.run):\(part.section)" }
        var startsSection: Bool { part.startsSection }
        var endsRun: Bool { part.endsRun }
        var run: Int { part.run }
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
