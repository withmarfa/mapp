import Foundation

nonisolated struct ItemTypeInfo: Identifiable, Hashable, Sendable {
    struct Field: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case text, number, boolean, date
            case choice([String])
            /// A shape the app shows but does not edit, such as a list or an object.
            case other
        }

        let key: String
        let label: String
        let kind: Kind
        /// The type that declares the field, which is an ancestor for an inherited one.
        let declaredBy: TypeID
        var required = false
        var description: String?
        var id: String { key }
    }

    let id: TypeID
    let label: String
    /// Inherited fields included, in the order they are shown.
    let fields: [Field]
    /// The property holding the title, where the title is not the body's first line.
    let titleField: String?
    let bodyField: String?
    let parent: TypeID?
    var description: String?
    /// A files library's types have none.
    var version: Int64?
    var roles: [String] = []
    /// The types this one is a structural superset of, so it can stand where they are accepted.
    var compatibleWith: [TypeID] = []
}

nonisolated struct EdgeTypeInfo: Identifiable, Hashable, Sendable {
    enum End: Hashable, Sendable { case source, target }

    enum Cardinality: Hashable, Sendable { case one, many }

    /// What deleting an item does to the item at the other end of one of its edges.
    enum CascadeOnDelete: Hashable, Sendable { case cascade, orphan, block }

    let id: String
    let label: String
    /// The name it is written under at its target, such as `child-of` for `parent-of`.
    let reverseName: String?
    /// How many of this edge the end it is written at may hold, which decides whether its field takes a list.
    let cardinality: Cardinality
    let writtenAt: End
    /// The types each end may be; an empty set allows any.
    let sourceTypes: Set<TypeID>
    let targetTypes: Set<TypeID>
    var description: String?
    /// How many of this edge the end it is not written at may hold.
    var reverseCardinality: Cardinality = .many
    var cascadeOnDelete: CascadeOnDelete = .orphan
    var properties: [ItemTypeInfo.Field] = []
}

nonisolated struct Catalogue: Hashable, Sendable {
    var itemTypes: [TypeID: ItemTypeInfo]
    var edgeTypes: [String: EdgeTypeInfo]

    init(itemTypes: [ItemTypeInfo] = [], edgeTypes: [EdgeTypeInfo] = []) {
        self.itemTypes = Dictionary(itemTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.edgeTypes = Dictionary(edgeTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Every type below `type` through `parent`, not including `type` itself.
    func descendants(of type: TypeID) -> Set<TypeID> {
        var children: [TypeID: [TypeID]] = [:]
        for info in itemTypes.values {
            if let parent = info.parent { children[parent, default: []].append(info.id) }
        }
        var found: Set<TypeID> = []
        var pending = [type]
        while let current = pending.popLast() {
            for child in children[current, default: []] where child != type && found.insert(child).inserted {
                pending.append(child)
            }
        }
        return found
    }

    /// Whether `type` is below one of `types`; walking up is cheaper than expanding each of them.
    func isSubtype(_ type: TypeID, ofAnyOf types: Set<TypeID>) -> Bool {
        var visited: Set<TypeID> = []
        var current: TypeID? = itemTypes[type]?.parent
        while let ancestor = current, visited.insert(ancestor).inserted {
            if types.contains(ancestor) { return true }
            current = itemTypes[ancestor]?.parent
        }
        return false
    }

    /// The edge type an item writes under `name`, and whether `name` is its reverse.
    func edgeType(named name: String) -> (info: EdgeTypeInfo, isReverse: Bool)? {
        if let info = edgeTypes[name] { return (info, false) }
        return edgeTypes.values.first { $0.reverseName == name }.map { ($0, true) }
    }

    /// The type's fields first, in the catalogue's order, then the rest as given.
    func ordered(_ properties: [Property], for type: TypeID) -> [Property] {
        let fields = itemTypes[type]?.fields.map(\.key) ?? []
        let known = fields.compactMap { key in properties.first { $0.key == key } }
        return known + properties.filter { !fields.contains($0.key) }
    }

    /// Marfa's properties come unordered, so the rest follow by key.
    func ordered(_ properties: [String: PropertyValue], for type: TypeID) -> [Property] {
        ordered(properties.map { Property(key: $0, value: $1) }.sorted { $0.key < $1.key }, for: type)
    }
}
