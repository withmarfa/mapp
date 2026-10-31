import Foundation

/// One of the catalogue's types that holds items, as the sidebar, Settings and the palette show it.
nonisolated struct ItemTypeCount: Identifiable, Hashable, Sendable {
    let id: TypeID
    /// The type's label, with its parent's in parentheses where another shown type has the same label.
    let label: String
    /// The type's icon, an Iconify ID.
    let icon: String?
    /// The items the type holds itself, never those of its subtypes, so the number is the length of the list the
    /// row opens.
    let count: Int
}

/// A row of the sidebar's Types section: a type, or a group of types whose identifiers share a stem that is no type
/// itself, as `aic.agent.session` and `aic.agent.log` share Agent. Types nest by their identifiers, the namespaces
/// their catalogue gives them, so `aic.ticket.task` sits under Ticket and reads just "Task".
nonisolated struct TypeNode: Identifiable, Hashable, Sendable {
    /// The type's identifier, or the group's stem.
    let id: String
    /// Nil for a group, which only holds other rows.
    let type: TypeID?
    let label: String
    let icon: String?
    /// The type's own items, which its row opens; zero for a group.
    let count: Int
    /// The items of the whole branch, the type's own included.
    let total: Int
    let children: [TypeNode]

    /// Whether the row opens a list: a type that holds items. A group, or a type with none of its own, only
    /// folds its rows open and shut.
    var opens: Bool { type != nil && count > 0 }

    /// `types` nested by the stems of their identifiers below the first segment, which only names who made the type
    /// (`aic`, `core`). A stem with one row under it and no type of its own gives way to that row. Siblings are in
    /// order of their branch's items, most first, then by label. A row under another drops the words it repeats, so
    /// Agent session under Agent reads "Session".
    static func tree(of types: [ItemTypeCount], in catalogue: Catalogue) -> [TypeNode] {
        let held = Dictionary(uniqueKeysWithValues: types.map { ($0.id.rawValue, $0) })
        var children: [String: Set<String>] = [:]
        var roots: Set<String> = []
        for type in types {
            var id = type.id.rawValue
            while true {
                guard let stem = stem(of: id) else { roots.insert(id); break }
                let isNew = children[stem, default: []].insert(id).inserted
                id = stem
                if !isNew { break }
            }
        }
        func node(_ id: String, under parentLabel: String?) -> TypeNode {
            let known = catalogue.itemTypes[TypeID(id)] != nil
            let own = held[id]
            let label = own.map { catalogue.label(for: $0.id) }
                ?? (known ? catalogue.label(for: TypeID(id)) : segment(of: id).capitalized)
            let shown = trimmed(label, under: parentLabel)
            let below = (children[id] ?? []).map { node($0, under: label) }
            let count = own?.count ?? 0
            let total = count + below.reduce(0) { $0 + $1.total }
            let sorted = ordered(below)
            // A group of one adds a fold for nothing: its row takes its place, under its own full name.
            if !known, own == nil, sorted.count == 1, let only = sorted.first {
                return node(only.id, under: parentLabel)
            }
            let icon = own?.icon ?? (known ? catalogue.icon(for: TypeID(id)) : sorted.first?.icon)
            return TypeNode(
                id: id, type: known || own != nil ? TypeID(id) : nil, label: shown, icon: icon,
                count: count, total: total, children: sorted)
        }
        return ordered(roots.map { node($0, under: nil) })
    }

    private static func ordered(_ nodes: [TypeNode]) -> [TypeNode] {
        nodes.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// The identifier without its last segment, or nil when what is left only names who made the type.
    private static func stem(of id: String) -> String? {
        let parts = id.split(separator: ".")
        return parts.count > 2 ? parts.dropLast().joined(separator: ".") : nil
    }

    private static func segment(of id: String) -> String {
        id.split(separator: ".").last.map(String.init) ?? id
    }

    /// "Agent session" under "Agent" reads "Session"; a label that does not start with its parent's stays whole.
    private static func trimmed(_ label: String, under parent: String?) -> String {
        guard let parent, label.count > parent.count + 1,
              label.lowercased().hasPrefix(parent.lowercased() + " ") else { return label }
        let rest = label.dropFirst(parent.count + 1)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}

/// A type a new item can be, as its menu shows it.
nonisolated struct ItemTypeOption: Identifiable, Hashable, Sendable {
    let id: TypeID
    let label: String
    let icon: String?
}

nonisolated extension Catalogue {
    /// Whether `type` is the file type or a kind of file.
    func isFileType(_ type: TypeID) -> Bool {
        type == .file || isSubtype(type, ofAnyOf: [.file])
    }

    /// Whether a new item can be of `type`: any but the file types, which are made by adding a file, and the system's.
    func isCreatable(_ type: TypeID) -> Bool {
        !isFileType(type) && !type.rawValue.hasPrefix("system.")
    }

    /// The label each of `types` goes by. A label two of them share gets its parent's label in parentheses,
    /// "Task (Ticket)", so the rows can be told apart.
    func displayLabels(for types: some Collection<TypeID>) -> [TypeID: String] {
        let labels = Dictionary(uniqueKeysWithValues: types.map { ($0, self.label(for: $0)) })
        let shared = Dictionary(grouping: types, by: { labels[$0] ?? "" }).filter { $0.value.count > 1 }
        return labels.reduce(into: [:]) { result, entry in
            let (type, label) = entry
            if shared[label] != nil, let parent = itemTypes[type]?.parent, itemTypes[parent] != nil {
                result[type] = "\(label) (\(self.label(for: parent)))"
            } else {
                result[type] = label
            }
        }
    }
}

extension ItemLibrary {
    /// How many items Recents lists. A fixed number, not a span of days, so it is useful however long ago the
    /// library was last edited.
    static var recentLimit: Int { 30 }

    /// The active items among `items` edited most recently, newest first, as many as `recentLimit`.
    static func recent(_ items: some Sequence<Item>) -> [Item] {
        Array(items.filter { $0.state == .active }
            .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.id.rawValue < $1.id.rawValue }
            .prefix(recentLimit))
    }

    /// The catalogue's types that directly hold active items, most items first, then by label. The file types are
    /// left out, since All Items and search reach them. A type with no items is left out, and the sidebar shows it
    /// the first time the library holds one. The count is `count(in:)` of the type's own place, which lists the
    /// type's items and no subtype's.
    var itemTypeCounts: [ItemTypeCount] {
        let started = ContinuousClock.now
        defer { Cost.record(.typeCounts, since: started) }
        let catalogue = catalogue
        let held = catalogue.itemTypes.keys.compactMap { type -> (TypeID, Int)? in
            guard !catalogue.isFileType(type) else { return nil }
            let count = count(in: .itemType(type.rawValue))
            return count > 0 ? (type, count) : nil
        }
        let labels = catalogue.displayLabels(for: held.map(\.0))
        return held.map { type, count in
            ItemTypeCount(id: type, label: labels[type] ?? type.rawValue, icon: catalogue.icon(for: type), count: count)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }

    /// `itemTypeCounts` as the sidebar's Types section nests them (`TypeNode.tree`).
    var typeTree: [TypeNode] { TypeNode.tree(of: itemTypeCounts, in: catalogue) }

    /// The types a new item can be, by label: every type in the catalogue except the file types, which are made by
    /// adding a file.
    var creatableTypes: [ItemTypeOption] {
        let catalogue = catalogue
        let types = catalogue.itemTypes.keys.filter(catalogue.isCreatable)
        let labels = catalogue.displayLabels(for: types)
        return types.map { type in
            ItemTypeOption(id: type, label: labels[type] ?? type.rawValue, icon: catalogue.icon(for: type))
        }
        .sorted {
            let order = $0.label.localizedStandardCompare($1.label)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }
}
