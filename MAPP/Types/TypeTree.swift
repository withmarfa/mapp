import Foundation

/// What the person selects in the list of types: an item type or an edge type. The two kinds have separate
/// namespaces, so an id alone could name either.
nonisolated enum TypeSelection: Hashable, Sendable {
    case item(TypeID)
    case edge(String)
}

extension EdgeTypeInfo {
    var selection: TypeSelection { .edge(id) }
}

/// A search over types, matched as typed and without regard to case or accents.
nonisolated struct TypeQuery: Sendable {
    private let needle: String

    /// Nil for text with nothing to match, which is no search at all.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        needle = trimmed
    }

    /// A type's id and label, and the name and label of each of its fields, inherited ones included, since the
    /// question a search answers is which types have a field.
    func matches(_ type: ItemTypeInfo) -> Bool {
        contains(type.id.rawValue) || contains(type.label)
            || type.fields.contains { contains($0.key) || contains($0.label) }
    }

    /// An edge type's id, label and reverse name, and the names of its own properties.
    func matches(_ edge: EdgeTypeInfo) -> Bool {
        contains(edge.id) || contains(edge.label) || edge.reverseName.map(contains) == true
            || edge.properties.contains { contains($0.key) || contains($0.label) }
    }

    private func contains(_ text: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: nil) != nil
    }
}

/// One item type in the list, with the types below it.
nonisolated struct TypeNode: Identifiable, Sendable {
    let type: ItemTypeInfo
    let depth: Int
    /// How many types sit directly below it in the catalogue, whatever a search leaves of them.
    let subtypeCount: Int
    /// False for a type shown only because a type below it matches.
    let matchesSearch: Bool
    /// Nil for a type with nothing below it, which is what a hierarchical `List` reads as a leaf.
    let children: [TypeNode]?

    var id: TypeSelection { .item(type.id) }
}

nonisolated enum TypeTree {
    /// The catalogue's item types as a tree by parent, in label order. With a query, only the types that match
    /// and the types above them, which stay for the context they give. A type whose parent is not in the
    /// catalogue stands at the top, and so does one chosen from a loop of parents, which has no top of its own.
    static func nodes(in catalogue: Catalogue, matching query: TypeQuery? = nil) -> [TypeNode] {
        var below: [TypeID: [ItemTypeInfo]] = [:]
        var top: [ItemTypeInfo] = []
        for type in catalogue.itemTypes.values {
            if let parent = type.parent, parent != type.id, catalogue.itemTypes[parent] != nil {
                below[parent, default: []].append(type)
            } else {
                top.append(type)
            }
        }
        var placed: Set<TypeID> = []

        func build(_ type: ItemTypeInfo, depth: Int) -> TypeNode? {
            placed.insert(type.id)
            let kids = ordered(below[type.id, default: []].filter { !placed.contains($0.id) })
            let children = kids.compactMap { placed.contains($0.id) ? nil : build($0, depth: depth + 1) }
            let matches = query?.matches(type) ?? true
            guard matches || !children.isEmpty else { return nil }
            return TypeNode(
                type: type, depth: depth, subtypeCount: kids.count, matchesSearch: matches,
                children: children.isEmpty ? nil : children)
        }

        var nodes = ordered(top).compactMap { build($0, depth: 0) }
        for type in ordered(catalogue.itemTypes.values.filter { !placed.contains($0.id) }) where !placed.contains(type.id) {
            if let node = build(type, depth: 0) { nodes.append(node) }
        }
        return nodes
    }

    /// The tree in reading order, for a list that shows it open throughout.
    static func flattened(_ nodes: [TypeNode]) -> [TypeNode] {
        nodes.flatMap { [$0] + flattened($0.children ?? []) }
    }

    static func ordered(_ types: [ItemTypeInfo]) -> [ItemTypeInfo] {
        types.sorted { order($0.label, $0.id.rawValue, $1.label, $1.id.rawValue) }
    }

    static func ordered(_ edges: [EdgeTypeInfo]) -> [EdgeTypeInfo] {
        edges.sorted { order($0.label, $0.id, $1.label, $1.id) }
    }

    private static func order(_ label: String, _ id: String, _ otherLabel: String, _ otherID: String) -> Bool {
        switch label.localizedStandardCompare(otherLabel) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: id < otherID
        }
    }
}
