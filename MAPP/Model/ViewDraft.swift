import Foundation
import Marfa

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
        /// Days by a date field, or none where the timeline has no field.
        case timeline(key: String?, label: String)
    }

    /// A choice of the window's that the view will not keep.
    enum Unkept: Hashable, Sendable {
        case search(String)
        /// A column whose filter a view cannot express.
        case filter(column: String)
        /// Filters that need both AND and OR, which a Marfa filter never mixes.
        case mixedFilters
        /// A filter the core refuses, as it words the refusal.
        case refused(String)
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

    /// The query a place stands for, or nil where a view cannot stand for it: Recents, which is a count of the
    /// latest edits, Recently Deleted, an index, and a single favorite. A view lists active items, as MAPP's places
    /// do. A collection's view lists its members, though by the view's own order, since a view cannot sort by an
    /// edge's position.
    static func query(for place: SidebarItem, catalogue: Catalogue, views: [LibraryView]) -> LibraryViewQuery? {
        let active: Set<ItemState> = [.active]
        switch place {
        case .allNotes: return LibraryViewQuery(states: active)
        case .inbox: return LibraryViewQuery(tier: .feed, states: active)
        case .favorites:
            return LibraryViewQuery(states: active, filter: text(of: FilterCondition(field: .tags, operator: .contains, value: .text(ItemTag.favorite))))
        case .itemType(let raw):
            let type = TypeID(raw)
            // Marfa takes a type with its subtypes, and a type's place holds the type's own items alone.
            let own = catalogue.descendants(of: type).isEmpty ? nil : text(of: FilterCondition(field: .system(.type), operator: .eq, value: .text(raw)))
            return LibraryViewQuery(types: [type], states: active, filter: own)
        case .files: return LibraryViewQuery(types: [TypeID.file], states: active)
        case .source(let name): return LibraryViewQuery(states: active, filter: text(of: FilterCondition(field: .system(.source), operator: .eq, value: .text(name))))
        case .view(let id): return views.first { $0.id == id }?.query
        case .collection(let id):
            let member = FilterField.edge(type: MarfaMapping.collectionEdge, direction: .outbound)
            return LibraryViewQuery(states: active, filter: text(of: FilterCondition(field: member, operator: .eq, value: .text(id.rawValue))))
        case .recents, .recentlyDeleted, .sources, .collections, .favoriteItem: return nil
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
        case .timeline(let key, let label):
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
        case .parent, .duration: nil
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
        let parsed: Parsed
        do { parsed = try terms(of: base) } catch { return (base, [.refused(message(of: error))]) }
        return combined(parsed, adding: filters, columns: columns, keeping: base)
    }

    /// The conditions of `base` with the window's filters added. Where nothing is added, `unchanged` is the filter.
    private static func combined(
        _ base: Parsed, adding filters: [String: Set<String>], columns: [ItemTableColumn], keeping unchanged: String?
    ) -> (filter: String?, unkept: [Unkept]) {
        var unkept: [Unkept] = []
        var groups: [[FilterCondition]] = []
        for column in columns {
            guard let values = filters[column.id], !values.isEmpty else { continue }
            let conditions = values.sorted().map { condition(of: column, value: $0) }
            guard !conditions.contains(nil) else {
                unkept.append(.filter(column: label(of: column)))
                continue
            }
            groups.append(conditions.compactMap { $0 })
        }
        let held = base.terms.map(\.condition)
        guard !groups.isEmpty else { return (unchanged, unkept) }
        // Values of one column join by OR, columns by AND, and the view's own filter by AND to what is added.
        var joins = Set<FilterJoin>()
        if held.count > 1 { joins.insert(base.join) }
        if groups.contains(where: { $0.count > 1 }) { joins.insert(.any) }
        if groups.count > 1 || !held.isEmpty { joins.insert(.all) }
        guard joins.count <= 1 else { return (unchanged, unkept + [.mixedFilters]) }
        let expression = FilterExpression(join: joins.first ?? .all, conditions: held + groups.flatMap { $0 })
        do {
            return (try expression.encoded(), unkept)
        } catch {
            return (unchanged, unkept + [.refused(message(of: error))])
        }
    }

    /// The field a table column filters, where a filter can express it.
    private static func filterField(of column: ItemTableColumn) -> FilterField? {
        switch column.content {
        case .type: .system(.type)
        case .parent: .edge(type: MarfaMapping.parentEdge, direction: .backref)
        case .field(let field): isPropertyName(field.key) ? .property(field.key) : nil
        case .title, .created, .edited, .duration: nil
        }
    }

    /// One table category as a Marfa condition; nil where a filter cannot express it.
    private static func condition(of column: ItemTableColumn, value: String) -> FilterCondition? {
        guard let field = filterField(of: column) else { return nil }
        if value.isEmpty {
            // The table's type filter keeps a type, never an empty cell.
            return column.content == .type ? nil : FilterCondition(field: field, operator: .notExists)
        }
        if case .field = column.content, column.style == .boolean {
            return value == "true" || value == "false" ? FilterCondition(field: field, operator: .eq, value: .bool(value == "true")) : nil
        }
        return FilterCondition(field: field, operator: .eq, value: .text(value))
    }

    /// The text of one condition on its own, or nil where the core refuses it.
    private static func text(of condition: FilterCondition) -> String? {
        try? FilterExpression(conditions: [condition]).encoded()
    }

    /// What the core says of a refusal, which a person is told as it is worded.
    static func message(of error: any Error) -> String {
        (error as? MarfaError)?.message ?? error.localizedDescription
    }

    static func isPropertyName(_ key: String) -> Bool {
        key.wholeMatch(of: /[a-zA-Z_][a-zA-Z0-9_]*/) != nil
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
        // A saved filter the core refuses shows no table filters; the refusal is told where the view is saved or changed.
        options.filters = (try? terms(of: view.query.filter)).map(shownFilters) ?? [:]
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
        var condition: FilterCondition
        /// The table column it filters, and the category it keeps.
        var column: String?
        var value: String?
        /// Whether its operand is a bool, as a filter on a Yes or No column is written.
        var isBare = false

        /// The condition as the core writes it.
        var text: String { ViewDraft.text(of: condition) ?? "" }
    }

    /// A filter's conditions, in order, and what joins them.
    struct Parsed: Hashable {
        var terms: [Term]
        var join: FilterJoin
    }

    /// A filter's conditions as the core reads them; throws what it refuses.
    static func terms(of filter: String?) throws -> Parsed {
        guard let filter, !filter.allSatisfy(\.isWhitespace) else { return Parsed(terms: [], join: .all) }
        let expression = try FilterExpression(decoding: filter)
        return Parsed(terms: expression.conditions.map(term(of:)), join: expression.join)
    }

    private static func term(of condition: FilterCondition) -> Term {
        var term = Term(condition: condition)
        guard let column = column(of: condition.field) else { return term }
        switch (condition.operator, condition.value) {
        case (.notExists, nil):
            term.column = column
            term.value = ""
        case (.eq, .text(let value)?):
            term.column = column
            term.value = value
        case (.eq, .bool(let value)?) where column.hasPrefix("field."):
            term.column = column
            term.value = value ? "true" : "false"
            term.isBare = true
        default:
            break
        }
        // The table's type filter keeps a type, never an empty cell.
        if column == ItemTableColumn.type.id, term.value?.isEmpty != false { term.column = nil }
        return term
    }

    /// The table column whose filter a condition on this field stands for.
    private static func column(of field: FilterField) -> String? {
        switch field {
        case .system(.type): ItemTableColumn.type.id
        case .edge(MarfaMapping.parentEdge, .backref): ItemTableColumn.parent.id
        case .property(let key): isPropertyName(key) ? "field." + key : nil
        default: nil
        }
    }

    /// The table filters a filter's conditions stand for. The table joins a column's values by OR and its columns
    /// by AND, so conditions joined by AND show where each column has one, and conditions joined by OR show only
    /// where all of them filter one column.
    private static func shownTerms(_ parsed: Parsed) -> [Term] {
        let mapped = parsed.terms.filter { $0.column != nil }
        if parsed.join == .any, parsed.terms.count > 1 {
            let columns = Set(mapped.map(\.column))
            return mapped.count == parsed.terms.count && columns.count == 1 ? mapped : []
        }
        let counts = Dictionary(grouping: parsed.terms.compactMap(\.column), by: { $0 }).mapValues(\.count)
        return mapped.filter { counts[$0.column!] == 1 }
    }

    private static func shownFilters(of parsed: Parsed) -> [String: Set<String>] {
        shownTerms(parsed).reduce(into: [:]) { $0[$1.column!, default: []].insert($1.value!) }
    }

    /// The view's filter with the window's filters in place of the conditions the table showed: the conditions
    /// it could not show stay as they are, in order, and are given back as `unchanged`. A table filter the view
    /// cannot hold leaves the view's filter whole, so a filter is never dropped for one the window could not save.
    static func replacing(
        _ filter: String?, with filters: [String: Set<String>], columns: [ItemTableColumn]
    ) -> (filter: String?, unkept: [Unkept], unchanged: [String]) {
        let parsed: Parsed
        do { parsed = try terms(of: filter) } catch { return (filter, [.refused(message(of: error))], []) }
        let filterable = Dictionary(uniqueKeysWithValues: columns.filter(\.isCategorical).map { ($0.id, $0) })
        let shown = shownTerms(parsed)
        // A column the table lacks, or one whose filter it writes otherwise, shows none of its conditions.
        let hiddenColumns = Set(shown.compactMap { term -> String? in
            guard let column = filterable[term.column!], (column.style == .boolean) == term.isBare else { return term.column }
            return nil
        })
        let shownConditions = Set(shown.filter { !hiddenColumns.contains($0.column!) }.map(\.condition))
        let seeded = shown.filter { !hiddenColumns.contains($0.column!) }
            .reduce(into: [String: Set<String>]()) { $0[$1.column!, default: []].insert($1.value!) }
        let window = filters.filter { filterable[$0.key] != nil && !$0.value.isEmpty }
        guard window != seeded else { return (filter, [], []) }
        let kept = parsed.terms.filter { !shownConditions.contains($0.condition) }
        let base = Parsed(terms: kept, join: parsed.join)
        let result = combined(base, adding: window, columns: columns, keeping: nil)
        if result.unkept.contains(.mixedFilters) || result.unkept.contains(where: { if case .refused = $0 { true } else { false } }) {
            return (filter, result.unkept, [])
        }
        let filterText = result.filter ?? (kept.isEmpty ? nil : try? FilterExpression(join: parsed.join, conditions: kept.map(\.condition)).encoded())
        return (filterText, result.unkept, kept.map(\.text))
    }
}
