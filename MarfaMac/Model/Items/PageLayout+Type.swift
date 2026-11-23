import Foundation

nonisolated extension PageLayout {
    /// The rows a type's page can place when no item of it is at hand to say which of its relationships are in use: its type
    /// and last edit, the fields the catalogue gives it, its tags and Linked From. Where an item exists, `rows(of:…)` is
    /// the one that Customize Layout lists; this is the same without what only an item knows (its source, its parent link
    /// and the fields its header draws itself).
    static func rows(ofType type: TypeID, catalogue: Catalogue) -> [Row] {
        var rows = [
            Row(id: PagePlacement.type, label: String(localized: "Type"), symbol: "square.grid.2x2"),
            Row(id: PagePlacement.updated, label: String(localized: "Updated"), symbol: "calendar"),
        ]
        let info = catalogue.itemTypes[type]
        // The parent is pinned by default beside the status, so a type that can have one lists it, or it would count against
        // the four pins with no row to show for it.
        if LookSurface(type, in: catalogue).relations.contains(.parent) {
            rows.append(Row(id: PagePlacement.parent, label: Relation.parent.label(in: catalogue), symbol: "square.stack"))
        }
        rows += (info?.fields ?? []).filter { $0.key != info?.titleKey && $0.key != info?.bodyKey && $0.key != info?.linkField }
            .map { Row(id: $0.key, label: $0.label, symbol: symbol(of: $0)) }
        rows.append(Row(id: PagePlacement.tags, label: String(localized: "Tags"), symbol: "tag"))
        rows.append(Row(id: PagePlacement.linkedFrom, label: String(localized: "Linked From"), symbol: "arrow.down.left"))
        return rows
    }
}
