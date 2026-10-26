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
        var layout: Layout = .table
    }

    /// The layout the window shows, which decides the order and grouping the person sees.
    enum Layout {
        case table
        /// The list or the gallery, in the list's order.
        case list(NoteOrder)
        /// Lanes by a choice field, or none where the board has no field.
        case board(key: String?, label: String)
        /// Days by a date field, or none where the agenda has no field.
        case agenda(key: String?, label: String)
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
        /// The list's sections by date, which a view's grouping cannot hold.
        case dateSections
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

    /// The settings for a new view of what the window shows, or nil where its place cannot be a view. Only the
    /// table applies filters, so another layout keeps the place's own query; and each layout gives the order and
    /// grouping it shows, never the table's when the table is not showing.
    static func draft(_ window: Window, catalogue: Catalogue, views: [LibraryView]) -> Draft? {
        guard var query = query(for: window.place, catalogue: catalogue, views: views) else { return nil }
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        if case .table = window.layout {
            var filter = filter(query.filter, adding: window.filters, columns: window.columns)
            if case .view = window.place {
                // A view's place shows the view's own filter as the table's filters, so they stand in for it.
                let replaced = replacing(query.filter, with: window.filters, columns: window.columns)
                filter = (replaced.filter, replaced.unkept)
            }
            query.filter = filter.filter
            unkept += filter.unkept
        }
        let arrangement = arrangement(of: window)
        return Draft(query: query, sort: arrangement.sort, group: arrangement.group, unkept: unkept + arrangement.unkept)
    }

    /// The order and grouping the window's layout shows.
    private static func arrangement(of window: Window) -> (sort: [LibraryViewSort], group: LibraryViewGroup?, unkept: [Unkept]) {
        switch window.layout {
        case .table:
            let sort = sort(window.sort)
            let group = group(window.grouping)
            return (sort.sort, group.group, sort.unkept + group.unkept)
        case .list(let order):
            let sort = switch order.sort {
            case .title: LibraryViewSort(field: "title", ascending: true)
            case .dateEdited: LibraryViewSort(field: "updated_at", ascending: false)
            case .dateCreated: LibraryViewSort(field: "created_at", ascending: false)
            }
            // Today, Yesterday and the rest are the list's own sections, which no bucket of a view's grouping matches.
            return ([sort], nil, order.groupsByDate && order.sort != .title ? [.dateSections] : [])
        case .board(let key, let label):
            let byTitle = [LibraryViewSort(field: "title", ascending: true)]
            guard let key else { return (byTitle, nil, []) }
            guard isPropertyName(key) else { return (byTitle, nil, [.group(column: label)]) }
            return (byTitle, LibraryViewGroup(field: "properties." + key), [])
        case .agenda(let key, let label):
            guard let key else { return ([], nil, []) }
            guard isPropertyName(key) else { return ([], nil, [.group(column: label)]) }
            let field = "properties." + key
            return ([LibraryViewSort(field: field, ascending: true)], LibraryViewGroup(field: field, bucket: .day), [])
        }
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
        options.filters = shownFilters(of: terms(of: view.query.filter))
        return options
    }

    /// Stands for a column by its identifier: the table finds its own column by the identifier (`ItemTableLayout.sort`).
    private static func placeholder(_ id: String) -> ItemTableColumn {
        ItemTableColumn(id: id, label: "", content: .title, style: .text)
    }

    /// Whether the window's choices differ from those the view opened with: its order, grouping or filters.
    static func differs(_ options: ItemTableOptions?, from seed: ItemTableOptions) -> Bool {
        let options = options ?? ItemTableOptions()
        return options.filters != seed.filters || options.grouping != seed.grouping || sortKeys(options.sort) != sortKeys(seed.sort)
    }

    private static func sortKeys(_ sort: [ItemTableComparator]?) -> [String]? {
        sort?.map { "\($0.column.id) \($0.order == .forward)" }
    }

    /// The change that saves the table's choices to the view it shows, naming only the settings that differ from
    /// those it opened with, so a setting the window left alone is never sent. The table's filters take the place of
    /// the conditions they showed, so a filter removed in the window is removed from the view; the conditions the
    /// table cannot show stay as they are and are named (`unchanged`) when the filter is written. Only the table shows
    /// a view's order, grouping and filters, so another layout changes nothing.
    static func change(
        _ window: Window, options: ItemTableOptions?, seed: ItemTableOptions, view: LibraryView
    ) -> (change: LibraryViewChange, unkept: [Unkept], unchanged: [String]) {
        guard case .table = window.layout else { return (LibraryViewChange(), [], []) }
        let options = options ?? ItemTableOptions()
        var change = LibraryViewChange()
        var unkept: [Unkept] = []
        var unchanged: [String] = []
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
        if options.filters != seed.filters {
            let filter = replacing(view.query.filter, with: window.filters, columns: window.columns)
            if filter.filter != view.query.filter {
                var query = view.query
                query.filter = filter.filter
                change.query = query
                unchanged = filter.unchanged
            }
            unkept += filter.unkept
        }
        return (change, unkept, unchanged)
    }

    // MARK: A view's filter as the table's

    /// One condition of a view's filter, and the table filter it stands for where it is one.
    struct Term: Hashable {
        var text: String
        /// The table column it filters, and the category it keeps.
        var column: String?
        var value: String?
        /// Whether its operand is a bare `true` or `false`, as a filter on a Yes or No column is written.
        var isBare = false
    }

    /// A filter's conditions, in order, and the word that joins them.
    static func terms(of filter: String?) -> (terms: [Term], joiner: String?) {
        guard let filter else { return ([], nil) }
        var conditions: [[(text: String, quoted: Bool)]] = [[]]
        var joiner: String?
        for token in tokens(of: filter) {
            if !token.quoted, token.text == "AND" || token.text == "OR" {
                joiner = joiner ?? token.text
                conditions.append([])
            } else {
                conditions[conditions.count - 1].append(token)
            }
        }
        let terms = conditions.filter { !$0.isEmpty }.map { tokens in
            var term = Term(text: tokens.map(\.text).joined(separator: " "))
            guard let column = column(ofField: tokens[0].text) else { return term }
            if tokens.count == 2, tokens[1].text == "not_exists" {
                term.column = column
                term.value = ""
            } else if tokens.count == 3, tokens[1].text == "eq" {
                let operand = tokens[2]
                if operand.quoted, let value = unquoted(operand.text) {
                    term.column = column
                    term.value = value
                } else if !operand.quoted, column.hasPrefix("field."), operand.text == "true" || operand.text == "false" {
                    term.column = column
                    term.value = operand.text
                    term.isBare = true
                }
            }
            // The table's type filter keeps a type, never an empty cell.
            if column == ItemTableColumn.type.id, term.value?.isEmpty != false { term.column = nil }
            return term
        }
        return (terms, joiner)
    }

    /// The table column whose filter a condition on this field stands for.
    private static func column(ofField field: String) -> String? {
        switch field {
        case "type": return ItemTableColumn.type.id
        case parentField: return ItemTableColumn.parent.id
        default:
            guard field.hasPrefix("properties.") else { return nil }
            let key = String(field.dropFirst("properties.".count))
            return isPropertyName(key) ? "field." + key : nil
        }
    }

    /// The words and quoted values of a filter, each quoted value whole with its quotes.
    private static func tokens(of filter: String) -> [(text: String, quoted: Bool)] {
        var tokens: [(text: String, quoted: Bool)] = []
        var token = ""
        var inString = false
        var characters = Array(filter)[...]
        func end() {
            if !token.isEmpty { tokens.append((token, token.first == "\"")) }
            token = ""
        }
        while let character = characters.popFirst() {
            if inString {
                token.append(character)
                if character == "\\", characters.first == "\"" { token.append(characters.removeFirst()) }
                else if character == "\"" { inString = false }
            } else if character.isWhitespace {
                end()
            } else {
                if character == "\"" { inString = true }
                token.append(character)
            }
        }
        end()
        return tokens
    }

    /// A quoted value's text, or nil where it holds a backslash other than an escaped quote, which `quotedIfPlain`
    /// would not write back alike.
    private static func unquoted(_ text: String) -> String? {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else { return nil }
        let inner = String(text.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        return inner.contains("\\") ? nil : inner
    }

    /// The table filters a filter's conditions stand for. The table joins a column's values by OR and its columns
    /// by AND, so conditions joined by AND show where each column has one, and conditions joined by OR show only
    /// where all of them filter one column.
    private static func shownTerms(_ parsed: (terms: [Term], joiner: String?)) -> [Term] {
        let mapped = parsed.terms.filter { $0.column != nil }
        if parsed.joiner == "OR", parsed.terms.count > 1 {
            let columns = Set(mapped.map(\.column))
            return mapped.count == parsed.terms.count && columns.count == 1 ? mapped : []
        }
        let counts = Dictionary(grouping: parsed.terms.compactMap(\.column), by: { $0 }).mapValues(\.count)
        return mapped.filter { counts[$0.column!] == 1 }
    }

    private static func shownFilters(of parsed: (terms: [Term], joiner: String?)) -> [String: Set<String>] {
        shownTerms(parsed).reduce(into: [:]) { $0[$1.column!, default: []].insert($1.value!) }
    }

    /// The view's filter with the window's filters in place of the conditions the table showed: the conditions
    /// it could not show stay as they are, in order, and are given back as `unchanged`. A table filter the view
    /// cannot hold leaves the view's filter whole, so a filter is never dropped for one the window could not save.
    static func replacing(
        _ filter: String?, with filters: [String: Set<String>], columns: [ItemTableColumn]
    ) -> (filter: String?, unkept: [Unkept], unchanged: [String]) {
        let parsed = terms(of: filter)
        let filterable = Dictionary(uniqueKeysWithValues: columns.filter(\.isCategorical).map { ($0.id, $0) })
        let shown = shownTerms(parsed)
        // A column the table lacks, or one whose filter it writes otherwise, shows none of its conditions.
        let hiddenColumns = Set(shown.compactMap { term -> String? in
            guard let column = filterable[term.column!], (column.style == .boolean) == term.isBare else { return term.column }
            return nil
        })
        let shownTexts = Set(shown.filter { !hiddenColumns.contains($0.column!) }.map(\.text))
        let seeded = shown.filter { !hiddenColumns.contains($0.column!) }
            .reduce(into: [String: Set<String>]()) { $0[$1.column!, default: []].insert($1.value!) }
        let window = filters.filter { filterable[$0.key] != nil && !$0.value.isEmpty }
        guard window != seeded else { return (filter, [], []) }
        let unchanged = parsed.terms.map(\.text).filter { !shownTexts.contains($0) }
        let base = unchanged.isEmpty ? nil : unchanged.joined(separator: " \(parsed.joiner ?? "AND") ")
        let result = self.filter(base, adding: window, columns: columns)
        if result.unkept.contains(.mixedFilters) || result.unkept.contains(.tooManyFilters) {
            return (filter, result.unkept, [])
        }
        return (result.filter, result.unkept, unchanged)
    }
}
