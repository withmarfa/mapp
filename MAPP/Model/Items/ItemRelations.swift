import Foundation

/// A link a look shows as a property: the item the link reaches, as a chip draws it.
nonisolated struct RelatedItem: Identifiable, Hashable, Sendable {
    let id: ItemID
    let title: String
    let icon: String?
}

/// A link a look can show, which Marfa holds as an edge: the item an item is filed under (`parent-of`, read from the
/// child end), the items filed under it, and the collections it is in (`in-collection`).
nonisolated enum Relation: String, CaseIterable, Hashable, Sendable {
    case parent, children, collections

    /// The words a look stores and exports it as, which a stored look reads the same in every version.
    var word: String { rawValue }

    /// Marfa's name for the link as this relation shows it, never reworded: the edge type's reverse label for the
    /// parent, its label for the children, the collection edge's label for the collections.
    func label(in catalogue: Catalogue) -> String {
        switch self {
        case .parent: catalogue.edgeTypes[MarfaMapping.parentEdge]?.reverseLabel ?? String(localized: "Parent")
        case .children: catalogue.edgeTypes[MarfaMapping.parentEdge]?.label ?? String(localized: "Children")
        case .collections: catalogue.edgeTypes[MarfaMapping.collectionEdge]?.label ?? String(localized: "In Collection")
        }
    }
}

/// What one item's links say, as the items they reach look now: plain values that a row, a card or a table cell draws, so
/// none of them reads the library. A linked item that is in Recently Deleted, that the copy does not hold or that the
/// library could not read is left out, and nothing names it by an id.
nonisolated struct ItemRelations: Hashable, Sendable {
    var parent: RelatedItem?
    var children: [RelatedItem] = []
    var collections: [RelatedItem] = []
    /// How many links a relation has where only its first few are held (`ItemLibrary.relations(of:wanting:limit:)`).
    /// A relation not named here holds all its links.
    var totals: [Relation: Int] = [:]
    /// What Marfa answered for the counts the look asks for. A count it has not answered, or cannot, is not here, so a row
    /// shows nothing for it (`CountFact`).
    var counts: [CountFact: ItemCountAnswer] = [:]

    static let none = ItemRelations()

    func items(of relation: Relation) -> [RelatedItem] {
        switch relation {
        case .parent: parent.map { [$0] } ?? []
        case .children: children
        case .collections: collections
        }
    }

    /// How many links the relation has, however many are held.
    func count(of relation: Relation) -> Int { totals[relation] ?? items(of: relation).count }
}

extension ItemLibrary {
    /// The links `item` has among `wanted`, worked out from what the copy holds now. A link no look or column asks for is
    /// not read.
    ///
    /// With a `limit`, the children and the collections hold only their first `limit` links in the usual order, found
    /// without sorting the rest, and `totals` says how many there are: what a row or a card needs to show a few and count
    /// the others.
    ///
    /// `counts` are the counts the look shows: each holds the last answer Marfa gave, and nothing where it has none, so a row
    /// draws first and is drawn again when the answer comes. Reading asks for nothing: the view that shows the count wants it
    /// when it appears (`ItemCounts.want`).
    func relations(of item: Item, wanting wanted: Set<Relation>, counts: Set<CountFact> = [], limit: Int? = nil) -> ItemRelations {
        guard !wanted.isEmpty || !counts.isEmpty else { return .none }
        var relations = ItemRelations()
        for count in counts {
            if let answer = self.counts.answer(of: item.id, count.query) { relations.counts[count] = answer }
        }
        if wanted.contains(.parent) { relations.parent = item.parentID.flatMap(related) }
        if wanted.contains(.children) {
            let (held, total) = Self.first(limit, of: childIDs(of: item.id).lazy.compactMap(related))
            relations.children = held
            if limit != nil { relations.totals[.children] = total }
        }
        if wanted.contains(.collections) {
            let (held, total) = Self.first(limit, of: item.collectionIDs.lazy.compactMap(related))
            relations.collections = held
            if limit != nil { relations.totals[.collections] = total }
        }
        return relations
    }

    /// The linked item as a chip draws it, or nil where it is not to be shown.
    private func related(_ id: ItemID) -> RelatedItem? {
        guard let other = item(id), other.state != .trashed, other.problem == nil else { return nil }
        return RelatedItem(id: id, title: other.displayTitle, icon: catalogue.icon(for: other.type))
    }

    /// The first `limit` of `items` by title, and by ID among equal titles, so the same links come first every time, and how
    /// many there are. With no limit, all of them in that order.
    private static func first(_ limit: Int?, of items: some Sequence<RelatedItem>) -> (items: [RelatedItem], total: Int) {
        guard let limit else {
            let all = Array(items).sorted(by: precedes)
            return (all, all.count)
        }
        var held: [RelatedItem] = []
        var total = 0
        for item in items {
            total += 1
            let place = held.firstIndex { precedes(item, $0) } ?? held.endIndex
            guard place < limit else { continue }
            held.insert(item, at: place)
            if held.count > limit { held.removeLast() }
        }
        return (held, total)
    }

    private static func precedes(_ lhs: RelatedItem, _ rhs: RelatedItem) -> Bool {
        switch lhs.title.localizedStandardCompare(rhs.title) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.rawValue < rhs.id.rawValue
        }
    }
}
