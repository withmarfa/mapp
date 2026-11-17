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

    static let none = ItemRelations()

    func items(of relation: Relation) -> [RelatedItem] {
        switch relation {
        case .parent: parent.map { [$0] } ?? []
        case .children: children
        case .collections: collections
        }
    }
}

extension ItemLibrary {
    /// The links `item` has among `wanted`, worked out from what the copy holds now. A link no look or column asks for is
    /// not read.
    func relations(of item: Item, wanting wanted: Set<Relation>) -> ItemRelations {
        guard !wanted.isEmpty else { return .none }
        var relations = ItemRelations()
        if wanted.contains(.parent) { relations.parent = item.parentID.flatMap(related) }
        if wanted.contains(.children) { relations.children = Self.ordered(childIDs(of: item.id).compactMap(related)) }
        if wanted.contains(.collections) { relations.collections = Self.ordered(item.collectionIDs.compactMap(related)) }
        return relations
    }

    /// The linked item as a chip draws it, or nil where it is not to be shown.
    private func related(_ id: ItemID) -> RelatedItem? {
        guard let other = item(id), other.state != .trashed, other.problem == nil else { return nil }
        return RelatedItem(id: id, title: other.displayTitle, icon: catalogue.icon(for: other.type))
    }

    /// By title, and by ID among equal titles, so the same links come first every time.
    private static func ordered(_ items: [RelatedItem]) -> [RelatedItem] {
        items.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id.rawValue < $1.id.rawValue
            }
        }
    }
}
