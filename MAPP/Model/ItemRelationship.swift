import Foundation

nonisolated struct ItemRelationshipTarget: Identifiable, Sendable {
    let title: String
    let itemID: ItemID?
    let resolution: NoteReferenceResolution
    var id: String { itemID?.rawValue ?? title }
}

nonisolated struct ItemRelationship: Identifiable, Sendable {
    let field: String
    let label: String
    let targets: [ItemRelationshipTarget]
    let isEditable: Bool
    let allowsMultiple: Bool
    var id: String { field }
}
