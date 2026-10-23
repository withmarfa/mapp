import Foundation

nonisolated enum PlaceID: Hashable, Codable, Sendable {
    case inbox, all, favorites, archive, recentlyDeleted
    case type(TypeID)
    case folder(ItemID)
}

nonisolated struct PlaceEditing: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let rename = PlaceEditing(rawValue: 1 << 0)
    static let delete = PlaceEditing(rawValue: 1 << 1)
    static let reorder = PlaceEditing(rawValue: 1 << 2)
}

/// What dropping items on a place does to each of them.
nonisolated enum DropAction: Hashable, Sendable {
    case move(to: ContainerID?)
    case retier(Tier)
    case tag(String)
    case transition(ItemState)

    /// Nil where the item is already as the drop would leave it, so a drop makes no empty write or undo step.
    func write(for item: Item) -> ItemWrite? {
        switch self {
        case .move(let container):
            item.container == container ? nil : .move(item.id, to: container)
        case .retier(let tier):
            item.tier == tier ? nil : .retier(item.id, tier, base: item.version)
        case .tag(let tag):
            item.tags.contains(tag) ? nil : .tag(item.id, tag, on: true)
        case .transition(let state):
            item.state == state ? nil : .transition(item.id, state)
        }
    }
}

/// A sidebar entry, published by the source so no view needs to know which source is open.
nonisolated struct Place: Identifiable, Hashable, Sendable {
    enum Section: Hashable, Sendable {
        case library, favorites, types, folders, footer
    }

    let id: PlaceID
    var title: String
    var symbol: String
    var section: Section
    var query: ItemQuery
    var drop: DropAction?
    var editing: PlaceEditing = []
}
