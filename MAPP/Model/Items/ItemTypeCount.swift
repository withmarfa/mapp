import Foundation

/// One of the catalogue's types that holds items, as the sidebar, Settings and the palette show it.
nonisolated struct ItemTypeCount: Identifiable, Hashable, Sendable {
    let id: TypeID
    /// The type's label, with its parent's in parentheses where another shown type has the same label.
    let label: String
    let symbol: String
    /// The items the type holds itself, never those of its subtypes, so the number is the length of the list the
    /// row opens.
    let count: Int
}

/// A type a new item can be, as its menu shows it.
nonisolated struct ItemTypeOption: Identifiable, Hashable, Sendable {
    let id: TypeID
    let label: String
    let symbol: String
}

nonisolated extension Catalogue {
    /// Whether `type` is the file type or a kind of file.
    func isFileType(_ type: TypeID) -> Bool {
        type == .file || isSubtype(type, ofAnyOf: [.file])
    }

    /// The label each of `types` goes by. A label two of them share gets its parent's label in parentheses,
    /// "Task (Ticket)", so the rows can be told apart.
    func displayLabels(for types: some Collection<TypeID>) -> [TypeID: String] {
        let labels = Dictionary(uniqueKeysWithValues: types.map { ($0, TypeSymbol.label(for: $0, in: self)) })
        let shared = Dictionary(grouping: types, by: { labels[$0] ?? "" }).filter { $0.value.count > 1 }
        return labels.reduce(into: [:]) { result, entry in
            let (type, label) = entry
            if shared[label] != nil, let parent = itemTypes[type]?.parent, itemTypes[parent] != nil {
                result[type] = "\(label) (\(TypeSymbol.label(for: parent, in: self)))"
            } else {
                result[type] = label
            }
        }
    }
}

extension ItemLibrary {
    /// Whether the catalogue has the project type, so the library has a Projects place even before it holds a project.
    var hasProjectType: Bool { catalogue.itemTypes[.project] != nil }

    /// The catalogue's types that directly hold active items, most items first, then by label. The project type is
    /// left out, since Projects has its own section, and so are the file types, which All Items and search reach.
    /// A type with no items is left out, and the sidebar shows it the first time the library holds one. The count is
    /// `count(in:)` of the type's own place, which lists the type's items and no subtype's.
    var itemTypeCounts: [ItemTypeCount] {
        let catalogue = catalogue
        let held = catalogue.itemTypes.keys.compactMap { type -> (TypeID, Int)? in
            guard type != .project, !catalogue.isFileType(type) else { return nil }
            let count = count(in: .itemType(type.rawValue))
            return count > 0 ? (type, count) : nil
        }
        let labels = catalogue.displayLabels(for: held.map(\.0))
        return held.map { type, count in
            ItemTypeCount(id: type, label: labels[type] ?? type.rawValue, symbol: TypeSymbol.name(for: type, in: catalogue), count: count)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }

    /// The types a new item can be, by label: every type in the catalogue except the file types, which are made by
    /// adding a file.
    var creatableTypes: [ItemTypeOption] {
        let catalogue = catalogue
        let types = catalogue.itemTypes.keys.filter { !catalogue.isFileType($0) && !$0.rawValue.hasPrefix("system.") }
        let labels = catalogue.displayLabels(for: types)
        return types.map { type in
            ItemTypeOption(id: type, label: labels[type] ?? type.rawValue, symbol: TypeSymbol.name(for: type, in: catalogue))
        }
        .sorted {
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }
}
