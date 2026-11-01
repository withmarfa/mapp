import Foundation

/// Every condition given must hold; an empty set or a nil places no condition.
nonisolated struct ItemQuery: Hashable, Sendable {
    var types: Set<TypeID> = []
    /// The item and every item below it through `parent-of`.
    var beneath: ItemID?
    /// Every tag given must be present.
    var tags: Set<String> = []
    var states: Set<ItemState> = [.active]
    var tier: Tier?
}
