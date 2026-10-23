import Foundation

/// One of the catalogue's types that holds items, with the label people read and the number of items its place lists.
nonisolated struct ItemTypeCount: Identifiable, Hashable, Sendable {
    let id: TypeID
    let label: String
    /// The items in the type's place, which is what the list shows when the type is chosen: a Marfa library lists
    /// the items of its subtypes too (`types/listing-subtree`), a folder library lists the type's own.
    let count: Int
}

extension ItemLibrary {
    /// Whether the catalogue has the project type, so the library has a Projects place even before it holds a project.
    var hasProjectType: Bool { catalogue.itemTypes[.project] != nil }

    /// The catalogue's types that hold active items, by label. A type with none is left out, and the sidebar shows
    /// a type the first time the library holds an item of it. The count is `count(in:)` of the type's place, so a
    /// row's number is always the length of the list it opens.
    var itemTypeCounts: [ItemTypeCount] {
        catalogue.itemTypes.values.compactMap { info in
            let count = count(in: .itemType(info.id.rawValue))
            return count > 0 ? ItemTypeCount(id: info.id, label: info.label, count: count) : nil
        }
        .sorted {
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }
}
