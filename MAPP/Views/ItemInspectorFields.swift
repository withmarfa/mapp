import Foundation

/// Which of an item's fields the inspector lists as properties to edit. The title is the page's heading and the
/// text is the page's content, so neither is a property here; a file's blob reference, kind and length are facts
/// the library keeps for the file, shown as Kind and Size under Details or not at all. The library says which keys
/// those are (`ItemLibrary.hiddenPropertyKeys(of:)`), since it alone knows how it keeps them.
nonisolated enum InspectorFields {
    /// The type's fields the inspector lists under Properties, in the catalogue's order. An empty field that
    /// cannot be added to is not worth a row.
    static func properties(of item: Item, type: ItemTypeInfo?, hidden: Set<String>) -> [ItemTypeInfo.Field] {
        (type?.fields ?? []).filter { field in
            if hidden.contains(field.key) { return false }
            if item.value(of: field.key) != nil { return true }
            if case .other = field.kind { return false }
            return item.isEditable
        }
    }

    /// Every property the inspector lists elsewhere or never: what the type names, what is hidden, and the
    /// bookkeeping Marfa adds to an item.
    static func accountedFor(type: ItemTypeInfo?, hidden: Set<String>) -> Set<String> {
        Set((type?.fields ?? []).map(\.key)).union(hidden).union(["title", "type", "marfa_id", "marfa_version"])
    }
}
