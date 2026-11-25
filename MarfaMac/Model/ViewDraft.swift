import Foundation
import Marfa

/// How what a window shows becomes a view's settings, and a view's settings the window's table options. Marfa
/// sorts, groups and filters by fields, while the table does so by columns, so only the columns that stand for a
/// field carry over; the rest are named, so the person knows what the view will not keep.
nonisolated enum ViewDraft {
    /// What a window shows of a place, as the table works it out.
    struct Window {
        var place: PlaceView
        var columns: [ItemTableColumn]
        var sort: [ItemTableComparator]
        var grouping: ItemTableColumn?
        /// How `grouping` groups: each value, a date's span, Set or Not Set, or status groups.
        var groupMode: GroupMode = .value
        /// The groups the window puts first and leaves out, by key (`GroupKey`).
        var groupOrder: [String]?
        var hiddenGroups: Set<String>?
        /// The filters the window applies, in every layout.
        var filter = FilterState()
        /// The fields the place offers a filter on, by identifier.
        var targets: [String: FilterTarget] = [:]
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
        /// The window's From, Archived Items and Include Kinds (`Browser.listing`).
        var listing = PlaceListing()
        /// The search's tokens that are not among the filters, as the field words them, which a view does not keep.
        var searchTokens: [String] = []
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
        case list(ItemOrder)
        /// Lanes by the board's grouping, which the window names as the table's (`grouping`, `groupMode`).
        case board
        /// Days by a date field, or none where the timeline has no field.
        case timeline(key: String?, label: String)
        /// Items placed by their own dates, in no order and no groups of a view's.
        case calendar
    }

    /// A choice of the window's that the view will not keep.
    enum Unkept: Hashable, Sendable {
        case search(String)
        /// A search token, as the field words it.
        case searchToken(String)
        /// A column whose filter a view cannot express.
        case filter(column: String)
        /// Filters that need both AND and OR, which a Marfa filter never mixes.
        case mixedFilters
        /// Filters that would need more conditions than a Marfa filter takes.
        case tooManyFilters
        /// A filter the core refuses, as it words the refusal.
        case refused(String)
        /// A filter relative to the day, such as the last 7 days, written as the row reads it: only this Mac keeps it.
        case relativeFilter(String)
        case sort(column: String)
        case group(column: String)
        /// A way of grouping a view's group cannot hold yet, such as Set or Not Set, named by its field and its way.
        case groupMode(column: String, mode: String)

        /// Said where it is made, in the row or the panel, so never told again once a view is written.
        var isSaidWhereMade: Bool {
            switch self {
            case .search, .searchToken, .relativeFilter: true
            default: false
            }
        }
    }

    /// The settings a view saves, apart from its title, and what of the window it leaves out.
    struct Draft: Hashable, Sendable {
        var query: LibraryViewQuery
        var sort: [LibraryViewSort]
        var group: LibraryViewGroup?
        var unkept: [Unkept] = []
    }

    /// The query what a window shows stands for, with the window's From, Archived Items and Include Kinds, or nil
    /// where a view cannot stand for it: an index. The Library lists its tier and the Feed its own, whatever the
    /// From. A type's view holds its kinds as Marfa takes a type, unless the window leaves them out, which an
    /// exact-type condition says. A collection's view lists its members, though by the view's own order, since a
    /// view cannot sort by an edge's position.
    static func query(
        for shown: PlaceView, listing: PlaceListing = PlaceListing(), catalogue: Catalogue, views: [LibraryView]
    ) -> LibraryViewQuery? {
        let states = listing.archived.states
        let tier = listing.scope.tier
        switch shown.view {
        case .saved(let id): return views.first { $0.id == id }?.query
        case .favorites:
            return LibraryViewQuery(tier: tier, states: states, filter: text(of: FilterCondition(field: .tags, operator: .contains, value: .text(ItemTag.favorite))))
        case .own: break
        }
        switch shown.place {
        case .library: return LibraryViewQuery(tier: .library, states: states)
        case .feed: return LibraryViewQuery(tier: .feed, states: states)
        case .archive: return LibraryViewQuery(states: [.archived])
        case .type(let type):
            let own = listing.includesKinds || catalogue.descendants(of: type).isEmpty
                ? nil : text(of: FilterCondition(field: .system(.type), operator: .eq, value: .text(type.rawValue)))
            return LibraryViewQuery(types: [type], tier: tier, states: states, filter: own)
        case .source(let name):
            return LibraryViewQuery(tier: tier, states: states, filter: text(of: FilterCondition(field: .system(.source), operator: .eq, value: .text(name))))
        case .collection(let id):
            let member = FilterField.edge(type: MarfaMapping.collectionEdge, direction: .outbound)
            return LibraryViewQuery(tier: tier, states: states, filter: text(of: FilterCondition(field: member, operator: .eq, value: .text(id.rawValue))))
        case .types, .sources, .collections: return nil
        }
    }

    /// The settings for a new view of what the window shows, or nil where its place cannot be a view. Every layout
    /// applies the filters; and each layout gives the order and grouping it shows, never the table's when the table
    /// is not showing.
    static func draft(_ window: Window, catalogue: Catalogue, views: [LibraryView]) -> Draft? {
        guard var base = query(for: window.place, listing: window.listing, catalogue: catalogue, views: views) else { return nil }
        if window.place.savedView != nil {
            // A view's From and Archived Items are the window's, as its filters are.
            if ListScope(tier: base.tier) != window.listing.scope { base.tier = window.listing.scope.tier }
            if ArchivedItems(states: base.states) != window.listing.archived { base.states = window.listing.archived.states }
        }
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        unkept += window.searchTokens.map(Unkept.searchToken)
        let filtered: (query: LibraryViewQuery, unkept: [Unkept])
        if window.place.savedView != nil {
            // A view's place shows the view's own filter as the window's filters, so they stand in for it.
            let replaced = replacing(
                base, with: window.filter, targets: window.targets, seededTypes: window.seededTypes, catalogue: catalogue)
            filtered = (replaced.query, replaced.unkept)
        } else {
            filtered = adding(window.filter, to: base, targets: window.targets, catalogue: catalogue)
        }
        unkept += relativeFilters(of: window)
        let arrangement = arrangement(of: window)
        return Draft(query: filtered.query, sort: arrangement.sort, group: arrangement.group, unkept: unkept + filtered.unkept + arrangement.unkept)
    }

    /// The order and grouping the window's layout shows.
    private static func arrangement(of window: Window) -> (sort: [LibraryViewSort], group: LibraryViewGroup?, unkept: [Unkept]) {
        switch window.layout {
        case .table:
            let sort = sort(window.sort)
            var group = group(window.grouping, mode: window.groupMode)
            if var held = group.group, let column = window.grouping {
                if let order = window.groupOrder, !order.isEmpty { held.order = json(order, of: column, mode: window.groupMode) }
                if let hidden = window.hiddenGroups, !hidden.isEmpty { held.hidden = json(hidden.sorted(), of: column, mode: window.groupMode) }
                group.group = held
            }
            return (sort.sort, group.group, sort.unkept + group.unkept)
        case .list(let order):
            let field = switch order.sort {
            case .title: "title"
            case .dateEdited: "updated_at"
            case .dateCreated: "created_at"
            }
            let sort = LibraryViewSort(field: field, ascending: order.sort == .title)
            // The list's sections by date are that date by day, which a list reads as Today, Yesterday and the rest.
            let days = order.groupsByDate && order.sort != .title ? LibraryViewGroup(field: field, bucket: .day) : nil
            return ([sort], days, [])
        case .board:
            // The cards follow the sort the window shows them in, which is by title where nothing sorts them, and the lanes
            // are the board's grouping, kept as the table's is.
            return arrangement(of: Window(
                place: window.place, columns: window.columns, sort: window.sort, grouping: window.grouping, groupMode: window.groupMode,
                groupOrder: window.groupOrder, hiddenGroups: window.hiddenGroups, layout: .table, listing: window.listing))
        case .calendar:
            return ([], nil, [])
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
        case .occurred: "occurred_at"
        case .field(let field): isPropertyName(field.key) ? "properties." + field.key : nil
        case .parent, .children, .collections, .count, .duration, .tags, .source: nil
        }
    }

    /// The table column that shows a field, for a window to sort or group by.
    static func columnID(of field: String) -> String? {
        switch field {
        case "title": return "title"
        case "type": return "type"
        case "created_at": return "created"
        case "updated_at": return "edited"
        case "occurred_at": return ItemTableColumn.occurred.id
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

    /// The group a view holds for the window's grouping by `column`. A value grouping names the order the app lists the
    /// values in where the column has one (`declaredOrder(of:)`), so other apps list them alike.
    static func group(_ column: ItemTableColumn?, mode: GroupMode = .value) -> (group: LibraryViewGroup?, unkept: [Unkept]) {
        guard let column else { return (nil, []) }
        if column.content == .parent { return (LibraryViewGroup(field: parentField), []) }
        // Marfa groups by each item's own status group, whichever type's status column the window groups by.
        if mode == .statusGroups { return (LibraryViewGroup(field: statusGroupField), []) }
        if column.content == .source, mode == .value { return (LibraryViewGroup(field: sourceField), []) }
        guard let field = field(of: column) else { return (nil, [.group(column: label(of: column))]) }
        switch mode {
        case .value: return (LibraryViewGroup(field: field, order: declaredOrder(of: column)), [])
        case .bucket(let bucket): return (LibraryViewGroup(field: field, bucket: bucket), [])
        case .presence:
            // Marfa takes presence on a property, and not on an item's own dates, which every item may not have.
            guard field.hasPrefix(propertyPrefix) else { return (nil, [.groupMode(column: label(of: column), mode: mode.title)]) }
            return (LibraryViewGroup(field: field, byPresence: true), [])
        case .statusGroups: return (nil, [])
        }
    }

    static let statusGroupField = "status_group"
    static let sourceField = "source"
    private static let propertyPrefix = "properties."

    /// Group keys as a view's lists hold them (`GroupKey.json`): a yes-or-no column's and Set or Not Set's as bools,
    /// and a status group's as Marfa's four words, with No Status as `null`.
    static func json(_ keys: [String], of column: ItemTableColumn, mode: GroupMode = .value) -> [JSONValue] {
        switch mode {
        case .presence:
            return keys.compactMap { [GroupKey.set, GroupKey.notSet].contains($0) ? GroupKey.json($0, booleans: true) : nil }
        case .statusGroups:
            return keys.compactMap { $0 == GroupKey.none || StatusGroup(rawValue: $0) != nil ? GroupKey.json($0, booleans: false) : nil }
        case .value, .bucket:
            return keys.compactMap { GroupKey.json($0, booleans: column.style == .boolean) }
        }
    }

    /// The order the app lists a column's values in, as a view's `group.order`: a status's words by their groups and
    /// then as declared, a choice's options as declared. Empty for any other column, whose groups follow Marfa's order.
    static func declaredOrder(of column: ItemTableColumn) -> [JSONValue] {
        guard let field = column.field else { return [] }
        let words = field.options.filter { !$0.isEmpty }
        switch column.style {
        case .status:
            return words.enumerated().sorted { (column.rank(of: $0.element), $0.offset) < (column.rank(of: $1.element), $1.offset) }
                .map { .string($0.element) }
        case .priority, .choice: return words.map { .string($0) }
        default: return []
        }
    }

    /// The group a write sends in place of `held`, the view's own. Grouping by the same field keeps the groups `held`
    /// orders and hides, which another app may have set, where they can name a group of the new way of grouping: a
    /// date's span keeps dates whatever the span, and Set or Not Set keeps only `true` and `false`. Grouping by another
    /// field drops them, since they name the old field's values, and orders the groups as the app lists them.
    static func kept(_ group: LibraryViewGroup?, from held: LibraryViewGroup?) -> LibraryViewGroup? {
        guard var group else { return nil }
        if let held, held.field == group.field {
            let sameWay = held.byPresence == group.byPresence && (held.bucket == nil) == (group.bucket == nil)
            let fits = { (key: JSONValue) in sameWay || names(key, in: group) }
            group.order = held.order.filter(fits)
            group.hidden = held.hidden.filter(fits)
        }
        return group
    }

    /// Whether a key can name a group of `group`: Set or Not Set's are bools, a date span's dates or the null group.
    private static func names(_ key: JSONValue, in group: LibraryViewGroup) -> Bool {
        if group.byPresence { if case .bool = key { return true } else { return false } }
        guard group.bucket != nil else { return true }
        switch key {
        case .null: return true
        case .string(let text): return text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
        default: return false
        }
    }

    private static func label(of column: ItemTableColumn) -> String {
        column.label.isEmpty ? String(localized: "Parent") : column.label
    }

    // MARK: Filters

    /// The filters relative to the day that a view cannot keep, named as the row reads them.
    static func relativeFilters(of window: Window) -> [Unkept] {
        window.filter.relative.compactMap { clause in
            window.targets[clause.field].map { .relativeFilter(FilterWording.sentence(of: clause, target: $0, calendar: .current)) }
        }
    }

    /// How a Type filter of exactly these types is saved beside the types a new view lists: the types the query then
    /// lists (nil where they stay), and whether the filter stays as an exact-type condition. Marfa lists a type with
    /// its subtypes, so a chosen type that has any cannot be said by the types alone and stays an exact-type
    /// condition. The listed types stay only where the chosen ones are within their subtrees and some have subtypes
    /// (the listed types then hold them and the condition narrows); otherwise the chosen types become the listed ones.
    static func narrowing(_ chosen: Set<String>, listed: [TypeID], catalogue: Catalogue) -> (types: [TypeID]?, asFilter: Bool) {
        let hasSubtypes = chosen.contains { !catalogue.descendants(of: TypeID($0)).isEmpty }
        let sorted = chosen.sorted().map { TypeID($0) }
        let scope = Set(listed).union(listed.flatMap { catalogue.descendants(of: $0) })
        if !listed.isEmpty, !chosen.allSatisfy({ scope.contains(TypeID($0)) }) { return (sorted, hasSubtypes) }
        if hasSubtypes { return (nil, true) }
        return (Set(listed.map(\.rawValue)) == chosen ? nil : sorted, false)
    }

    /// Whether an existing view keeps the types it lists where a Type filter of exactly these types is saved: they lie
    /// within the listed types' subtrees, and are not just those types again with no subtypes (which hides nothing).
    /// The filter is then an exact-type condition beside the view's own types.
    static func keepsListedTypes(_ chosen: Set<String>, listed: [TypeID], catalogue: Catalogue) -> Bool {
        guard !listed.isEmpty else { return false }
        let scope = Set(listed).union(listed.flatMap { catalogue.descendants(of: $0) })
        guard chosen.allSatisfy({ scope.contains(TypeID($0)) }) else { return false }
        let hasSubtypes = chosen.contains { !catalogue.descendants(of: TypeID($0)).isEmpty }
        return hasSubtypes || Set(listed.map(\.rawValue)) != chosen
    }

    /// The types a view lists, shown as a Type filter where it lists several and none has subtypes: the items are
    /// then all of those types, so the filter hides nothing until it is changed. A view whose filter has a condition
    /// on the type shows that condition as its Type filter instead, so its types are not seeded.
    static func seededTypes(of query: LibraryViewQuery, catalogue: Catalogue) -> [String]? {
        guard query.types.count > 1, query.types.allSatisfy({ catalogue.descendants(of: $0).isEmpty }) else { return nil }
        if let parsed = try? terms(of: query.filter), parsed.terms.contains(where: { if case .system(.type) = $0.field { true } else { false } }) { return nil }
        return query.types.map(\.rawValue)
    }

    /// The most conditions a Marfa filter holds.
    static let maxConditions = 10
    /// How many sort keys a window keeps, in the panel and in the table's header.
    static let maxSortKeys = 10

    /// What the core says of a refusal, which a person is told as it is worded.
    static func message(of error: any Error) -> String {
        (error as? MarfaError)?.message ?? error.localizedDescription
    }

    static func isPropertyName(_ key: String) -> Bool {
        key.wholeMatch(of: /[a-zA-Z_][a-zA-Z0-9_]*/) != nil
    }

    // MARK: Opening a view

    /// The table options a view opens with: its order and grouping, where the table has a column for them.
    /// A date grouped by day, week, month or year opens grouped so. A view with no grouping opens ungrouped, and one
    /// grouped by what the app cannot show (a link it has no column for, a span of something that is no date) opens
    /// ungrouped too; its group stays in the view as it is, since a write names it only when the person changes it.
    /// A view that lists several types opens with a Type filter keeping them.
    static func options(for view: LibraryView, catalogue: Catalogue) -> ItemTableOptions {
        var options = ItemTableOptions()
        let sort = view.sort.compactMap { key in
            columnID(of: key.field).map { ItemTableComparator(column: placeholder($0), order: key.ascending ? .forward : .reverse) }
        }
        options.sort = sort.isEmpty ? nil : sort
        if let group = view.group, let id = groupColumnID(of: group, view: view, catalogue: catalogue),
           let mode = mode(of: group, column: id, catalogue: catalogue) {
            options.grouping = .column(id, by: mode)
            let order = group.order.compactMap(GroupKey.key(of:))
            let hidden = Set(group.hidden.compactMap(GroupKey.key(of:)))
            options.groupOrder = order.isEmpty ? nil : order
            options.hiddenGroups = hidden.isEmpty ? nil : hidden
        } else {
            options.grouping = .none
        }
        options.filter = filterState(of: view, catalogue: catalogue)
        options.scope = ListScope(tier: view.query.tier)
        options.archived = ArchivedItems(states: view.query.states)
        return options
    }

    /// How the window groups by a view's group, or nil where it cannot: a span needs a date, which an item's own dates
    /// are and a field is where a type declares it one.
    private static func mode(of group: LibraryViewGroup, column id: String, catalogue: Catalogue) -> GroupMode? {
        guard group.otherBucket == nil else { return nil }
        if group.field == statusGroupField { return group.bucket == nil && !group.byPresence ? .statusGroups : nil }
        if group.byPresence { return group.bucket == nil && id.hasPrefix(Browser.fieldColumnPrefix) ? .presence : nil }
        guard let bucket = group.bucket else { return .value }
        if [ItemTableColumn.created.id, ItemTableColumn.edited.id, ItemTableColumn.occurred.id].contains(id) { return .bucket(bucket) }
        guard id.hasPrefix(Browser.fieldColumnPrefix) else { return nil }
        let key = String(id.dropFirst(Browser.fieldColumnPrefix.count))
        let isDate = catalogue.itemTypes.values.contains { type in type.fields.contains { field in
            guard field.key == key, case .date = field.kind else { return false }
            return true
        } }
        return isDate ? .bucket(bucket) : nil
    }

    /// The column the window groups a view's group by. Status groups stand on the status column of the first type
    /// the view lists, or of every type where it lists none, as Group by offers them (`GroupOffer`).
    private static func groupColumnID(of group: LibraryViewGroup, view: LibraryView, catalogue: Catalogue) -> String? {
        switch group.field {
        case sourceField: return ItemTableColumn.source.id
        case statusGroupField:
            let listed = view.query.types.isEmpty
                ? Array(catalogue.itemTypes.keys) : view.query.types + view.query.types.flatMap { catalogue.descendants(of: $0) }
            let key = listed.sorted { $0.rawValue < $1.rawValue }.lazy.compactMap { catalogue.itemTypes[$0]?.statusField?.key }.first
            return key.map { Browser.fieldColumnPrefix + $0 }
        default: return columnID(of: group.field)
        }
    }

    /// The date field a view's days are grouped by, which a timeline shows its items by.
    static func timelineDate(of view: LibraryView) -> String? {
        guard let group = view.group, group.bucket == .day, group.field.hasPrefix("properties.") else { return nil }
        let key = String(group.field.dropFirst("properties.".count))
        return isPropertyName(key) ? key : nil
    }

    /// Stands for a column by its identifier: the table finds its own column by the identifier (`ItemTableLayout.sort`).
    static func placeholder(_ id: String) -> ItemTableColumn {
        ItemTableColumn(id: id, label: "", content: .title, style: .text)
    }

    /// Whether the window's choices differ from those the view opened with: its order, grouping, filters or the
    /// date its timeline shows.
    static func differs(
        _ options: ItemTableOptions?, timelineDate: String?, from seed: ItemTableOptions, seedTimelineDate: String?,
        dated: Dated? = nil
    ) -> Bool {
        let options = shown(options ?? ItemTableOptions(), dated: dated)
        let seed = shown(seed, dated: dated)
        return !options.filter.isSame(as: seed.filter) || options.grouping != seed.grouping || reorders(options, from: seed)
            || sortKeys(options.sort) != sortKeys(seed.sort) || timelineDate != seedTimelineDate
            || options.scope != seed.scope || options.archived != seed.archived
    }

    /// The options as a list that shows its starting order shows them: with no sort and no column to group by it is
    /// ordered by that order and grouped by its date by day where it shows sections, however the options spell it.
    static func shown(_ options: ItemTableOptions, dated: Dated?) -> ItemTableOptions {
        guard let dated, options.sort == nil else { return options }
        if options.grouping.columnID != nil { return options }
        var shown = options
        shown.sort = dated.sort
        shown.grouping = dated.hasSections ? dated.sort.first.map { .column($0.column.id, by: .bucket(.day)) } ?? .none : .none
        return shown
    }

    /// Whether the groups put first or left out differ, which a grouping that changed starts afresh.
    static func reorders(_ options: ItemTableOptions, from seed: ItemTableOptions) -> Bool {
        options.grouping == seed.grouping
            && ((options.groupOrder ?? []) != (seed.groupOrder ?? []) || (options.hiddenGroups ?? []) != (seed.hiddenGroups ?? []))
    }

    static func sortKeys(_ sort: [ItemTableComparator]?) -> [String]? {
        sort?.map { "\($0.column.id) \($0.order == .forward)" }
    }

    /// The change that saves the window's choices to the view it shows, naming only the settings that differ from
    /// those it opened with, so a setting the window left alone is never sent. `replaced` holds the view's earlier
    /// groups by field, whose order and hidden groups come back when the window groups by that field again. The window's filters take the place
    /// of the conditions they showed, so a filter removed in the window is removed from the view; the conditions the
    /// window cannot show stay as they are. A view groups
    /// by one thing, so where the timeline's date and the table's grouping both changed, the layout shown decides
    /// which is kept.
    static func change(
        _ window: Window, options: ItemTableOptions?, seed: ItemTableOptions, seedTimelineDate: String?,
        seededTypes: [String]?, view: LibraryView, catalogue: Catalogue, replaced: [String: LibraryViewGroup] = [:]
    ) -> (change: LibraryViewChange, unkept: [Unkept]) {
        let options = shown(options ?? ItemTableOptions(), dated: window.dated)
        let seed = shown(seed, dated: window.dated)
        var change = LibraryViewChange()
        var unkept: [Unkept] = []
        if let search = window.search { unkept.append(.search(search)) }
        unkept += window.searchTokens.map(Unkept.searchToken)
        if sortKeys(options.sort) != sortKeys(seed.sort) {
            let sort = sort(window.sort)
            change.sort = sort.sort
            unkept += sort.unkept
        }
        let regrouped = options.grouping != seed.grouping
        let redated = window.timelineDate != seedTimelineDate
        if regrouped || redated {
            var showsTimeline = false
            if case .timeline = window.layout { showsTimeline = true }
            // In a view the timeline's date and a grouping by its day are one setting (`Browser.followDayGrouping`).
            let agrees = window.timelineDate.map { options.grouping == .column(Browser.fieldColumnPrefix + $0, by: .bucket(.day)) }
                ?? (options.grouping.columnID == nil)
            var target: LibraryViewGroup??
            if redated && (showsTimeline || !regrouped || agrees) {
                if let key = window.timelineDate {
                    if isPropertyName(key) {
                        target = .some(LibraryViewGroup(field: "properties." + key, bucket: .day))
                    } else {
                        unkept.append(.group(column: key))
                    }
                } else {
                    target = .some(nil)
                }
                if regrouped && !agrees {
                    unkept.append(.group(column: window.grouping.map(label(of:)) ?? String(localized: "Group")))
                } else if case .some(let days) = target, let group = view.group, group.bucket != .day, group.field != days?.field {
                    // The days replace a grouping the view had, which the window did not ask for.
                    let shown = columnID(of: group.field).flatMap { id in window.columns.first { $0.id == id } }
                    unkept.append(.group(column: shown.map(label(of:)) ?? String(localized: "Group")))
                }
            } else {
                let group = group(window.grouping, mode: window.groupMode)
                // A grouping the view cannot hold leaves the view's own as it is.
                if group.unkept.isEmpty { target = .some(group.group) }
                unkept += group.unkept
                if redated { unkept.append(.group(column: String(localized: "Timeline date"))) }
            }
            if let target {
                let held = view.group.flatMap { $0.field == target?.field ? $0 : nil } ?? target.flatMap { replaced[$0.field] }
                change.group = kept(target, from: held).map { .set($0) } ?? .clear
            }
        } else if reorders(options, from: seed), var group = view.group, let column = window.grouping {
            // The same grouping with other groups first or left out: Marfa's `group.order` and `group.hidden`.
            group.order = json(options.groupOrder ?? [], of: column, mode: window.groupMode)
            group.hidden = json((options.hiddenGroups ?? []).sorted(), of: column, mode: window.groupMode)
            change.group = .set(group)
        }
        if !options.filter.savable.isSame(as: seed.filter.savable) {
            let filter = replacing(
                view.query, with: window.filter, targets: window.targets, seededTypes: seededTypes, catalogue: catalogue)
            if filter.query != view.query {
                change.query = filter.query
            }
            unkept += filter.unkept
        }
        if let scope = options.scope, scope != seed.scope {
            var query = change.query ?? view.query
            query.tier = scope.tier
            change.query = query
        }
        if let archived = options.archived, archived != seed.archived {
            var query = change.query ?? view.query
            query.states = archived.states
            change.query = query
        }
        unkept += relativeFilters(of: window)
        return (change, unkept)
    }
}
