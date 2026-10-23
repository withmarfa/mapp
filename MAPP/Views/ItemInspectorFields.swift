import Foundation

/// Which of an item's fields the inspector lists as properties to edit. The title is the page's heading and the
/// text is the page's content, so neither is a property here; a file's blob reference, kind and length are facts
/// the library keeps for the file, shown as Kind and Size under Details or not at all. The library says which keys
/// those are (`ItemLibrary.hiddenPropertyKeys(of:)`), since it alone knows how it keeps them.
nonisolated enum InspectorFields {
    /// Whether a value says anything. A cleared field reads as no value, whether the source drops it or keeps it
    /// empty.
    static func hasValue(_ value: PropertyValue?) -> Bool {
        switch value {
        case nil, .null: false
        case .string(let text)?: !text.isEmpty
        case .array(let values)?: !values.isEmpty
        case .object(let fields)?: !fields.isEmpty
        case .bool?, .number?: true
        }
    }

    /// The type's fields the inspector lists under Properties, in the catalogue's order: those with a value, and
    /// those `revealed`, which the person added or cleared while the inspector showed this item, so a row does not
    /// jump away while they work on it.
    static func properties(of item: Item, type: ItemTypeInfo?, hidden: Set<String>, revealed: Set<String> = []) -> [ItemTypeInfo.Field] {
        (type?.fields ?? []).filter { field in
            if hidden.contains(field.key) { return false }
            return hasValue(item.value(of: field.key)) || (item.isEditable && revealed.contains(field.key))
        }
    }

    /// The empty fields the Add Property menu offers, in the catalogue's order: those the item can take a value
    /// for and the inspector does not list yet. A list or an object is shown but not edited, so it is not offered.
    static func addable(of item: Item, type: ItemTypeInfo?, hidden: Set<String>, revealed: Set<String> = []) -> [ItemTypeInfo.Field] {
        guard item.isEditable else { return [] }
        let listed = Set(properties(of: item, type: type, hidden: hidden, revealed: revealed).map(\.key))
        return (type?.fields ?? []).filter { field in
            if hidden.contains(field.key) || listed.contains(field.key) { return false }
            if case .other = field.kind { return false }
            return true
        }
    }

    /// Every property the inspector lists elsewhere or never: what the type names, what is hidden, and the
    /// bookkeeping Marfa adds to an item.
    static func accountedFor(type: ItemTypeInfo?, hidden: Set<String>) -> Set<String> {
        Set((type?.fields ?? []).map(\.key)).union(hidden).union(["title", "type", "marfa_id", "marfa_version"])
    }
}
