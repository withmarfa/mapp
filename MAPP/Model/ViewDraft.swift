import Foundation

/// How what a window shows becomes a view's settings, and a view's settings the window's table options. Marfa
/// sorts, groups and filters by fields, while the table does so by columns, so only the columns that stand for a
/// field carry over; the rest are named, so the person knows what the view will not keep.
nonisolated enum ViewDraft {
    /// What a window shows of a place, as the table works it out.
    struct Window {
        var place: SidebarItem
        var columns: [ItemTableColumn]
        var sort: [ItemTableComparator]
        var grouping: ItemTableColumn?
        /// The filters the window applies; only the table applies them.
        var filters: [String: Set<String>] = [:]
        /// The search under way, which a view does not keep.
        var search: String?
    }

    /// A choice of the window's that the view will not keep.
    enum Unkept: Hashable, Sendable {
        case search(String)
        /// A column whose filter a view cannot express.
        case filter(column: String)
        /// Filters that need both AND and OR, which a Marfa filter never mixes.
        case mixedFilters
        case tooManyFilters
        case sort(column: String)
        case group(column: String)
    }

    /// The settings a view saves, apart from its title, and what of the window it leaves out.
    struct Draft: Hashable, Sendable {
        var query: LibraryViewQuery
        var sort: [LibraryViewSort]
        var group: LibraryViewGroup?
        var unkept: [Unkept] = []
    }

    static let maxConditions = 10
    static let maxFilterLength = 2048

    /// The query a place stands for, or nil where a view cannot stand for it: Recents, which is a count of the
    /// latest edits, Recently Deleted, an index, a single favorite, and a collection. A view lists active items,
    /// as MAPP's places do.
    static func query(for place: SidebarItem, catalogue: Catalogue, views: [LibraryView]) -> LibraryViewQuery? {
        let active: Set<ItemState> = [.active]
        switch place {
        case .allNotes: return LibraryViewQuery(states: active)
        case .inbox: return LibraryViewQuery(tier: .feed, states: active)
        case .favorites:
            return LibraryViewQuery(states: active, filter: condition("tags", "contains", quoted(ItemTag.favorite)))
        case .itemType(let raw):
            let type = TypeID(raw)
            // Marfa takes a type with its subtypes, and a type's place holds the type's own items alone.
            let own = catalogue.descendants(of: type).isEmpty ? nil : condition("type", "eq", quoted(raw))
            return LibraryViewQuery(types: [type], states: active, filter: own)
        case .files: return LibraryViewQuery(types: [TypeID.file], states: active)
        case .source(let name): return LibraryViewQuery(states: active, filter: condition("source", "eq", quoted(name)))
        case .view(let id): return views.first { $0.id == id }?.query
        case .recents, .recentlyDeleted, .sources, .collections, .favoriteItem, .collection: return nil
        }
    }

    /// The settings for a new view of what the window shows, or nil where its place cannot be a view.
    static func draft(_ window: Window, catalogue: Catalogue, views: [LibraryView]) -> Draft? {
        guard var query = query(for: window.place, catalogue: catalogue, views: views) else { return nil }
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        let filter = filter(query.filter, adding: window.filters, columns: window.columns)
        query.filter = filter.filter
        unkept += filter.unkept
        let sort = sort(window.sort)
        let group = group(window.grouping)
        return Draft(query: query, sort: sort.sort, group: group.group, unkept: unkept + sort.unkept + group.unkept)
    }

    // MARK: Columns and fields

    /// The field a column stands for, as a view's sort and group name it.
    static func field(of column: ItemTableColumn) -> String? {
        switch column.content {
        case .title: "title"
        case .type: "type"
        case .created: "created_at"
        case .edited: "updated_at"
        case .field(let field): isPropertyName(field.key) ? "properties." + field.key : nil
        case .parent, .collection, .duration: nil
        }
    }

    /// The table column that shows a field, for a window to sort or group by.
    static func columnID(of field: String) -> String? {
        switch field {
        case "title": return "title"
        case "type": return "type"
        case "created_at": return "created"
        case "updated_at": return "edited"
        case "backref[\(MarfaMapping.parentEdge)]": return ItemTableColumn.parent.id
        default:
            guard field.hasPrefix("properties.") else { return nil }
            let key = String(field.dropFirst("properties.".count))
            return isPropertyName(key) ? "field." + key : nil
        }
    }

    /// The link from an item's parent, which the parent column shows.
    private static let parentField = "backref[\(MarfaMapping.parentEdge)]"

    static func sort(_ comparators: [ItemTableComparator]) -> (sort: [LibraryViewSort], unkept: [Unkept]) {
        var sort: [LibraryViewSort] = []
        var unkept: [Unkept] = []
        for comparator in comparators {
            guard let field = field(of: comparator.column) else {
                unkept.append(.sort(column: label(of: comparator.column)))
                continue
            }
            sort.append(LibraryViewSort(field: field, ascending: comparator.order == .forward))
        }
        return (sort, unkept)
    }

    static func group(_ column: ItemTableColumn?) -> (group: LibraryViewGroup?, unkept: [Unkept]) {
        guard let column else { return (nil, []) }
        if column.content == .parent { return (LibraryViewGroup(field: parentField), []) }
        guard let field = field(of: column) else { return (nil, [.group(column: label(of: column))]) }
        return (LibraryViewGroup(field: field), [])
    }

    private static func label(of column: ItemTableColumn) -> String {
        column.label.isEmpty ? String(localized: "Parent") : column.label
    }

    // MARK: Filters

    /// `base` with the window's filters added: a column's values joined by OR, and the columns by AND, each kept only
    /// where the whole expression stays one Marfa filter.
    static func filter(
        _ base: String?, adding filters: [String: Set<String>], columns: [ItemTableColumn]
    ) -> (filter: String?, unkept: [Unkept]) {
        let base = base.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
        var unkept: [Unkept] = []
        var groups: [[String]] = []
        for column in columns {
            guard let values = filters[column.id], !values.isEmpty else { continue }
            let conditions = values.sorted().map { condition(of: column, value: $0) }
            guard !conditions.contains(nil) else {
                unkept.append(.filter(column: label(of: column)))
                continue
            }
            groups.append(conditions.compactMap { $0 })
        }
        guard !groups.isEmpty else { return (base, unkept) }
        let baseShape = base.map { shape(of: $0) } ?? Shape(conditions: 0, joiner: nil)
        let added = groups.flatMap { $0 }
        // Values of one column join by OR, columns by AND, and the view's own filter by AND to what is added.
        var joiners = Set([baseShape.joiner].compactMap { $0 })
        if groups.contains(where: { $0.count > 1 }) { joiners.insert("OR") }
        if groups.count > 1 || baseShape.conditions > 0 { joiners.insert("AND") }
        guard joiners.count <= 1 else { return (base, unkept + [.mixedFilters]) }
        guard baseShape.conditions + added.count <= maxConditions else { return (base, unkept + [.tooManyFilters]) }
        let joiner = joiners.first ?? "AND"
        let filter = ([base].compactMap { $0 } + added).joined(separator: " \(joiner) ")
        guard filter.count <= maxFilterLength else { return (base, unkept + [.tooManyFilters]) }
        return (filter, unkept)
    }

    /// One table category as a Marfa condition; nil where a filter cannot express it.
    private static func condition(of column: ItemTableColumn, value: String) -> String? {
        switch column.content {
        case .type:
            return value.isEmpty ? nil : quotedIfPlain(value).map { condition("type", "eq", $0) }
        case .parent:
            return value.isEmpty
                ? condition(parentField, "not_exists", nil)
                : quotedIfPlain(value).map { condition(parentField, "eq", $0) }
        case .field(let field):
            guard isPropertyName(field.key) else { return nil }
            let path = "properties." + field.key
            if value.isEmpty { return condition(path, "not_exists", nil) }
            if column.style == .boolean { return value == "true" || value == "false" ? condition(path, "eq", value) : nil }
            return quotedIfPlain(value).map { condition(path, "eq", $0) }
        case .title, .collection, .created, .edited, .duration:
            return nil
        }
    }

    private static func condition(_ field: String, _ op: String, _ operand: String?) -> String {
        operand.map { "\(field) \(op) \($0)" } ?? "\(field) \(op)"
    }

    /// Marfa takes `\"` as a quote and any other backslash as itself, so a value that holds a backslash could end in
    /// one that escapes the closing quote, and is not kept.
    private static func quotedIfPlain(_ value: String) -> String? {
        value.contains("\\") ? nil : quoted(value)
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func isPropertyName(_ key: String) -> Bool {
        key.wholeMatch(of: /[a-zA-Z_][a-zA-Z0-9_]*/) != nil
    }

    /// How many conditions a filter holds, and the word that joins them.
    struct Shape: Hashable {
        var conditions: Int
        var joiner: String?
    }

    /// Read from the words outside quoted values: the joiners are AND and OR, and one filter uses one of them.
    static func shape(of filter: String) -> Shape {
        var joiners: [String] = []
        var word = ""
        var inString = false
        var characters = Array(filter)[...]
        func endWord() {
            if word == "AND" || word == "OR" { joiners.append(word) }
            word = ""
        }
        while let character = characters.popFirst() {
            if inString {
                if character == "\\", characters.first == "\"" { characters.removeFirst() }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" {
                endWord()
                inString = true
            } else if character.isWhitespace {
                endWord()
            } else {
                word.append(character)
            }
        }
        endWord()
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        return Shape(conditions: trimmed.isEmpty ? 0 : joiners.count + 1, joiner: joiners.first)
    }

    // MARK: Opening a view

    /// The table options a view opens with: its order and grouping, where the table has a column for them.
    /// A view with no grouping opens ungrouped, and one grouped by what the table cannot show, such as a date by
    /// month, opens ungrouped too.
    static func options(for view: LibraryView) -> ItemTableOptions {
        var options = ItemTableOptions()
        let sort = view.sort.compactMap { key in
            columnID(of: key.field).map { ItemTableComparator(column: placeholder($0), order: key.ascending ? .forward : .reverse) }
        }
        options.sort = sort.isEmpty ? nil : sort
        if let group = view.group, group.bucket == nil, let id = columnID(of: group.field) {
            options.grouping = .column(id)
        } else {
            options.grouping = .none
        }
        return options
    }

    /// Stands for a column by its identifier: the table finds its own column by the identifier (`ItemTableLayout.sort`).
    private static func placeholder(_ id: String) -> ItemTableColumn {
        ItemTableColumn(id: id, label: "", content: .title, style: .text)
    }

    /// Whether the window's choices differ from those the view opened with: its order, grouping or any filter.
    static func differs(_ options: ItemTableOptions?, from seed: ItemTableOptions) -> Bool {
        let options = options ?? ItemTableOptions()
        return !options.filters.isEmpty || options.grouping != seed.grouping || sortKeys(options.sort) != sortKeys(seed.sort)
    }

    private static func sortKeys(_ sort: [ItemTableComparator]?) -> [String]? {
        sort?.map { "\($0.column.id) \($0.order == .forward)" }
    }

    /// The change that saves the window's choices to the view it shows, naming only the settings that differ from
    /// those it opened with, so a setting the window left alone is never sent.
    static func change(
        _ window: Window, options: ItemTableOptions?, seed: ItemTableOptions, view: LibraryView
    ) -> (change: LibraryViewChange, unkept: [Unkept]) {
        let options = options ?? ItemTableOptions()
        var change = LibraryViewChange()
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        if sortKeys(options.sort) != sortKeys(seed.sort) {
            let sort = sort(window.sort)
            change.sort = sort.sort
            unkept += sort.unkept
        }
        if options.grouping != seed.grouping {
            let group = group(window.grouping)
            change.group = group.group.map { .set($0) } ?? .clear
            unkept += group.unkept
        }
        if !window.filters.isEmpty {
            let filter = filter(view.query.filter, adding: window.filters, columns: window.columns)
            if filter.filter != view.query.filter {
                var query = view.query
                query.filter = filter.filter
                change.query = query
            }
            unkept += filter.unkept
        }
        return (change, unkept)
    }
}
