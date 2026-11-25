import Foundation

nonisolated struct ItemDraft: Hashable, Sendable {
    var type: TypeID
    var title: String
    var body = ""
    var properties: [String: PropertyValue] = [:]
    var tags: Set<String> = []
    /// Nil leaves the tier to the source.
    var tier: Tier?
    var parent: ItemID?
}

/// Written in the canonical direction; a source writes it at whichever end its type is written at.
nonisolated struct EdgeDraft: Hashable, Sendable {
    var type: String
    var from: ItemID
    var to: ItemID
    /// The edge's `position` property, so an undone removal puts a collection member back where it was.
    var position: Double? = nil
    /// The edge's own id: minted for a new edge, and the one this Mac saw for an edge to remove.
    var id: EdgeID? = nil
}

nonisolated enum BodyMerge: Hashable, Sendable {
    /// Refused unless the item is still at the base version.
    case ifUnchanged
    /// Typed on the base version, which may be older than the one the source now holds, and merged against it.
    /// The first edit typed on a version is this.
    case asRead
    /// Typed on the person's own earlier edit of the text: laid over it while the source holds only that edit
    /// over the base, and otherwise merged against the version that edit was made on.
    case following
}

nonisolated enum ItemWrite: Hashable, Sendable {
    /// The app mints the id, so it can name the item before the source answers.
    case create(id: ItemID, ItemDraft)
    /// A nil value removes the property.
    case editProperties(ItemID, [String: PropertyValue?], base: ItemVersion)
    case editBody(ItemID, String, base: ItemVersion, merge: BodyMerge)
    /// Moves the item to another type, with the property changes the move makes in the same edit (`TypeChange`). A
    /// nil value removes the property.
    case retype(ItemID, TypeID, [String: PropertyValue?], base: ItemVersion)
    /// Marfa moves a row's tier as an update, which carries the version it read. Sent only while the copy shows the
    /// item in the other tier (`MarfaEngine.judge`).
    case retier(ItemID, Tier, base: ItemVersion)
    /// Archive, Unarchive, or Delete, sent only while the copy shows the item in `from`, or, where `from` is nil, out
    /// of Recently Deleted (`MarfaEngine.judge`).
    case transition(ItemID, ItemState, from: ItemState?)
    /// Out of Recently Deleted, to active, sent only while the copy shows the item there or does not hold it.
    case restore(ItemID)
    /// Sent at the version the person was shown, so an item changed elsewhere since is refused rather than erased.
    case purge(ItemID, version: ItemVersion)
    case tag(ItemID, String, on: Bool)
    /// Sent only while the copy shows no edge of its type between its ends (`MarfaEngine.judge(edge:)`).
    case link(EdgeDraft)
    /// Removes the edge the draft's `id` names. Sent only while the copy shows that edge with the draft's type and
    /// ends, since Marfa keeps an edge's id when another device moves it.
    case unlink(EdgeDraft)
    /// Replaces one end of an edge in one write, so the end that stays never holds no edge or two. Only an edge
    /// whose staying end holds one edge of its type can move. Sent only while the copy shows the edge between
    /// `from` and `stays`; one already at `to` is skipped, since the package queues nothing for it.
    case moveEdge(EdgeID, end: EdgeTypeInfo.End, to: ItemID, from: ItemID, stays: ItemID)
}
