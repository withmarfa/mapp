import Foundation

nonisolated enum ContainerScope: Hashable, Sendable {
    /// Items in no container: in files mode, the files at the top of the notes folder.
    case root
    case container(ContainerID)
}

/// Every condition given must hold; an empty set or a nil places no condition.
nonisolated struct ItemQuery: Hashable, Sendable {
    var types: Set<TypeID> = []
    /// Marfa documents subtype expansion for search only, so the app expands it from the catalogue.
    var includesSubtypes = true
    /// The item and every item below it through `parent-of`.
    var beneath: ItemID?
    /// Every tag given must be present.
    var tags: Set<String> = []
    var states: Set<ItemState> = [.active]
    var tier: Tier?
    var container: ContainerScope?

    /// `descendants` holds the items below `beneath`, which only the caller's edge index can answer.
    func matches(_ item: Item, catalogue: Catalogue, descendants: Set<ItemID> = []) -> Bool {
        guard states.isEmpty || states.contains(item.state) else { return false }
        if let tier, item.tier != tier { return false }
        guard tags.isSubset(of: item.tags) else { return false }
        switch container {
        case nil: break
        case .root: if item.container != nil { return false }
        case .container(let id): if item.container != id { return false }
        }
        if let beneath, item.id != beneath, !descendants.contains(item.id) { return false }
        guard !types.isEmpty else { return true }
        if types.contains(item.type) { return true }
        return includesSubtypes && catalogue.isSubtype(item.type, ofAnyOf: types)
    }
}
