import Foundation
import UniformTypeIdentifiers

nonisolated struct ItemDraft: Hashable, Sendable {
    var type: TypeID
    var title: String
    var body = ""
    var properties: [String: PropertyValue] = [:]
    var tags: Set<String> = []
    /// Nil leaves the tier to the source.
    var tier: Tier?
    var container: ContainerID?
    var parent: ItemID?
}

/// Written in the canonical direction; a source writes it at whichever end its type is written at.
nonisolated struct EdgeDraft: Hashable, Sendable {
    var type: String
    var source: ItemID
    var target: ItemID
}

nonisolated enum AttachmentSource: Hashable, Sendable {
    case file(URL)
    case data(Data, name: String, type: UTType)
}

nonisolated enum BodyMerge: Hashable, Sendable {
    /// Refused unless the item is still at the base version.
    case ifUnchanged
    /// Merged against the version the editor read, which may be older than the one the source now holds.
    case asRead
}

nonisolated enum PlaceWrite: Hashable, Sendable {
    case createFolder(ItemID, name: String)
    case rename(PlaceID, to: String)
    case delete(PlaceID)
    case reorder([PlaceID])
}

nonisolated enum ItemWrite: Hashable, Sendable {
    /// The app mints the id, so it can name the item before the source answers.
    case create(id: ItemID, ItemDraft)
    /// A nil value removes the property. `undoing` names the write whose side effects an undo puts back.
    case editProperties(ItemID, [String: PropertyValue?], base: ItemVersion, undoing: WriteID?)
    case editBody(ItemID, String, base: ItemVersion, merge: BodyMerge)
    case retype(ItemID, TypeID, base: ItemVersion)
    /// Marfa moves a row's tier as an update, which carries the version it read.
    case retier(ItemID, Tier, base: ItemVersion)
    case move(ItemID, to: ContainerID?)
    case transition(ItemID, ItemState)
    case purge(ItemID)
    case tag(ItemID, String, on: Bool)
    case link(EdgeDraft, undoing: WriteID?)
    case unlink(EdgeID)
    case attach(ItemID, AttachmentSource)
    case place(PlaceWrite)
}
