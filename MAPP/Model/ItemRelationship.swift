import Foundation

nonisolated struct ItemRelationshipTarget: Identifiable, Sendable {
    let title: String
    let itemID: ItemID?
    let resolution: NoteReferenceResolution
    /// The item is in Recently Deleted. It still opens, there.
    var isDeleted = false
    var id: String { itemID?.rawValue ?? title }

    /// Whether the row can open an item: a link whose item the library does not hold has an ID to remove it by and
    /// nothing to open.
    var isOpenable: Bool {
        guard itemID != nil, case .resolved = resolution else { return false }
        return true
    }
}

nonisolated struct ItemRelationship: Identifiable, Sendable {
    let field: String
    let label: String
    let targets: [ItemRelationshipTarget]
    let isEditable: Bool
    let allowsMultiple: Bool
    var id: String { field }
}

/// One list of links in an item's inspector: a relationship, or the links in its content.
nonisolated struct LinkGroup: Hashable, Sendable {
    let item: ItemID
    let field: String

    /// The group of links in the item's content, which no relationship field names.
    static func content(of item: ItemID) -> LinkGroup { LinkGroup(item: item, field: "#content") }
}

/// A group of links draws this many before the person asks for the rest, so an item that hundreds of others link
/// to does not become hundreds of rows.
nonisolated enum LinkLimit {
    static let limit = 20

    /// The links to draw, and how many are left out until the group is expanded.
    static func split<Link>(_ links: [Link], expanded: Bool) -> (shown: ArraySlice<Link>, hidden: Int) {
        guard !expanded, links.count > limit else { return (links[...], 0) }
        return (links.prefix(limit), links.count - limit)
    }
}
