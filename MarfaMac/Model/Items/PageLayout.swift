import Foundation

/// The rows a type's page can place: what Settings > Layouts lists to pin under the title, and the symbol of each kind of
/// value. Pure, with no SwiftUI; a person's choices for them are `PagePlacements`.
nonisolated enum PageLayout {
    /// A row the person can place. `symbol` is the SF Symbol of the kind of value it holds.
    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let symbol: String
    }
}

nonisolated extension PageLayout {
    /// The rows the page can place for `item`, in their default order: the type's fields as the catalogue orders them
    /// (those `PageCustomization.fields` offers, with the parent after the status and one Location for the latitude, the
    /// longitude and a name for the place), its other relationships, its tags and Linked From. The type's own rows are
    /// there whether or not the item has a value, and a type with no fields has these built-in rows only. The latitude
    /// and longitude are rows of their own with `showsCoordinates`.
    static func rows(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, relationships: [ItemRelationship], catalogue: Catalogue,
        showsCoordinates: Bool = false
    ) -> [Row] {
        var rows: [Row] = []
        let offered = relationships.filter { !$0.field.hasPrefix("inverse:") }
        let parent = offered.first { $0.field == PagePlacement.parent }.map {
            Row(id: $0.field, label: $0.label, symbol: "square.stack")
        }
        var fields: [Row] = []
        let status = type?.statusField?.key
        let location = ItemLocation.of(type)
        let owned = location?.ownedKeys(showingCoordinates: showsCoordinates) ?? []
        var locationListed = false
        for field in PageCustomization.fields(of: item, type: type, hidden: hidden, catalogue: catalogue) {
            if let location, location.keys.contains(field.key) {
                // One row stands for the point and its name, where the first of them is.
                if !locationListed {
                    fields.append(Row(id: ItemLocation.rowID, label: String(localized: "Location"), symbol: ItemLocation.symbol))
                    locationListed = true
                }
                if owned.contains(field.key) { continue }
            }
            fields.append(Row(id: field.key, label: field.label, symbol: symbol(of: field)))
            if field.key == status, let parent { fields.append(parent) }
        }
        if let parent, !fields.contains(where: { $0.id == parent.id }) { fields.insert(parent, at: 0) }
        rows += fields
        rows += offered.filter { $0.field != PagePlacement.parent }.map { Row(id: $0.field, label: $0.label, symbol: "link") }
        rows.append(Row(id: PagePlacement.tags, label: String(localized: "Tags"), symbol: "tag"))
        rows.append(Row(id: PagePlacement.linkedFrom, label: String(localized: "Linked From"), symbol: "arrow.down.left"))
        return rows
    }

    /// The symbol of the value a field holds, as the page's rows draw it (`PropertyRow.Value.symbol`).
    static func symbol(of field: ItemTypeInfo.Field) -> String {
        switch field.kind {
        case .status: "circle.dotted"
        case .boolean: "checkmark.square"
        case .date: "calendar"
        case .choice: "list.bullet"
        case .number: "text.alignleft"
        case .list(let shape): shape.holdsPeople ? "person.2" : "list.bullet"
        case .text: field.format == .url ? "globe" : field.format == .email ? "envelope" : "text.alignleft"
        case .words: "list.bullet"
        case .other: "text.alignleft"
        }
    }
}
