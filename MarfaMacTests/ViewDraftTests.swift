import Foundation
import Testing
@testable import MarfaMac

/// What a window shows, as a view's settings, and a view's settings, as what a window shows.
struct ViewDraftTests {
    private static let task = TypeID("core.task")
    private static let ticket = TypeID("aic.ticket")
    private static let ticketTask = TypeID("aic.ticket.task")
    private static let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .choice(["todo", "done"]), declaredBy: task)
    private static let done = ItemTypeInfo.Field(key: "done", label: "Done", kind: .boolean, declaredBy: task)
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: task, label: "Task", fields: [status, done], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: ticket, label: "Ticket", fields: [], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: ticketTask, label: "Task", fields: [], titleField: "title", bodyField: "body", parent: ticket),
    ])
    private static let statusColumn = ItemTableColumn(id: "field.status", label: "Status", content: .field(status), style: .status)
    private static let doneColumn = ItemTableColumn(id: "field.done", label: "Done", content: .field(done), style: .boolean)
    /// A field Marfa cannot name, so a view cannot sort, group or filter by it.
    private static let dueColumn = ItemTableColumn(
        id: "field.due-date", label: "Due", content: .field(ItemTypeInfo.Field(key: "due-date", label: "Due", kind: .text, declaredBy: task)),
        style: .text)
    private static let columns = [ItemTableColumn.title, statusColumn, doneColumn, .parent, .type, dueColumn, .edited]

    private static let targets = FilterOffer.make(columns: columns, types: [task], catalogue: catalogue).targets

    /// Clauses for the old shape of a filter: a column's values joined by OR, or by AND where the column is left out.
    private static func state(_ filters: [String: Set<String>], negated: Set<String> = []) -> FilterState {
        // In the order the columns have them, as a row of chips follows the person's choices.
        let order = columns.map(\.id)
        return FilterState(clauses: filters.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }.map {
            FilterClause(field: $0, op: negated.contains($0) ? .isNot : .is, values: Array(filters[$0]!))
        })
    }

    /// The values each field's clauses hold, whatever their operator.
    private static func shownFilters(_ options: ItemTableOptions) -> [String: Set<String>] {
        options.filter.clauses.reduce(into: [:]) { $0[$1.field, default: []].formUnion($1.values) }
    }

    private static func negated(_ options: ItemTableOptions) -> Set<String> {
        Set(options.filter.clauses.filter { $0.op == .isNot }.map(\.field))
    }

    private static func window(
        _ place: SidebarItem, sort: [ItemTableComparator] = [], grouping: ItemTableColumn? = nil,
        filters: [String: Set<String>] = [:], negated: Set<String> = [], search: String? = nil, layout: ViewDraft.Layout = .table,
        timelineDate: String? = nil, includesSubtypes: Bool = false
    ) -> ViewDraft.Window {
        ViewDraft.Window(
            place: place, columns: columns, sort: sort, grouping: grouping, filter: state(filters, negated: negated), targets: targets,
            search: search, layout: layout, timelineDate: timelineDate, includesSubtypes: includesSubtypes)
    }

    /// A filter added to `base` as a place's filter, through the same call a new view's draft makes.
    private static func filter(
        _ base: String?, adding filters: [String: Set<String>], negated: Set<String> = []
    ) -> (filter: String?, unkept: [ViewDraft.Unkept]) {
        let result = ViewDraft.adding(state(filters, negated: negated), to: LibraryViewQuery(filter: base), targets: targets, catalogue: catalogue)
        return (result.query.filter, result.unkept)
    }

    private static func draft(_ window: ViewDraft.Window, views: [LibraryView] = []) -> ViewDraft.Draft? {
        ViewDraft.draft(window, catalogue: catalogue, views: views)
    }

    // MARK: Places

    @Test func eachPlaceAViewCanStandForBecomesItsQuery() {
        let active: Set<ItemState> = [.active]
        func query(_ place: SidebarItem) -> LibraryViewQuery? {
            ViewDraft.query(for: place, catalogue: Self.catalogue, views: [])
        }
        #expect(query(.allItems) == LibraryViewQuery(states: active))
        #expect(query(.inbox) == LibraryViewQuery(tier: .feed, states: active))
        #expect(query(.favorites) == LibraryViewQuery(states: active, filter: #"tags contains "favorite""#))
        #expect(query(.files) == LibraryViewQuery(types: [TypeID.file], states: active))
        #expect(query(.source("mail")) == LibraryViewQuery(states: active, filter: #"source eq "mail""#))
        // A type's place holds its own items, and Marfa takes a type with its subtypes, so a type with any is narrowed.
        #expect(query(.itemType("core.task")) == LibraryViewQuery(types: [Self.task], states: active))
        #expect(query(.itemType("aic.ticket")) == LibraryViewQuery(types: [Self.ticket], states: active, filter: #"type eq "aic.ticket""#))
        // A collection's members are the items with an `in-collection` edge to it, written at the member.
        #expect(query(.collection(ItemID("c1"))) == LibraryViewQuery(states: active, filter: #"edge[in-collection] eq "c1""#))
    }

    @Test func placesNoViewCanStandForOfferNone() {
        for place: SidebarItem in [.recents, .sources, .collections, .favoriteItem(ItemID("a"))] {
            #expect(ViewDraft.query(for: place, catalogue: Self.catalogue, views: []) == nil)
            #expect(Self.draft(Self.window(place)) == nil)
        }
        // A view the library no longer holds cannot be saved anew.
        #expect(Self.draft(Self.window(.view(ItemID("gone")))) == nil)
    }

    @Test func aViewSavedAgainKeepsItsOwnQuery() throws {
        let base = LibraryView(
            id: ItemID("v"), title: "Open", version: 3,
            query: LibraryViewQuery(types: [Self.task], tier: .library, filter: #"properties.priority eq "high""#, beneath: ItemID("p")))
        let draft = try #require(Self.draft(Self.window(.view(base.id)), views: [base]))
        #expect(draft.query == base.query)
    }

    // MARK: Sort and group

    @Test func sortAndGroupKeepTheColumnsThatStandForFields() throws {
        let window = Self.window(
            .allItems,
            sort: [
                ItemTableComparator(column: Self.statusColumn, order: .forward),
                ItemTableComparator(column: Self.dueColumn, order: .forward),
                ItemTableComparator(column: .edited, order: .reverse),
            ],
            grouping: Self.statusColumn, search: "plans")
        let draft = try #require(Self.draft(window))
        #expect(draft.sort == [
            LibraryViewSort(field: "properties.status", ascending: true),
            LibraryViewSort(field: "updated_at", ascending: false),
        ])
        #expect(draft.group == LibraryViewGroup(field: "properties.status", order: ViewDraft.declaredOrder(of: Self.statusColumn)))
        #expect(draft.unkept == [.search("plans"), .sort(column: "Due")])
    }

    @Test func groupingByParentIsKeptAndByAnUnnamedFieldIsNot() {
        #expect(ViewDraft.group(.parent).group == LibraryViewGroup(field: "backref[parent-of]"))
        #expect(ViewDraft.group(Self.dueColumn) == (nil, [.group(column: "Due")]))
        #expect(ViewDraft.group(nil) == (nil, []))
    }

    @Test func aFieldMarfaCannotNameIsNotKept() {
        let odd = ItemTypeInfo.Field(key: "due-date", label: "Due", kind: .text, declaredBy: Self.task)
        let column = ItemTableColumn(id: "field.due-date", label: "Due", content: .field(odd), style: .text)
        #expect(ViewDraft.field(of: column) == nil)
        #expect(ViewDraft.sort([ItemTableComparator(column: column)]).unkept == [.sort(column: "Due")])
    }

    @Test func aViewOpensWithItsOwnOrderAndGrouping() {
        let view = LibraryView(
            id: ItemID("v"), title: "V",
            sort: [
                LibraryViewSort(field: "properties.status", ascending: true),
                LibraryViewSort(field: "occurred_at", ascending: true),
                LibraryViewSort(field: "updated_at", ascending: false),
            ],
            group: LibraryViewGroup(field: "type"))
        let options = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(options.sort?.map(\.column.id) == ["field.status", "occurred", "edited"])
        #expect(options.sort?.map(\.order) == [.forward, .forward, .reverse])
        #expect(options.grouping == .column("type"))
        #expect(options.filter.isEmpty)
    }

    @Test func fieldsAndColumnsMapBothWays() {
        for column in Self.columns {
            guard let field = ViewDraft.field(of: column) else { continue }
            #expect(ViewDraft.columnID(of: field) == column.id)
        }
        #expect(ViewDraft.columnID(of: "backref[parent-of]") == "parent")
        #expect(ViewDraft.columnID(of: "properties.bad-key") == nil)
        #expect(ViewDraft.columnID(of: "edge[blocks]") == nil)
    }

    @Test func eachLayoutSavesTheOrderAndGroupingItShows() throws {
        // The table's own order and grouping, which the other layouts do not show, and a filter, which they all do.
        let sort = [ItemTableComparator(column: Self.statusColumn, order: .forward)]
        func draft(_ layout: ViewDraft.Layout) throws -> ViewDraft.Draft {
            try #require(Self.draft(Self.window(.allItems, sort: sort, grouping: Self.statusColumn, filters: ["field.status": ["todo"]], layout: layout)))
        }
        let byTitle = try draft(.list(ItemOrder(sort: .title, groupsByDate: true)))
        #expect(byTitle.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(byTitle.group == nil)
        #expect(byTitle.query.filter == #"properties.status eq "todo""#)
        #expect(byTitle.unkept.isEmpty)

        let byEdit = try draft(.list(ItemOrder(sort: .dateEdited, groupsByDate: true)))
        #expect(byEdit.sort == [LibraryViewSort(field: "updated_at", ascending: false)])
        // The list's sections by date are that date by day, which the view keeps.
        #expect(byEdit.group == LibraryViewGroup(field: "updated_at", bucket: .day))
        #expect(byEdit.unkept.isEmpty)
        let byCreated = try draft(.list(ItemOrder(sort: .dateCreated, groupsByDate: true)))
        #expect(byCreated.group == LibraryViewGroup(field: "created_at", bucket: .day))
        #expect(byCreated.unkept.isEmpty)
        #expect(try draft(.list(ItemOrder(sort: .dateCreated, groupsByDate: false))).sort
            == [LibraryViewSort(field: "created_at", ascending: false)])

        // The board's cards follow the sort the window shows them in, and its lanes keep the app's order of the words.
        let board = try draft(.board)
        #expect(board.group == LibraryViewGroup(field: "properties.status", order: ViewDraft.declaredOrder(of: Self.statusColumn)))
        #expect(board.sort == [LibraryViewSort(field: "properties.status", ascending: true)])
        let odd = try #require(Self.draft(Self.window(.allItems, grouping: Self.dueColumn, layout: .board)))
        #expect(odd.unkept == [.group(column: "Due")])

        let timeline = try draft(.timeline(key: "due_at", label: "Due"))
        #expect(timeline.group == LibraryViewGroup(field: "properties.due_at", bucket: .day))
        #expect(timeline.sort == [LibraryViewSort(field: "properties.due_at", ascending: true)])
    }

    // MARK: Filters

    @Test func filtersJoinAColumnsValuesByOrAndColumnsByAnd() {
        let one = Self.filter(nil, adding: ["field.status": ["todo", "done"]])
        #expect(one.filter == #"properties.status eq "done" OR properties.status eq "todo""#)
        #expect(one.unkept.isEmpty)

        let both = Self.filter(nil, adding: ["field.status": ["todo"], "field.done": ["false"]])
        #expect(both.filter == #"properties.status eq "todo" AND properties.done eq false"#)

        // Two columns of two values each would need both joiners.
        let mixed = Self.filter(nil, adding: ["field.status": ["todo", "done"], "field.done": ["false"]])
        #expect(mixed.filter == nil)
        #expect(mixed.unkept == [.mixedFilters])
    }

    @Test func filtersAddToTheViewsOwnWhereTheJoinerAgrees() {
        let added = ["field.status": Set(["todo"])]
        #expect(Self.filter(#"type eq "core.task""#, adding: added).filter
            == #"type eq "core.task" AND properties.status eq "todo""#)
        // A filter of ORs cannot take an AND, nor a filter of one condition two values by OR.
        let ors = #"tags contains "a" OR tags contains "b""#
        #expect(Self.filter(ors, adding: added) == (ors, [.mixedFilters]))
        #expect(Self.filter(#"type eq "core.task""#, adding: ["field.status": ["todo", "done"]]).unkept
            == [.mixedFilters])
    }

    @Test func emptyCellsAndParentsBecomeConditions() {
        let filter = Self.filter(nil, adding: ["field.status": [""], "parent": ["p1"]])
        #expect(filter.filter == #"properties.status not_exists AND backref[parent-of] eq "p1""#)
        #expect(Self.filter(nil, adding: ["parent": [""]]).filter == "backref[parent-of] not_exists")
    }

    @Test func valuesAreQuotedByTheCoreAndABackslashIsKept() throws {
        let quoted = Self.filter(nil, adding: ["field.status": [#"say "hi""#]])
        #expect(quoted.filter == #"properties.status eq "say \"hi\"""#)
        for value in [#"a\"#, #"C:\temp\"#, #"\""#, #"x\y"#] {
            let kept = Self.filter(nil, adding: ["field.status": [value]])
            #expect(kept.unkept.isEmpty, "\(value) was not kept")
            let text = try #require(kept.filter)
            let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: text))
            #expect(Self.shownFilters(ViewDraft.options(for: view, catalogue: Self.catalogue)) == ["field.status": [value]], "\(value) did not come back")
        }
        // A field Marfa cannot name has no condition it can express.
        #expect(Self.filter(nil, adding: ["field.due-date": ["c"]]).unkept == [.filter(column: "Due")])
    }

    @Test func aFilterIsMeasuredByTheCoreInCharactersNotUTF16Units() throws {
        // Each 🎉 is one character and two UTF-16 units: 1,100 of them fit in 2,048 characters and 2,100 do not.
        func filter(_ count: Int) -> (filter: String?, unkept: [ViewDraft.Unkept]) {
            Self.filter(nil, adding: ["field.status": [String(repeating: "🎉", count: count)]])
        }
        let fits = filter(1_100)
        #expect(fits.unkept.isEmpty)
        #expect(try #require(fits.filter).unicodeScalars.count <= 2_048)
        let over = filter(2_100)
        #expect(over.filter == nil)
        guard case .refused(let message)? = over.unkept.first else { Issue.record("not refused: \(over.unkept)"); return }
        #expect(!message.isEmpty)
    }

    @Test func moreConditionsThanTheCoreTakesAreToldWithItsMessage() {
        let values = Set((1...11).map { "v\($0)" })
        let filter = Self.filter(nil, adding: ["field.status": values])
        #expect(filter.filter == nil)
        #expect(filter.unkept == [.tooManyFilters])
        // Ten conditions are the most a filter holds.
        #expect(Self.filter(nil, adding: ["field.status": Set((1...10).map { "v\($0)" })]).unkept.isEmpty)
        // The view's own conditions count too.
        let held = (1...5).map { #"tags contains "t\#($0)""# }.joined(separator: " AND ")
        let beside = Self.filter(held, adding: ["field.status": ["a"], "field.done": ["true"]])
        #expect(beside.unkept.isEmpty)
        let over = Self.filter(held + " AND " + held, adding: ["field.status": ["a"]])
        #expect(over.unkept == [.tooManyFilters])
    }

    @Test func aSavedFilterTheCoreRefusesShowsNoFiltersAndIsNeverOverwritten() {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 3, query: LibraryViewQuery(types: [Self.task], filter: "properties.status eq"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(Self.shownFilters(seed).isEmpty)
        var options = seed
        options.filter = Self.state(["field.status": ["todo"]])
        let update = ViewDraft.change(Self.window(.view(view.id), filters: Self.shownFilters(options)), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change.query == nil, "a filter that could not be read is not replaced")
        guard case .refused(let message)? = update.unkept.first else { Issue.record("not refused: \(update.unkept)"); return }
        #expect(!message.isEmpty)
    }

    // MARK: Updating a view

    @Test func anUnchangedWindowDiffersFromNothing() {
        let view = LibraryView(id: ItemID("v"), title: "V", sort: [LibraryViewSort(field: "updated_at", ascending: false)])
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(!ViewDraft.differs(seed, timelineDate: nil, from: seed, seedTimelineDate: nil))
        var filtered = seed
        filtered.filter = Self.state(["field.status": ["todo"]])
        #expect(ViewDraft.differs(filtered, timelineDate: nil, from: seed, seedTimelineDate: nil))
        var regrouped = seed
        regrouped.grouping = .column("type")
        #expect(ViewDraft.differs(regrouped, timelineDate: nil, from: seed, seedTimelineDate: nil))
        var resorted = seed
        resorted.sort = nil
        #expect(ViewDraft.differs(resorted, timelineDate: nil, from: seed, seedTimelineDate: nil))
        // Folding a group is the window's own.
        var folded = seed
        folded.collapsed = ["done"]
        #expect(!ViewDraft.differs(folded, timelineDate: nil, from: seed, seedTimelineDate: nil))
    }

    @Test func removingAViewsGroupingNeverWritesAMonthGroup() {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 4, group: LibraryViewGroup(field: "type"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var ungrouped = seed
        ungrouped.grouping = .none
        var window = Self.window(.view(view.id), layout: .list(ItemOrder(sort: .dateEdited, groupsByDate: true)))
        window.dated = ViewDraft.Dated(sort: [ItemTableComparator(column: .edited, order: .reverse)], hasSections: true)
        let result = ViewDraft.change(
            window, options: ungrouped, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(result.change.group == .clear)
        #expect(result.unkept.isEmpty)
    }

    @Test func anUpdateNamesOnlyWhatTheWindowChanged() {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 4, query: LibraryViewQuery(types: [Self.task], filter: #"version gt 1"#),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "type"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)

        var grouped = seed
        grouped.grouping = .none
        let ungroup = ViewDraft.change(Self.window(.view(view.id), sort: seed.sort ?? []), options: grouped, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(ungroup.change == LibraryViewChange(group: .clear))

        var filtered = seed
        filtered.filter = Self.state(["field.status": ["todo"]])
        let filter = ViewDraft.change(
            Self.window(.view(view.id), filters: Self.shownFilters(filtered)), options: filtered, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(filter.change == LibraryViewChange(
            query: LibraryViewQuery(types: [Self.task], filter: #"version gt 1 AND properties.status eq "todo""#)))

        var resorted = seed
        resorted.sort = [ItemTableComparator(column: .title)]
        let sort = ViewDraft.change(Self.window(.view(view.id), sort: [ItemTableComparator(column: .title)]), options: resorted, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(sort.change == LibraryViewChange(sort: [LibraryViewSort(field: "title", ascending: true)]))
    }

    @Test func aViewOpensWithTheFiltersTheRowCanShow() {
        func state(_ filter: String) -> FilterState {
            ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: filter)), catalogue: Self.catalogue).filter
        }
        func clause(_ field: String, _ op: FilterOp, _ values: [String] = []) -> FilterClause { FilterClause(field: field, op: op, values: values) }
        #expect(state(#"properties.status eq "todo" AND properties.done eq false AND tags contains "x""#).clauses
            == [clause("field.status", .is, ["todo"]), clause("field.done", .is, ["false"]), clause("tags", .includes, ["x"])])
        #expect(state(#"properties.status not_exists AND backref[parent-of] eq "p1""#).clauses
            == [clause("field.status", .isEmpty), clause("parent", .is, ["p1"])])
        #expect(state(#"properties.status eq "say \"hi\"""#).clauses == [clause("field.status", .is, [#"say "hi""#])])
        // One field's values joined by OR are one chip; a row of different fields joined by OR is a row that matches any.
        #expect(state(#"properties.status eq "a" OR properties.status eq "b""#) == FilterState(clauses: [clause("field.status", .is, ["a", "b"])]))
        let any = state(#"properties.status eq "a" OR properties.done eq true"#)
        #expect(any.clauses == [clause("field.status", .is, ["a"]), clause("field.done", .is, ["true"])])
        #expect(any.matchesAny)
        // Two that must both hold are two chips, each a condition of its own.
        #expect(state(#"properties.status eq "a" AND properties.status eq "b""#).clauses
            == [clause("field.status", .is, ["a"]), clause("field.status", .is, ["b"])])
        // Is Not is a chip of its own, and the values left out of one field are one chip.
        #expect(state(#"properties.status neq "a""#).clauses == [clause("field.status", .isNot, ["a"])])
        #expect(state(#"properties.status neq "a" AND properties.status neq "b""#).clauses == [clause("field.status", .isNot, ["a", "b"])])
        #expect(state(#"properties.status neq "a" AND properties.status eq "b""#).clauses
            == [clause("field.status", .isNot, ["a"]), clause("field.status", .is, ["b"])])
        #expect(state(#"properties.status neq "a" OR properties.status neq "b""#).clauses
            == [clause("field.status", .isNot, ["a"]), clause("field.status", .isNot, ["b"])])
        // The empty cell, in or out.
        #expect(state("properties.status exists").clauses == [clause("field.status", .isSet)])
        // A condition no chip can say stays out of the row, for the view to keep.
        #expect(state(#"id eq "x" AND properties.status eq "todo""#).clauses == [clause("field.status", .is, ["todo"])])
        // Any shows only where every condition does.
        #expect(state(#"id eq "x" OR properties.status eq "todo""#).isEmpty)
    }

    private func negated(_ filter: String) -> Set<String> {
        Self.negated(ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: filter)), catalogue: Self.catalogue))
    }

    @Test func isNotValuesJoinByAndAndIsValuesByOr() throws {
        let not = Self.filter(nil, adding: ["field.status": ["todo", "done"]], negated: ["field.status"])
        #expect(not.filter == #"properties.status neq "done" AND properties.status neq "todo""#)
        #expect(not.unkept.isEmpty)
        let single = Self.filter(nil, adding: ["field.done": ["true"]], negated: ["field.done"])
        #expect(single.filter == "properties.done neq true")
        // Is Not on the empty cell asks that the property exist.
        #expect(Self.filter(nil, adding: ["field.status": [""]], negated: ["field.status"]).filter
            == "properties.status exists")
        // Is Not with several values beside Is with several would need both joiners.
        let mixed = Self.filter(
            nil, adding: ["field.status": ["a", "b"], "parent": ["p1", "p2"]], negated: ["field.status"])
        #expect(mixed.unkept == [.mixedFilters])
        // Written and read back, it is the same filter.
        let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: not.filter))
        let options = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(Self.shownFilters(options) == ["field.status": ["todo", "done"]])
        #expect(Self.negated(options) == ["field.status"])
    }

    // MARK: Types

    @Test func aTypesPlaceWithIncludeSubtypesOnSavesTheTypeWithItsSubtypes() throws {
        // Marfa lists a type with its subtypes, so the types alone hold what the window shows.
        let on = try #require(Self.draft(Self.window(.itemType("aic.ticket"), includesSubtypes: true)))
        #expect(on.query.types == [Self.ticket])
        #expect(on.query.filter == nil)
        #expect(on.unkept.isEmpty)
        // Filtered to one subtype, the window shows that subtype's items, which the types say.
        let sub = try #require(Self.draft(Self.window(.itemType("aic.ticket"), filters: ["type": ["aic.ticket.task"]], includesSubtypes: true)))
        #expect(sub.query.types == [Self.ticketTask])
        #expect(sub.query.filter == nil)
        // Filtered to the parent alone, the window shows the parent's own items, so it stays exact.
        let parent = try #require(Self.draft(Self.window(.itemType("aic.ticket"), filters: ["type": ["aic.ticket"]], includesSubtypes: true)))
        #expect(parent.query.filter == #"type eq "aic.ticket""#)
        // Off, the type's own items alone, as before.
        let off = try #require(Self.draft(Self.window(.itemType("aic.ticket"), includesSubtypes: false)))
        #expect(off.query.types == [Self.ticket])
        #expect(off.query.filter == #"type eq "aic.ticket""#)
    }

    @Test func aTypeFilterGoesIntoTheQueryTypes() throws {
        let window = Self.window(.allItems, filters: ["type": ["core.task"]])
        let draft = try #require(Self.draft(window))
        #expect(draft.query.types == [Self.task])
        #expect(draft.query.filter == nil)
        #expect(draft.unkept.isEmpty)
        // Several types are all of them.
        let several = try #require(Self.draft(Self.window(.allItems, filters: ["type": ["core.task", "core.note"]])))
        #expect(several.query.types == [TypeID("core.note"), Self.task])
    }

    @Test func aTypeWithSubtypesIsSavedAsAnExactTypeFilterBecauseMarfaListsItsSubtypesToo() throws {
        // Saving from the window with the Type filter on a type that has subtypes (#389).
        let draft = try #require(Self.draft(Self.window(.allItems, filters: ["type": ["aic.ticket"]])))
        #expect(draft.query.types.isEmpty)
        #expect(draft.query.filter == #"type eq "aic.ticket""#)
        #expect(draft.unkept.isEmpty)
        // A type the place does not list replaces the place's, so the saved view is not empty.
        let beside = try #require(Self.draft(Self.window(.itemType("core.task"), filters: ["type": ["core.note"]])))
        #expect(beside.query.types == [TypeID("core.note")])
        #expect(beside.query.filter == nil)
        #expect(beside.unkept.isEmpty)
        // With the list grouped by a column too, both are kept.
        let grouped = try #require(Self.draft(Self.window(.allItems, grouping: Self.statusColumn, filters: ["type": ["aic.ticket"]])))
        #expect(grouped.group == LibraryViewGroup(field: "properties.status", order: ViewDraft.declaredOrder(of: Self.statusColumn)))
        #expect(grouped.query.filter == #"type eq "aic.ticket""#)
        // Is Not is a condition.
        let not = try #require(Self.draft(Self.window(.allItems, filters: ["type": ["core.task"]], negated: ["type"])))
        #expect(not.query.filter == #"type neq "core.task""#)
    }

    @Test func aSubtypeChosenInATypesPlaceReplacesThePlacesOwnTypeTerms() throws {
        // A place of a type with subtypes saves its own items; the window filtered to a subtype shows that subtype's.
        let place = try #require(ViewDraft.query(for: .itemType("aic.ticket"), catalogue: Self.catalogue, views: []))
        #expect(place.filter == #"type eq "aic.ticket""#)
        let sub = try #require(Self.draft(Self.window(.itemType("aic.ticket"), filters: ["type": ["aic.ticket.task"]])))
        #expect(sub.query.types == [Self.ticketTask])
        #expect(sub.query.filter == nil)
        #expect(sub.unkept.isEmpty)
        // The parent alone is the place's own items already.
        let parent = try #require(Self.draft(Self.window(.itemType("aic.ticket"), filters: ["type": ["aic.ticket"]])))
        #expect(parent.query == place)
        // Another type with its own subtypes is exact, and the place's terms are replaced.
        let other = try #require(Self.draft(Self.window(.itemType("core.task"), filters: ["type": ["aic.ticket"]])))
        #expect(other.query.types == [Self.ticket])
        #expect(other.query.filter == #"type eq "aic.ticket""#)
        // The place's other conditions stay.
        let held = LibraryViewQuery(types: [Self.ticket], filter: #"type eq "aic.ticket" AND properties.status eq "done""#)
        let kept = ViewDraft.adding(Self.state(["type": ["aic.ticket.task"]]), to: held, targets: Self.targets, catalogue: Self.catalogue)
        #expect(kept.query.types == [Self.ticketTask])
        #expect(kept.query.filter == #"properties.status eq "done""#)
    }

    @Test func aParentTypeChosenAloneIsSavedExactWhereItsTypesAreListedWithSubtypes() throws {
        // Marfa lists a type with its subtypes, so the parent alone cannot be said by the types: it stays a filter.
        let listed = LibraryViewQuery(types: [Self.ticket])
        let added = ViewDraft.adding(Self.state(["type": ["aic.ticket"]]), to: listed, targets: Self.targets, catalogue: Self.catalogue)
        #expect(added.query.types == [Self.ticket])
        #expect(added.query.filter == #"type eq "aic.ticket""#)
        #expect(added.unkept.isEmpty)
        // So it is in a view that lists the type.
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, query: listed)
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.filter = Self.state(["type": ["aic.ticket"]])
        let change = ViewDraft.change(
            Self.window(.view(view.id), filters: ["type": ["aic.ticket"]]), options: options, seed: seed, seedTimelineDate: nil,
            seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(change.change.query?.types == [Self.ticket])
        #expect(change.change.query?.filter == #"type eq "aic.ticket""#)
        // A subtype chosen in a view that lists the parent keeps the view's types and narrows them exactly.
        let sub = ViewDraft.replacing(
            listed, with: Self.state(["type": ["aic.ticket.task"]]), targets: Self.targets,
            seededTypes: nil, catalogue: Self.catalogue)
        #expect(sub.query.types == [Self.ticket])
        #expect(sub.query.filter == #"type eq "aic.ticket.task""#)
    }

    /// The change a window makes to a saved view that lists `types` when it filters to `chosen`, and the view it makes.
    private static func filtering(_ types: [TypeID], to chosen: Set<String>, filter: String? = nil) -> (before: LibraryView, after: LibraryView?) {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, query: LibraryViewQuery(types: types, filter: filter))
        let seed = ViewDraft.options(for: view, catalogue: catalogue)
        var options = seed
        options.filter = Self.state(["type": chosen])
        let change = ViewDraft.change(
            window(.view(view.id), filters: ["type": chosen]), options: options, seed: seed, seedTimelineDate: nil,
            seededTypes: ViewDraft.seededTypes(of: view.query, catalogue: catalogue), view: view, catalogue: catalogue)
        guard let query = change.change.query else { return (view, nil) }
        return (view, LibraryView(id: view.id, title: view.title, version: 3, query: query))
    }

    @Test func anExistingViewFilteredToASubtypeKeepsItsTypesAndShowsTheFilterAsAChip() throws {
        let saved = try #require(Self.filtering([Self.ticket], to: ["aic.ticket.task"]).after)
        #expect(saved.query.types == [Self.ticket])
        #expect(saved.query.filter == #"type eq "aic.ticket.task""#)
        // Reopened, the filter is a chip.
        #expect(Self.shownFilters(ViewDraft.options(for: saved, catalogue: Self.catalogue)) == ["type": ["aic.ticket.task"]])
        // Removing the chip writes the view as it was; so does Undo, which seeds the saved view's own options.
        let removed = ViewDraft.replacing(
            saved.query, with: FilterState(), targets: Self.targets, seededTypes: nil, catalogue: Self.catalogue)
        #expect(removed.query == LibraryViewQuery(types: [Self.ticket]))
        #expect(Self.shownFilters(ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: removed.query), catalogue: Self.catalogue)).isEmpty)
    }

    @Test func anExistingViewOfSeveralTypesFilteredToOneKeepsAllOfThem() throws {
        let note = TypeID("core.note")
        let saved = try #require(Self.filtering([Self.task, note], to: ["core.task"]).after)
        #expect(saved.query.types == [Self.task, note])
        #expect(saved.query.filter == #"type eq "core.task""#)
        // Reopened it shows the one chip, not the two types, and removing it restores the view's own list.
        #expect(ViewDraft.seededTypes(of: saved.query, catalogue: Self.catalogue) == nil)
        #expect(Self.shownFilters(ViewDraft.options(for: saved, catalogue: Self.catalogue)) == ["type": ["core.task"]])
        let removed = ViewDraft.replacing(saved.query, with: FilterState(), targets: Self.targets, seededTypes: nil, catalogue: Self.catalogue)
        #expect(removed.query == LibraryViewQuery(types: [Self.task, note]))
        // Undo is the original query, whose types show as the seeded chip again.
        let original = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task, note]))
        #expect(Self.shownFilters(ViewDraft.options(for: original, catalogue: Self.catalogue)) == ["type": ["core.task", "core.note"]])
    }

    @Test func aTypeFilterOutsideAnExistingViewsTypesReplacesThem() throws {
        let saved = try #require(Self.filtering([Self.ticket], to: ["core.task"]).after)
        #expect(saved.query.types == [Self.task])
        #expect(saved.query.filter == nil)
    }

    @Test func aTypeFilterOfTwoTypesInItemsIsTheirTypes() throws {
        let plain = try #require(Self.draft(Self.window(.allItems, filters: ["type": ["core.task", "core.note"]])))
        #expect(plain.query.types == [TypeID("core.note"), Self.task])
        #expect(plain.query.filter == nil)
        // With a type that has subtypes, the types are exact conditions joined by or.
        let exact = try #require(Self.draft(Self.window(.allItems, filters: ["type": ["core.task", "aic.ticket"]])))
        #expect(exact.query.types.isEmpty)
        #expect(exact.query.filter == #"type eq "aic.ticket" OR type eq "core.task""#)
        #expect(exact.unkept.isEmpty)
    }

    @Test func aViewOfSeveralTypesOpensWithATypeFilter() {
        let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task, TypeID("core.note")]))
        #expect(Self.shownFilters(ViewDraft.options(for: view, catalogue: Self.catalogue)) == ["type": ["core.task", "core.note"]])
        // One type is the view's own place, and a type with subtypes cannot be told from its subtypes.
        #expect(Self.shownFilters(ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task])), catalogue: Self.catalogue)).isEmpty)
        let nested = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task, Self.ticket]))
        #expect(Self.shownFilters(ViewDraft.options(for: nested, catalogue: Self.catalogue)).isEmpty)
    }

    @Test func aViewOfSeveralTypesIsSavedAsItWasUntilTheTypeFilterChanges() throws {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, query: LibraryViewQuery(types: [Self.task, TypeID("core.note")]))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        func update(_ filters: [String: Set<String>]) -> (change: LibraryViewChange, unkept: [ViewDraft.Unkept]) {
            var options = seed
            options.filter = Self.state(filters)
            return ViewDraft.change(
                Self.window(.view(view.id), filters: filters), options: options, seed: seed, seedTimelineDate: nil,
                seededTypes: ViewDraft.seededTypes(of: view.query, catalogue: Self.catalogue), view: view, catalogue: Self.catalogue)
        }
        #expect(update(Self.shownFilters(seed)).change.query == nil)
        // Filtered to one, the view keeps its types and the filter is an exact-type condition.
        #expect(update(["type": ["core.task"]]).change.query?.types == [Self.task, TypeID("core.note")])
        #expect(update(["type": ["core.task"]]).change.query?.filter == #"type eq "core.task""#)
        #expect(update([:]).change.query?.types == [])
    }

    // MARK: Timeline date

    @Test func aChangedTimelineDateDiffersAndIsSavedAsTheDayGroup() {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, group: LibraryViewGroup(field: "properties.due_at", bucket: .day))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(ViewDraft.differs(seed, timelineDate: "starts_at", from: seed, seedTimelineDate: "due_at"))
        #expect(!ViewDraft.differs(seed, timelineDate: "due_at", from: seed, seedTimelineDate: "due_at"))
        let timeline = Self.window(.view(view.id), layout: .timeline(key: "starts_at", label: "Starts"), timelineDate: "starts_at")
        let update = ViewDraft.change(timeline, options: seed, seed: seed, seedTimelineDate: "due_at", seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change == LibraryViewChange(group: .set(LibraryViewGroup(field: "properties.starts_at", bucket: .day))))
    }

    @Test func aTimelineDateThatReplacesAnotherGroupingNamesTheGroupItReplaces() {
        // The view is grouped by status, which is not a day: a new date would replace it.
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, group: LibraryViewGroup(field: "properties.status"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        let timeline = Self.window(
            .view(view.id), grouping: Self.statusColumn, layout: .timeline(key: "starts_at", label: "Starts"), timelineDate: "starts_at")
        let update = ViewDraft.change(timeline, options: seed, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change.group == .set(LibraryViewGroup(field: "properties.starts_at", bucket: .day)))
        #expect(update.unkept == [.group(column: "Status")])
        // A group by month is not a day either, and no column of the window shows it.
        let monthly = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "properties.due_at", bucket: .month))
        let months = ViewDraft.change(timeline, options: seed, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: monthly, catalogue: Self.catalogue)
        #expect(months.unkept == [.group(column: "Group")])
        // A day group moving to another date loses nothing.
        let dated = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "properties.due_at", bucket: .day))
        let moved = ViewDraft.change(timeline, options: seed, seed: seed, seedTimelineDate: "due_at", seededTypes: nil, view: dated, catalogue: Self.catalogue)
        #expect(moved.unkept.isEmpty)
        // A view with no group loses nothing either.
        let plain = LibraryView(id: ItemID("v"), title: "V")
        let none = ViewDraft.change(timeline, options: ItemTableOptions(), seed: ItemTableOptions(), seedTimelineDate: nil, seededTypes: nil, view: plain, catalogue: Self.catalogue)
        #expect(none.unkept.isEmpty)
    }

    @Test func aCatalogueChangeWhileEditingNeverWidensAViewsTypes() {
        // Ticket has a subtype when the view opens, so its types are not shown as a Type filter...
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 2, query: LibraryViewQuery(types: [Self.ticket, TypeID("core.note")]))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(Self.shownFilters(seed).isEmpty)
        // ...and the subtype goes away from the catalogue before the filter on Status is saved.
        let later = Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [Self.status, Self.done], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: Self.ticket, label: "Ticket", fields: [], titleField: "title", bodyField: "body", parent: nil),
        ])
        var options = seed
        options.filter = Self.state(["field.status": ["todo"]])
        let update = ViewDraft.change(
            Self.window(.view(view.id), filters: Self.shownFilters(options)), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view,
            catalogue: later)
        #expect((update.change.query?.types ?? view.query.types) == view.query.types)
    }

    @Test func anUpdateReplacesTheFiltersTheWindowShows() throws {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 2,
            query: LibraryViewQuery(types: [Self.task], filter: #"id eq "x" AND properties.status eq "todo""#))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(Self.shownFilters(seed) == ["field.status": ["todo"]])
        func update(_ filters: [String: Set<String>]) -> (change: LibraryViewChange, unkept: [ViewDraft.Unkept]) {
            var options = seed
            options.filter = Self.state(filters)
            return ViewDraft.change(Self.window(.view(view.id), filters: filters), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        }

        // Removing the filter in the window removes it from the view; what the window cannot show stays.
        let removed = update([:])
        #expect(removed.change.query?.filter == #"id eq "x""#)

        let changed = update(["field.status": ["done"]])
        #expect(changed.change.query?.filter == #"id eq "x" AND properties.status eq "done""#)

        // A window filter the view cannot hold leaves the view's filter whole, rather than dropping what it showed.
        let mixed = update(["field.status": ["todo", "done"]])
        #expect(mixed.change.query == nil)
        #expect(mixed.unkept == [.mixedFilters])

        // An unchanged window sends no filter.
        #expect(update(Self.shownFilters(seed)).change.query == nil)
    }

    @Test func aFilterOnAColumnTheTableLacksStaysAsItIs() {
        let view = LibraryView(
            id: ItemID("v"), title: "V",
            query: LibraryViewQuery(filter: #"properties.owner eq "ann" AND properties.status eq "todo""#))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.filter = Self.state([:])
        let window = ViewDraft.Window(place: .view(view.id), columns: Self.columns, sort: [], grouping: nil, filter: FilterState(), targets: Self.targets)
        let update = ViewDraft.change(window, options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change.query?.filter == #"properties.owner eq "ann""#)
    }

    // MARK: A window's changed filters, read at once

    private static func preview(_ query: LibraryViewQuery) -> LibraryViewQuery? {
        ViewDraft.previewQuery(
            of: query, seededTypes: ViewDraft.seededTypes(of: query, catalogue: catalogue), catalogue: catalogue)
    }

    @Test func aPreviewTakesOutTheConditionsTheWindowShowsAsChips() {
        let states: Set<ItemState> = [.active]
        let base = LibraryViewQuery(types: [Self.task], tier: .library, states: states, filter: #"properties.status neq "done""#)
        // The one type stays a type: it is the view's place, not a chip.
        #expect(Self.preview(base) == LibraryViewQuery(types: [Self.task], tier: .library, states: states, filter: nil))
        let both = LibraryViewQuery(states: states, filter: #"properties.status neq "done" AND properties.status neq "todo""#)
        #expect(Self.preview(both) == LibraryViewQuery(states: states, filter: nil))
        // A bare yes/no is the Yes/No column's chip.
        #expect(Self.preview(LibraryViewQuery(filter: "properties.done eq true"))?.filter == nil)
    }

    @Test func aPreviewKeepsWhatTheWindowCannotShow() {
        let kept = Self.preview(LibraryViewQuery(filter: #"id eq "x" AND properties.status eq "todo""#))
        #expect(kept?.filter == #"id eq "x""#)
        // A field no type declares has no column, so its condition stays in the read.
        #expect(Self.preview(LibraryViewQuery(filter: #"properties.owner eq "ann""#))?.filter == #"properties.owner eq "ann""#)
        // Several values of one column joined by OR are one chip.
        #expect(Self.preview(LibraryViewQuery(filter: #"properties.status eq "a" OR properties.status eq "b""#))?.filter == nil)
        // Conditions joined by OR show only where each does, so one the row cannot show keeps the whole filter.
        let mixed = #"id eq "x" OR properties.status eq "a""#
        #expect(Self.preview(LibraryViewQuery(filter: mixed))?.filter == mixed)
    }

    @Test func aPreviewOfSeveralTypesDropsThemForTheTypeChip() {
        let query = LibraryViewQuery(types: [Self.task, TypeID("core.note")], filter: #"properties.status eq "todo""#)
        #expect(ViewDraft.seededTypes(of: query, catalogue: Self.catalogue) != nil)
        #expect(Self.preview(query)?.types == [])
        // A type with subtypes cannot be told from them, so the types stay in the read.
        let nested = LibraryViewQuery(types: [Self.task, Self.ticket])
        #expect(Self.preview(nested)?.types == [Self.task, Self.ticket])
    }

    @Test func aFilterTheCoreRefusesHasNoPreview() {
        #expect(Self.preview(LibraryViewQuery(filter: "not a filter ((")) == nil)
    }
}
