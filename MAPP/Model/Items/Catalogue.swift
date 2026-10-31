import Foundation

nonisolated struct ItemTypeInfo: Identifiable, Hashable, Sendable {
    struct Field: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case text, number, boolean
            /// A Marfa `date`, a day, or a `datetime`, which may also name a time.
            case date(includesTime: Bool)
            case choice([String])
            /// A status field: a word the type declares, each in one of the four groups. It is the field's kind, not its
            /// name, that makes it a status (`core.media` calls it `progress`).
            case status([StatusWord])
            /// A shape the app shows but does not edit, such as a list or an object.
            case other
        }

        enum TextFormat: Hashable, Sendable { case url, email }

        let key: String
        let label: String
        let kind: Kind
        /// The type that declares the field, which is an ancestor for an inherited one.
        let declaredBy: TypeID
        var required = false
        var description: String?
        /// What a text field holds beyond plain text, where the contract names it: a `url` or an `email`.
        var format: TextFormat?
        /// Whether a number field holds whole numbers only, as a Marfa `integer` does.
        var isInteger = false
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
    /// The Iconify ID of the icon that stands for the type, such as `lucide:book-open` or `simple-icons:github`, as the
    /// server resolves it: the owner's choice, else the nearest type's that sets one. Nil where none does.
    var icon: String?
    var description: String?
    var version: Int64?
    /// With the roles it inherits, as Marfa resolves them.
    var roles: [String] = []
    /// The types this one claims to be a structural superset of.
    var compatibleWith: [TypeID] = []
    /// The field that holds each item's own identity at the connector that writes the type, such as a GitHub issue's
    /// node ID. It is a fact for the connector, not something to read, so the page leaves it out until asked.
    var linkField: String?

    func declares(_ key: String) -> Bool { fields.contains { $0.key == key } }

    /// The property the item's title is kept in: the field the hints name, else `title` where the type declares
    /// it.
    var titleKey: String? { titleField ?? (declares("title") ? "title" : nil) }

    /// The property the item's text is kept in: the field the hints name, else `body` where the type declares it.
    var bodyKey: String? { bodyField ?? (declares("body") ? "body" : nil) }

    /// The field an item's status is kept in: the type's one field of the `status` kind, whatever its name.
    var statusField: Field? { fields.first { $0.isStatus } }

    /// The group this type puts `word` in; nil where it has no status field or does not declare the word.
    func statusGroup(of word: String) -> StatusGroup? { statusField?.statusGroup(of: word) }
}

nonisolated extension ItemTypeInfo.Field {
    /// The values the catalogue offers for the field, in its order: a choice's own, or a status field's words.
    var options: [String] {
        switch kind {
        case .choice(let choices): return choices
        case .status(let words): return words.map(\.value)
        case .text, .number, .boolean, .date, .other: return []
        }
    }

    /// Whether the field is picked from a list of values rather than typed.
    var isPicked: Bool { !options.isEmpty }

    /// The field with the words of `other`, a status field of another type that shares it, added after its own.
    func addingStatusWords(of other: ItemTypeInfo.Field) -> ItemTypeInfo.Field {
        guard case .status(let mine) = kind, case .status(let theirs) = other.kind else { return self }
        let added = theirs.filter { word in !mine.contains { $0.value == word.value } }
        guard !added.isEmpty else { return self }
        var merged = ItemTypeInfo.Field(key: key, label: label, kind: .status(mine + added), declaredBy: declaredBy)
        merged.required = required
        merged.description = description
        merged.format = format
        return merged
    }

    /// Whether the field is a status field.
    var isStatus: Bool {
        if case .status = kind { true } else { false }
    }

    /// The group a status field puts `word` in; nil for any other field and for a word it does not declare.
    func statusGroup(of word: String) -> StatusGroup? {
        guard case .status(let words) = kind else { return nil }
        return words.first { $0.value == word }?.group
    }

    /// Where a table lists `word` in a status field: its group, else Other.
    func statusBucket(of word: String) -> StatusBucket {
        statusGroup(of: word).map(StatusBucket.group) ?? .other
    }

    /// The values to offer for an item that holds `current`: `options`, and `current` last where they do not list
    /// it, since a menu always shows what is set. A status can hold a word its type does not declare.
    func options(including current: String?) -> [String] {
        let options = options
        guard !options.isEmpty, let current, !current.isEmpty, !options.contains(current) else { return options }
        return options + [current]
    }

    /// An option written for reading, in the person's language: the catalogue holds no labels for them, so
    /// `in_progress` reads as "In Progress" or its translation. Every place that shows an option goes through this.
    static func label(ofOption option: String) -> String {
        let words = option.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return Bundle.main.localizedString(forKey: words, value: words, table: nil)
    }

    /// A label the catalogue wrote for people, set in title case for the interface: "Completed at" reads as
    /// "Completed At". Only each word's first letter changes, so an acronym or a name keeps its capitals. This is
    /// the one place a catalogue label becomes a display label, for properties and relationships alike.
    static func displayLabel(_ label: String) -> String {
        label.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The field's label as the interface shows it.
    var displayLabel: String { Self.displayLabel(label) }
}

nonisolated struct EdgeTypeInfo: Identifiable, Hashable, Sendable {
    enum End: Hashable, Sendable { case source, target }

    enum Cardinality: Hashable, Sendable { case one, many }

    /// What deleting an item does through an edge: `cascade` deletes the target when the source is deleted, `block`
    /// refuses a delete of either end, and `orphan` keeps the other end.
    enum CascadeOnDelete: Hashable, Sendable { case cascade, orphan, block }

    let id: String
    /// Marfa's name for the source end of a link, as it comes: the parent end of `parent-of` is `Children`.
    let label: String
    /// Marfa's name for the target end, as it comes: the child end of `parent-of` is `Parent`.
    let reverseLabel: String
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

    /// Whether both ends carry one name, so the relation reads the same from either item and its outgoing and
    /// incoming links form one list.
    var isTwoWay: Bool { label == reverseLabel }

    /// The name of the end an item holds, as Marfa gives it.
    func label(atTarget: Bool) -> String { atTarget ? reverseLabel : label }

    /// How many edges of this type one item holds as its source, or as its target.
    func cardinality(atTarget: Bool) -> Cardinality {
        (writtenAt == .target) == atTarget ? cardinality : reverseCardinality
    }
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

    /// The icon of `type`, an Iconify ID; nil where no type in its chain sets one, and for a type the catalogue does
    /// not hold.
    func icon(for type: TypeID) -> String? { itemTypes[type]?.icon }

    /// The type's name as people read it: the catalogue's label, else its last segment capitalized.
    func label(for type: TypeID) -> String {
        if let label = itemTypes[type]?.label, !label.isEmpty { return label }
        let segment = type.rawValue.split(whereSeparator: { $0 == "." || $0 == "/" }).last.map(String.init)?.lowercased() ?? ""
        return segment.capitalized
    }

    /// The label for a property key: the item's own type's, else the one the catalogue gives it for any type. Nil
    /// for a key no type defines.
    func label(ofField key: String, for type: TypeID?) -> String? {
        type.flatMap { itemTypes[$0]?.fields.first { $0.key == key }?.label } ?? fieldLabels[key]
    }

    /// The keys that hold what the page shows itself, the item's title and text, so Properties does not list them.
    func pageKeys(of item: Item) -> Set<String> {
        var keys: Set<String> = []
        if case .property(let key) = item.titleRule { keys.insert(key) }
        let type = itemTypes[item.type]
        if let key = type?.titleKey { keys.insert(key) }
        if let key = type?.bodyKey { keys.insert(key) }
        return keys
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

    /// Whether `type` is one of `types`, below one of them, or plays one of `roles`, as an edge type's end names
    /// what it admits. An end naming neither admits any type.
    func admits(_ type: TypeID, types: Set<TypeID>, roles: Set<String>) -> Bool {
        (types.isEmpty && roles.isEmpty) || types.contains(type) || isSubtype(type, ofAnyOf: types)
            || !roles.isDisjoint(with: itemTypes[type]?.roles ?? [])
    }

    // MARK: Tasks and statuses

    /// Whether `type` is `core.task` or below it. A task is what has a due date and a priority; no other type's field
    /// of those names is read as one.
    func isTask(_ type: TypeID) -> Bool {
        type == MarfaMapping.taskType || isSubtype(type, ofAnyOf: [MarfaMapping.taskType])
    }

    /// Whether `field` is a task's priority: the `priority` field of a type that is a task.
    func isPriority(_ field: ItemTypeInfo.Field, of type: TypeID) -> Bool {
        field.key == MarfaMapping.priorityField && isTask(type)
    }

    /// Whether `field` is a task's due date: the `due_at` field of a type that is a task.
    func isDueDate(_ field: ItemTypeInfo.Field, of type: TypeID) -> Bool {
        field.key == MarfaMapping.dueField && isTask(type)
    }

    /// Whether `field` is a start date: the `starts_at` field of a type that is an event or a task, or below one.
    func isStartDate(_ field: ItemTypeInfo.Field, of type: TypeID) -> Bool {
        field.key == MarfaMapping.startField && [MarfaMapping.eventType, MarfaMapping.taskType].contains { type == $0 || isSubtype(type, ofAnyOf: [$0]) }
    }

    /// The group of the word `item` holds in its type's status field; nil where the type has none, the item holds
    /// none, or the type does not declare it.
    func statusGroup(of item: Item) -> StatusGroup? {
        guard let type = itemTypes[item.type], let field = type.statusField,
              let word = item.value(of: field.key)?.string else { return nil }
        return field.statusGroup(of: word)
    }

    // MARK: Collections

    /// Whether items of `type` are collections: the type plays Marfa's `container` role.
    func isCollection(_ type: TypeID) -> Bool {
        itemTypes[type]?.roles.contains(MarfaMapping.containerRole) == true
    }

    /// The types whose items are collections.
    var collectionTypes: [TypeID] {
        itemTypes.values.filter { $0.roles.contains(MarfaMapping.containerRole) }.map(\.id)
    }

    /// Whether an item of `type` can be filed in a collection: the catalogue has `in-collection`, its source end
    /// admits the type, and the type is not a collection itself, since collections are flat
    /// (`edges/collection-no-nesting`).
    func canJoinCollection(_ type: TypeID) -> Bool {
        guard let info = edgeTypes[MarfaMapping.collectionEdge], !isCollection(type) else { return false }
        return admits(type, types: info.sourceTypes, roles: info.sourceRoles)
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

    /// Properties given unordered, as a queued write holds them, put the rest in order by key.
    func ordered(_ properties: [String: PropertyValue], for type: TypeID) -> [Property] {
        ordered(properties.map { Property(key: $0, value: $1) }.sorted { $0.key < $1.key }, for: type)
    }
}
