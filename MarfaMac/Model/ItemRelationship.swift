import Foundation

nonisolated struct ItemRelationshipTarget: Identifiable, Sendable {
    let title: String
    let itemID: ItemID?
    let resolution: ReferenceResolution
    /// Settings lists the item in Trash.
    var isDeleted = false
    var id: String { itemID?.rawValue ?? title }
    /// The title to show, as `Item.displayTitle`.
    var displayTitle: String { title.isEmpty ? String(localized: "Untitled") : title }

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
    var id: String { field }
}

/// One edge field an item's type may hold, its own or an inverse, as a row draws it (`ItemLibrary.relationFields(of:)`).
nonisolated struct RelationField: Identifiable, Sendable {
    enum Editability: Equatable, Sendable {
        case editable
        /// Why the row takes no change, in the person's words.
        case readOnly(String)
    }

    /// The start of the name of the end that points at the item: `inverse:` and the edge type.
    static let inversePrefix = "inverse:"

    /// What `ItemLibrary.changeLinks` takes: an edge type, its reverse name, or `inverse:` and the edge type.
    let field: String
    /// Marfa's name for the end the item holds (`EdgeTypeInfo.label(atTo:)`).
    let label: String
    /// How many links the item may hold here. The core judges it as a link is made.
    let cardinality: EdgeTypeInfo.Cardinality
    /// The types the far end admits, by identifier.
    let allowedTypes: [TypeID]
    let targets: [ItemRelationshipTarget]
    let editability: Editability
    var id: String { field }
}
