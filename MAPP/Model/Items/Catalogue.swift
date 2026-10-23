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
    /// The display hints the type declares or inherits, taken whole; where they name none, Marfa reads `title` and
    /// `body`.
    let titleField: String?
    let bodyField: String?
    let parent: TypeID?
    var description: String?
    /// A files library's types have none.
    var version: Int64?
    /// With the roles it inherits, as Marfa resolves them.
    var roles: [String] = []
    /// The types this one claims to be a structural superset of.
    var compatibleWith: [TypeID] = []

    func declares(_ key: String) -> Bool { fields.contains { $0.key == key } }

    /// The property the item's title is kept in: the field the hints name, else `title` where the type declares
    /// it.
    var titleKey: String? { titleField ?? (declares("title") ? "title" : nil) }

    /// The property the item's text is kept in: the field the hints name, else `body` where the type declares it.
    var bodyKey: String? { bodyField ?? (declares("body") ? "body" : nil) }

    /// The field an item's status is kept in, for any type that defines one a person can pick from: a choice, or
    /// a text field that recommends values (Marfa's `core.task` does). A status the type gives some other shape
    /// (a number, a date) is not a status the page can offer a menu for.
    var statusField: Field? {
        fields.first { field in
            guard field.key == "status" else { return false }
            switch field.kind {
            case .choice, .text: return true
            case .number, .boolean, .date, .other: return false
            }
        }
    }
}

nonisolated extension ItemTypeInfo.Field {
    /// The values the catalogue offers for the field, in its order: a choice's own, or the ones a text field's
    /// description recommends, as `Recommended values: pending, in_progress`. Empty when it names none.
    var options: [String] {
        switch kind {
        case .choice(let choices): return choices
        case .text: return Self.recommendedValues(in: description)
        case .number, .boolean, .date, .other: return []
        }
    }

    /// Whether the field is picked from a list of values rather than typed.
    var isPicked: Bool { !options.isEmpty }

    private static let recommendation = "recommended values:"

    private static func recommendedValues(in description: String?) -> [String] {
        guard let description, let range = description.range(of: recommendation, options: [.caseInsensitive, .anchored]) else { return [] }
        let values = description[range.upperBound...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
        // Prose that merely follows the phrase is no list: every value has to look like one.
        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } })
        else { return [] }
        return values
    }

    /// An option written for reading: the catalogue holds no labels for them, so `in_progress` reads as "In
    /// Progress".
    static func label(ofOption option: String) -> String {
        option.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

nonisolated struct EdgeTypeInfo: Identifiable, Hashable, Sendable {
    enum End: Hashable, Sendable { case source, target }

    enum Cardinality: Hashable, Sendable { case one, many }

    /// What deleting an item does through an edge: `cascade` deletes the target when the source is deleted, `block`
    /// refuses a delete of either end, and `orphan` keeps the other end.
    enum CascadeOnDelete: Hashable, Sendable { case cascade, orphan, block }

    let id: String
    let label: String
    /// The name it is written under at its target, such as `child-of` for `parent-of`.
    let reverseName: String?
    /// How many of this edge the end it is written at may hold, which decides whether its field takes a list.
    let cardinality: Cardinality
    let writtenAt: End
    /// The types each end may be, with their subtypes, and the roles a type may play to be one. An end naming
    /// neither allows any type.
    let sourceTypes: Set<TypeID>
    let targetTypes: Set<TypeID>
    var sourceRoles: Set<String> = []
    var targetRoles: Set<String> = []
    var description: String?
    /// How many of this edge the end it is not written at may hold.
    var reverseCardinality: Cardinality = .many
    var cascadeOnDelete: CascadeOnDelete = .orphan
    var properties: [ItemTypeInfo.Field] = []

    /// How many edges of this type one item holds as its source, or as its target.
    func cardinality(atTarget: Bool) -> Cardinality {
        (writtenAt == .target) == atTarget ? cardinality : reverseCardinality
    }

    func allowsAnySource() -> Bool { sourceTypes.isEmpty && sourceRoles.isEmpty }
    func allowsAnyTarget() -> Bool { targetTypes.isEmpty && targetRoles.isEmpty }
}

nonisolated struct Catalogue: Hashable, Sendable {
    var itemTypes: [TypeID: ItemTypeInfo] {
        didSet { fieldLabels = Self.fieldLabels(of: itemTypes) }
    }
    var edgeTypes: [String: EdgeTypeInfo]
    /// The label for each property key some type defines. Types are read in the order of their identifiers, so a
    /// key several types label differently always has the same label.
    private(set) var fieldLabels: [String: String]

    init(itemTypes: [ItemTypeInfo] = [], edgeTypes: [EdgeTypeInfo] = []) {
        let types = Dictionary(itemTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.itemTypes = types
        self.edgeTypes = Dictionary(edgeTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        fieldLabels = Self.fieldLabels(of: types)
    }

    private static func fieldLabels(of itemTypes: [TypeID: ItemTypeInfo]) -> [String: String] {
        var labels: [String: String] = [:]
        for type in itemTypes.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            for field in type.fields where labels[field.key] == nil { labels[field.key] = field.label }
        }
        return labels
    }

    /// The label for a property key: the item's own type's, else the one the catalogue gives it for any type. Nil
    /// for a key no type defines.
    func label(ofField key: String, for type: TypeID?) -> String? {
        type.flatMap { itemTypes[$0]?.fields.first { $0.key == key }?.label } ?? fieldLabels[key]
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

    /// Properties given unordered, as a note's front matter is read, put the rest in order by key.
    func ordered(_ properties: [String: PropertyValue], for type: TypeID) -> [Property] {
        ordered(properties.map { Property(key: $0, value: $1) }.sorted { $0.key < $1.key }, for: type)
    }
}
