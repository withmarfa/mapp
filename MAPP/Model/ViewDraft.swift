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
        /// The filters the window applies, in every layout.
        var filters: [String: Set<String>] = [:]
        /// The columns whose filter is Is Not.
        var negated: Set<String> = []
        /// The search under way, which a view does not keep.
        var search: String?
        var layout: Layout = .table
        /// The date field the person chose for the timeline, which a view keeps as the day its items are grouped by.
        var timelineDate: String?
        /// The types the view opened with as a Type filter (`seededTypes(of:catalogue:)`), kept from then rather than
        /// worked out again, since a catalogue that changes while the window is open must not change what the
        /// filter stood for. Nil where the place is not a view, or its types were not shown as a filter.
        var seededTypes: [String]?
        /// Set where the window shows the list's own order, which a list or gallery that is neither sorted nor grouped by a
        /// column does: the order it shows, and whether it shows sections by date.
        var dated: Dated?
    }

    /// The list's own order, which stands for a view with no sort or grouping of its own.
    struct Dated {
        var sort: [ItemTableComparator]
        var hasSections: Bool
    }

    /// The layout the window shows, which decides the order and grouping the person sees.
    enum Layout {
        /// The order and grouping of the table's columns, which the table shows, and the list and gallery do where
        /// the person has set them or the place is a view.
        case table
        /// The list or the gallery, in the list's own order.
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
        /// Filters that would need more conditions than a Marfa filter takes.
        case tooManyFilters
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

    /// The settings for a new view of what the window shows, or nil where its place cannot be a view. Every layout
    /// applies the filters; and each layout gives the order and grouping it shows, never the table's when the table
    /// is not showing.
    static func draft(_ window: Window, catalogue: Catalogue, views: [LibraryView]) -> Draft? {
        guard let base = query(for: window.place, catalogue: catalogue, views: views) else { return nil }
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        let filtered: (query: LibraryViewQuery, unkept: [Unkept])
        if case .view = window.place {
            // A view's place shows the view's own filter as the window's filters, so they stand in for it.
            let replaced = replacing(
                base, with: choices(of: window), columns: window.columns, seededTypes: window.seededTypes, catalogue: catalogue)
            filtered = (replaced.query, replaced.unkept)
        } else {
            filtered = adding(choices(of: window), to: base, columns: window.columns, catalogue: catalogue)
        }
        let arrangement = arrangement(of: window)
        return Draft(query: filtered.query, sort: arrangement.sort, group: arrangement.group, unkept: unkept + filtered.unkept + arrangement.unkept)
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
        case .parent, .duration, .occurred, .tags: nil
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

    private static let typeColumnID = ItemTableColumn.type.id

    /// The window's filters with whether each is Is Not.
    static func choices(of window: Window) -> [String: FilterChoice] {
        ItemTableOptions(filters: window.filters, negated: window.negated).filterChoices
    }

    private static func filtered(
        _ base: String?, adding choices: [String: FilterChoice], columns: [ItemTableColumn]
    ) -> (filter: String?, unkept: [Unkept]) {
        let base = base.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
        let parsed: Parsed
        do { parsed = try terms(of: base) } catch { return (base, [.refused(message(of: error))]) }
        return combined(parsed, adding: choices, columns: columns, keeping: base)
    }

    /// The query with the window's filters added to a place's own. A Type filter that keeps types goes into the
    /// query's types, which Marfa takes with their subtypes, so it is not kept for a type that has any, nor beside
    /// the types the place already lists.
    static func adding(
        _ choices: [String: FilterChoice], to query: LibraryViewQuery, columns: [ItemTableColumn], catalogue: Catalogue
    ) -> (query: LibraryViewQuery, unkept: [Unkept]) {
        var query = query
        var choices = choices
        var unkept: [Unkept] = []
        if let column = columns.first(where: { $0.id == typeColumnID }), let choice = choices[typeColumnID], !choice.isNegated {
            choices[typeColumnID] = nil
            let chosen = choice.values.subtracting([""])
            if !chosen.isEmpty {
                if let types = types(keeping: chosen, beside: query.types, catalogue: catalogue) {
                    query.types = types
                } else {
                    unkept.append(.filter(column: label(of: column)))
                }
            }
        }
        let result = filtered(query.filter, adding: choices, columns: columns)
        query.filter = result.filter
        return (query, unkept + result.unkept)
    }

    /// The types a Type filter keeps, as a query lists them, or nil where Marfa cannot say so: it lists a type with
    /// its subtypes, and the query's own types are kept whole.
    private static func types(keeping chosen: Set<String>, beside listed: [TypeID], catalogue: Catalogue) -> [TypeID]? {
        if !listed.isEmpty { return Set(listed.map(\.rawValue)) == chosen ? listed : nil }
        guard chosen.allSatisfy({ catalogue.descendants(of: TypeID($0)).isEmpty }) else { return nil }
        return chosen.sorted().map { TypeID($0) }
    }

    /// The types a view lists, shown as a Type filter where it lists several and none has subtypes: the items are
    /// then all of those types, so the filter hides nothing until it is changed.
    static func seededTypes(of query: LibraryViewQuery, catalogue: Catalogue) -> [String]? {
        guard query.types.count > 1, query.types.allSatisfy({ catalogue.descendants(of: $0).isEmpty }) else { return nil }
        return query.types.map(\.rawValue)
    }

    /// The conditions of `base` with the window's filters added. Where nothing is added, `unchanged` is the filter.
    private static func combined(
        _ base: Parsed, adding choices: [String: FilterChoice], columns: [ItemTableColumn], keeping unchanged: String?
    ) -> (filter: String?, unkept: [Unkept]) {
        var unkept: [Unkept] = []
        var groups: [(conditions: [FilterCondition], isNegated: Bool)] = []
        for column in columns {
            guard let choice = choices[column.id], !choice.values.isEmpty else { continue }
            let conditions = choice.values.sorted().map { condition(of: column, value: $0, negated: choice.isNegated) }
            guard !conditions.contains(nil) else {
                unkept.append(.filter(column: label(of: column)))
                continue
            }
            groups.append((conditions.compactMap { $0 }, choice.isNegated))
        }
        let held = base.terms.map(\.condition)
        guard !groups.isEmpty else { return (unchanged, unkept) }
        guard held.count + groups.reduce(0, { $0 + $1.conditions.count }) <= maxConditions else {
            return (unchanged, unkept + [.tooManyFilters])
        }
        // Values of one column join by OR (by AND where they are excluded), columns by AND, and the view's own
        // filter by AND to what is added.
        var joins = Set<FilterJoin>()
        if held.count > 1 { joins.insert(base.join) }
        for group in groups where group.conditions.count > 1 { joins.insert(group.isNegated ? .all : .any) }
        if groups.count > 1 || !held.isEmpty { joins.insert(.all) }
        guard joins.count <= 1 else { return (unchanged, unkept + [.mixedFilters]) }
        let expression = FilterExpression(join: joins.first ?? .all, conditions: held + groups.flatMap { $0.conditions })
        do {
            return (try expression.encoded(), unkept)
        } catch {
            return (unchanged, unkept + [.refused(message(of: error))])
        }
    }

    /// The most conditions a Marfa filter holds.
    static let maxConditions = 10
    /// How many sort keys a window keeps, in the panel and in the table's header.
    static let maxSortKeys = 10

    /// The field a table column filters, where a filter can express it.
    private static func filterField(of column: ItemTableColumn) -> FilterField? {
        switch column.content {
        case .type: .system(.type)
        case .parent: .edge(type: MarfaMapping.parentEdge, direction: .backref)
        case .field(let field): isPropertyName(field.key) ? .property(field.key) : nil
        case .title, .created, .edited, .occurred, .tags, .duration: nil
        }
    }

    /// Whether a saved view's query can hold a filter on the column, as the window's filter does, so the row offers only
    /// filters that can be saved. Today's filterable columns are the categorical ones, which the query holds as a type,
    /// a parent or a property.
    static func canFilter(_ column: ItemTableColumn) -> Bool {
        column.isCategorical && filterField(of: column) != nil
    }

    /// One table category as a Marfa condition; nil where a filter cannot express it. Is Not is `neq`, and the
    /// empty cell, which Is Not excludes, is `exists`.
    private static func condition(of column: ItemTableColumn, value: String, negated: Bool = false) -> FilterCondition? {
        guard let field = filterField(of: column) else { return nil }
        if value.isEmpty {
            // The table's type filter keeps a type, never an empty cell.
            guard column.content != .type else { return nil }
            return FilterCondition(field: field, operator: negated ? .exists : .notExists)
        }
        let comparison: FilterOperator = negated ? .neq : .eq
        if case .field = column.content, column.style == .boolean {
            return value == "true" || value == "false" ? FilterCondition(field: field, operator: comparison, value: .bool(value == "true")) : nil
        }
        return FilterCondition(field: field, operator: comparison, value: .text(value))
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
    /// month, opens ungrouped too. A view that lists several types opens with a Type filter keeping them.
    static func options(for view: LibraryView, catalogue: Catalogue) -> ItemTableOptions {
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
        let types = seededTypes(of: view.query, catalogue: catalogue)
        let shown = (try? terms(of: view.query.filter)).map { shownTerms($0).filter { types == nil || $0.column != typeColumnID } } ?? []
        var choices = shownChoices(shown)
        if let types { choices[typeColumnID] = FilterChoice(values: Set(types), isNegated: false) }
        options.filters = choices.mapValues(\.values)
        options.negated = Set(choices.filter(\.value.isNegated).keys)
        return options
    }

    /// The conditions of a view's filter the window has no filter for, as Marfa writes them. Saving a change of filters
    /// leaves them as they are, and the panel lists them so they are not a surprise.
    static func unshownConditions(of query: LibraryViewQuery, catalogue: Catalogue) -> [String] {
        guard let parsed = try? terms(of: query.filter) else { return [] }
        let types = seededTypes(of: query, catalogue: catalogue)
        let shown = Set(shownTerms(parsed).map(\.condition))
        return parsed.terms.filter { term in
            !shown.contains(term.condition) && !(types != nil && term.column == typeColumnID)
        }.map(\.text)
    }

    /// The date field a view's days are grouped by, which a timeline shows its items by.
    static func timelineDate(of view: LibraryView) -> String? {
        guard let group = view.group, group.bucket == .day, group.field.hasPrefix("properties.") else { return nil }
        let key = String(group.field.dropFirst("properties.".count))
        return isPropertyName(key) ? key : nil
    }

    /// Stands for a column by its identifier: the table finds its own column by the identifier (`ItemTableLayout.sort`).
    private static func placeholder(_ id: String) -> ItemTableColumn {
        ItemTableColumn(id: id, label: "", content: .title, style: .text)
    }

    /// Whether the window's choices differ from those the view opened with: its order, grouping, filters or the
    /// date its timeline shows.
    static func differs(
        _ options: ItemTableOptions?, timelineDate: String?, from seed: ItemTableOptions, seedTimelineDate: String?,
        dated: [ItemTableComparator]? = nil
    ) -> Bool {
        let options = shown(options ?? ItemTableOptions(), dated: dated)
        let seed = shown(seed, dated: dated)
        return options.filterChoices != seed.filterChoices || options.grouping != seed.grouping
            || sortKeys(options.sort) != sortKeys(seed.sort) || timelineDate != seedTimelineDate
    }

    /// The options as a list that shows its own order shows them: with no sort and no column to group by it is ordered
    /// by that order and has no grouping of a view's kind, however the options spell it.
    static func shown(_ options: ItemTableOptions, dated: [ItemTableComparator]?) -> ItemTableOptions {
        guard let dated, options.sort == nil else { return options }
        if case .column = options.grouping { return options }
        var shown = options
        shown.sort = dated
        shown.grouping = .none
        return shown
    }

    private static func sortKeys(_ sort: [ItemTableComparator]?) -> [String]? {
        sort?.map { "\($0.column.id) \($0.order == .forward)" }
    }

    /// The change that saves the window's choices to the view it shows, naming only the settings that differ from
    /// those it opened with, so a setting the window left alone is never sent. The window's filters take the place
    /// of the conditions they showed, so a filter removed in the window is removed from the view; the conditions the
    /// window cannot show stay as they are. A view groups
    /// by one thing, so where the timeline's date and the table's grouping both changed, the layout shown decides
    /// which is kept.
    static func change(
        _ window: Window, options: ItemTableOptions?, seed: ItemTableOptions, seedTimelineDate: String?,
        seededTypes: [String]?, view: LibraryView, catalogue: Catalogue
    ) -> (change: LibraryViewChange, unkept: [Unkept]) {
        let options = shown(options ?? ItemTableOptions(), dated: window.dated?.sort)
        let seed = shown(seed, dated: window.dated?.sort)
        var change = LibraryViewChange()
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        if sortKeys(options.sort) != sortKeys(seed.sort) {
            let sort = sort(window.sort)
            change.sort = sort.sort
            unkept += sort.unkept
        }
        let regrouped = options.grouping != seed.grouping
        let redated = window.timelineDate != seedTimelineDate
        var showsTimeline = false
        if case .timeline = window.layout { showsTimeline = true }
        if redated && (showsTimeline || !regrouped) {
            if let key = window.timelineDate {
                if isPropertyName(key) {
                    change.group = .set(LibraryViewGroup(field: "properties." + key, bucket: .day))
                } else {
                    unkept.append(.group(column: key))
                }
            } else {
                change.group = .clear
            }
            if regrouped {
                unkept.append(.group(column: window.grouping.map(label(of:)) ?? String(localized: "Group")))
            } else if let group = view.group, group.bucket != .day {
                // The days replace a grouping the view had, which the window did not change but would lose.
                let shown = columnID(of: group.field).flatMap { id in window.columns.first { $0.id == id } }
                unkept.append(.group(column: shown.map(label(of:)) ?? String(localized: "Group")))
            }
        } else if regrouped {
            let group = group(window.grouping)
            change.group = group.group.map { .set($0) } ?? .clear
            unkept += group.unkept
            if window.dated?.hasSections == true { unkept.append(.dateSections) }
            if redated { unkept.append(.group(column: String(localized: "Timeline date"))) }
        }
        if options.filterChoices != seed.filterChoices {
            let filter = replacing(
                view.query, with: choices(of: window), columns: window.columns, seededTypes: seededTypes, catalogue: catalogue)
            if filter.query != view.query {
                change.query = filter.query
            }
            unkept += filter.unkept
        }
        return (change, unkept)
    }

    // MARK: A view's filter as the window's

    /// The query to read a view's items with while the window's filters differ from the view's: the view's own with
    /// the conditions the window shows as filters taken out, and the types it shows as a Type filter. The window's
    /// filters then narrow what is read, so a value unchecked in one brings its items back. The conditions the window
    /// cannot show (those on a field no type declares), the tier and the states stay.
    /// Nil where the view's filter is one the core refuses, since nothing can be taken out of it.
    static func previewQuery(of query: LibraryViewQuery, seededTypes: [String]?, catalogue: Catalogue) -> LibraryViewQuery? {
        let parsed: Parsed
        do { parsed = try terms(of: query.filter) } catch { return nil }
        // A condition the window shows as written: a bare bool is a Yes/No column's, and any other is not.
        let shown = shownTerms(parsed).filter { term in
            if seededTypes != nil, term.column == typeColumnID { return false }
            guard let column = term.column, column.hasPrefix("field.") else { return true }
            let key = column.dropFirst("field.".count)
            let declared = catalogue.itemTypes.values.flatMap(\.fields).filter { $0.key == key }
            // A field no type declares has no column to narrow by, so the read keeps its condition.
            guard !declared.isEmpty else { return false }
            return declared.contains { $0.kind == .boolean } == term.isBare
        }
        let shownConditions = Set(shown.map(\.condition))
        let kept = parsed.terms.filter { !shownConditions.contains($0.condition) }
        var result = query
        if seededTypes != nil { result.types = [] }
        do {
            result.filter = kept.isEmpty ? nil : try FilterExpression(join: parsed.join, conditions: kept.map(\.condition)).encoded()
        } catch {
            return nil
        }
        return result
    }

    /// One condition of a view's filter, and the window filter it stands for where it is one.
    struct Term: Hashable {
        var condition: FilterCondition
        /// The table column it filters, and the category it keeps (or, where `isNegated`, leaves out).
        var column: String?
        var value: String?
        /// Whether its operand is a bool, as a filter on a Yes or No column is written.
        var isBare = false
        /// Whether it excludes the category: `neq`, and `exists` for the empty cell.
        var isNegated = false

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
        case (.exists, nil):
            term.column = column
            term.value = ""
            term.isNegated = true
        case (.eq, .text(let value)?):
            term.column = column
            term.value = value
        case (.neq, .text(let value)?):
            term.column = column
            term.value = value
            term.isNegated = true
        case (.eq, .bool(let value)?) where column.hasPrefix("field."):
            term.column = column
            term.value = value ? "true" : "false"
            term.isBare = true
        case (.neq, .bool(let value)?) where column.hasPrefix("field."):
            term.column = column
            term.value = value ? "true" : "false"
            term.isBare = true
            term.isNegated = true
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

    /// The window filters a filter's conditions stand for. The window joins a column's values by OR, or by AND
    /// where they are excluded, and its columns by AND, so conditions joined by AND show where each column has one
    /// or all of its conditions exclude, and conditions joined by OR show only where all of them keep values of
    /// one column.
    private static func shownTerms(_ parsed: Parsed) -> [Term] {
        let mapped = parsed.terms.filter { $0.column != nil }
        if parsed.join == .any, parsed.terms.count > 1 {
            let columns = Set(mapped.map(\.column))
            return mapped.count == parsed.terms.count && columns.count == 1 && mapped.allSatisfy({ !$0.isNegated }) ? mapped : []
        }
        let byColumn = Dictionary(grouping: mapped, by: { $0.column! })
        return mapped.filter { term in
            let terms = byColumn[term.column!]!
            return terms.count == 1 || terms.allSatisfy(\.isNegated)
        }
    }

    private static func shownChoices(_ terms: [Term]) -> [String: FilterChoice] {
        terms.reduce(into: [:]) { result, term in
            var choice = result[term.column!] ?? FilterChoice(values: [], isNegated: term.isNegated)
            choice.values.insert(term.value!)
            result[term.column!] = choice
        }
    }

    /// Whether this leaves the whole filter unwritable, rather than only one column's part of it.
    private static func refusesFilter(_ unkept: Unkept) -> Bool {
        switch unkept {
        case .mixedFilters, .tooManyFilters, .refused: true
        default: false
        }
    }

    /// The view's query with the window's filters in place of the conditions the window showed: the conditions
    /// it could not show stay as they are, in order. A window filter the view
    /// cannot hold leaves the query whole, so a filter is never dropped for one the window could not save.
    static func replacing(
        _ query: LibraryViewQuery, with choices: [String: FilterChoice], columns: [ItemTableColumn], seededTypes: [String]?,
        catalogue: Catalogue
    ) -> (query: LibraryViewQuery, unkept: [Unkept]) {
        let parsed: Parsed
        do { parsed = try terms(of: query.filter) } catch { return (query, [.refused(message(of: error))]) }
        let filterable = Dictionary(uniqueKeysWithValues: columns.filter(\.isCategorical).map { ($0.id, $0) })
        // Where the view's types stand for the Type filter, its conditions on the type are not the filter's.
        let shown = shownTerms(parsed).filter { seededTypes == nil || $0.column != typeColumnID }
        // A column the window lacks, or one whose filter it writes otherwise, shows none of its conditions.
        let hiddenColumns = Set(shown.compactMap { term -> String? in
            guard let column = filterable[term.column!], (column.style == .boolean) == term.isBare else { return term.column }
            return nil
        })
        let owned = shown.filter { !hiddenColumns.contains($0.column!) }
        var seeded = shownChoices(owned)
        if let seededTypes, filterable[typeColumnID] != nil {
            seeded[typeColumnID] = FilterChoice(values: Set(seededTypes), isNegated: false)
        }
        var window = choices.filter { filterable[$0.key] != nil && !$0.value.values.isEmpty }
        guard window != seeded else { return (query, []) }

        var result = query
        if let column = filterable[typeColumnID] {
            if let choice = window[typeColumnID], !choice.isNegated {
                window[typeColumnID] = nil
                let chosen = choice.values.subtracting([""])
                if !chosen.isEmpty, chosen != Set(query.types.map(\.rawValue)) {
                    guard let types = types(keeping: chosen, beside: [], catalogue: catalogue) else {
                        return (query, [.filter(column: label(of: column))])
                    }
                    result.types = types
                }
            } else if seededTypes != nil {
                result.types = []
            }
        }
        let ownedConditions = Set(owned.map(\.condition))
        let kept = parsed.terms.filter { !ownedConditions.contains($0.condition) }
        let combination = combined(Parsed(terms: kept, join: parsed.join), adding: window, columns: columns, keeping: nil)
        if combination.unkept.contains(where: refusesFilter) { return (query, combination.unkept) }
        result.filter = combination.filter ?? (kept.isEmpty ? nil : try? FilterExpression(join: parsed.join, conditions: kept.map(\.condition)).encoded())
        return (result, combination.unkept)
    }
}
