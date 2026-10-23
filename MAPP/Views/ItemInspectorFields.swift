import Foundation

/// Which of an item's fields the inspector lists as properties to edit. The title is the page's heading and the
/// text is the page's content, so neither is a property here; a file's blob reference, kind and length are facts
/// the library keeps for the file, shown as Kind and Size under Details or not at all.
nonisolated enum InspectorFields {
    /// The keys the inspector never lists as an editable property or as one of the item's other properties.
    static func hiddenKeys(of item: Item, type: ItemTypeInfo?) -> Set<String> {
        var keys: Set<String> = []
        if case .property(let key) = item.titleRule { keys.insert(key) }
        if let key = type?.titleKey { keys.insert(key) }
        if let key = type?.bodyKey { keys.insert(key) }
        if case .file = item.content {
            keys.formUnion([MarfaMapping.blobField, MarfaMapping.mimeTypeField, MarfaMapping.sizeField])
        }
        return keys
    }

    /// The type's fields the inspector lists under Properties, in the catalogue's order. An empty field that
    /// cannot be added to is not worth a row.
    static func properties(of item: Item, type: ItemTypeInfo?) -> [ItemTypeInfo.Field] {
        let hidden = hiddenKeys(of: item, type: type)
        return (type?.fields ?? []).filter { field in
            if hidden.contains(field.key) { return false }
            if item.value(of: field.key) != nil { return true }
            if case .other = field.kind { return false }
            return item.isEditable
        }
    }

    /// Every property the inspector lists elsewhere or never: what the type names, what is hidden, and the
    /// bookkeeping Marfa adds to an item.
    static func accountedFor(item: Item, type: ItemTypeInfo?) -> Set<String> {
        Set((type?.fields ?? []).map(\.key)).union(hiddenKeys(of: item, type: type)).union(["title", "type", "marfa_id", "marfa_version"])
    }
}
