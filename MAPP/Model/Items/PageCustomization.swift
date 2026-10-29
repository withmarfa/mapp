import Foundation

/// What a type's page can be customized for: the choices of `PagePlacements` reach the property block and
/// Linked From, which only some items draw.
enum PageCustomization {
    /// Whether choosing what the page shows means anything for `item`.
    static func isAvailable(for item: Item?) -> Bool {
        item.map { !$0.isFile } ?? false
    }

    /// The keys of `item`'s properties that its header draws itself, so showing or hiding them in the property
    /// block changes nothing.
    static func drawnKeys(of item: Item, in catalogue: Catalogue) -> Set<String> {
        // Whether an event can be placed on a calendar day is read from the item, so the keys follow it.
        PageHeaderLead(for: item, kind: PageHeaderKind.of(item.type, in: catalogue), body: nil, now: Date()).consumed
    }

    /// The fields the Customize Page sheet and the inspector's Show on Page offer for `item`: those the library
    /// does not keep for itself and the header does not draw.
    static func fields(of item: Item, type: ItemTypeInfo?, hidden: Set<String>, catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        let drawn = drawnKeys(of: item, in: catalogue)
        return (type?.fields ?? []).filter { !hidden.contains($0.key) && !drawn.contains($0.key) }
    }
}
