import Foundation
import Testing
@testable import MAPP

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
    private static let columns = [ItemTableColumn.title, statusColumn, doneColumn, .parent, .type, .collection, .edited]

    private static func window(
        _ place: SidebarItem, sort: [ItemTableComparator] = [], grouping: ItemTableColumn? = nil,
        filters: [String: Set<String>] = [:], search: String? = nil
    ) -> ViewDraft.Window {
        ViewDraft.Window(place: place, columns: columns, sort: sort, grouping: grouping, filters: filters, search: search)
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
        #expect(query(.allNotes) == LibraryViewQuery(states: active))
        #expect(query(.inbox) == LibraryViewQuery(tier: .feed, states: active))
        #expect(query(.favorites) == LibraryViewQuery(states: active, filter: #"tags contains "favorite""#))
        #expect(query(.files) == LibraryViewQuery(types: [TypeID.file], states: active))
        #expect(query(.source("mail")) == LibraryViewQuery(states: active, filter: #"source eq "mail""#))
        // A type's place holds its own items, and Marfa takes a type with its subtypes, so a type with any is narrowed.
        #expect(query(.itemType("core.task")) == LibraryViewQuery(types: [Self.task], states: active))
        #expect(query(.itemType("aic.ticket")) == LibraryViewQuery(types: [Self.ticket], states: active, filter: #"type eq "aic.ticket""#))
    }

    @Test func placesNoViewCanStandForOfferNone() {
        for place: SidebarItem in [.recents, .recentlyDeleted, .sources, .collections, .favoriteItem(ItemID("a")), .collection(ItemID("a"))] {
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
            .allNotes,
            sort: [
                ItemTableComparator(column: Self.statusColumn, order: .forward),
                ItemTableComparator(column: .collection, order: .forward),
                ItemTableComparator(column: .edited, order: .reverse),
            ],
            grouping: Self.statusColumn, search: "plans")
        let draft = try #require(Self.draft(window))
        #expect(draft.sort == [
            LibraryViewSort(field: "properties.status", ascending: true),
            LibraryViewSort(field: "updated_at", ascending: false),
        ])
        #expect(draft.group == LibraryViewGroup(field: "properties.status"))
        #expect(draft.unkept == [.search("plans"), .sort(column: "Collection")])
    }

    @Test func groupingByParentIsKeptAndByCollectionIsNot() {
        #expect(ViewDraft.group(.parent).group == LibraryViewGroup(field: "backref[parent-of]"))
        #expect(ViewDraft.group(.collection) == (nil, [.group(column: "Collection")]))
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
        let options = ViewDraft.options(for: view)
        // A field the table has no column for, here `occurred_at`, is left out of the order.
        #expect(options.sort?.map(\.column.id) == ["field.status", "edited"])
        #expect(options.sort?.map(\.order) == [.forward, .reverse])
        #expect(options.grouping == .column("type"))
        #expect(options.filters.isEmpty)
    }

    @Test func aViewWithoutGroupingOrSortOpensUngroupedInTheTablesOwnOrder() {
        let plain = ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V"))
        #expect(plain.grouping == .none)
        #expect(plain.sort == nil)
        // The table groups no dates by month, so a bucketed grouping opens ungrouped.
        let monthly = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "created_at", bucket: .month))
        #expect(ViewDraft.options(for: monthly).grouping == .none)
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

    // MARK: Filters

    @Test func filtersJoinAColumnsValuesByOrAndColumnsByAnd() {
        let one = ViewDraft.filter(nil, adding: ["field.status": ["todo", "done"]], columns: Self.columns)
        #expect(one.filter == #"properties.status eq "done" OR properties.status eq "todo""#)
        #expect(one.unkept.isEmpty)

        let both = ViewDraft.filter(nil, adding: ["field.status": ["todo"], "field.done": ["false"]], columns: Self.columns)
        #expect(both.filter == #"properties.status eq "todo" AND properties.done eq false"#)

        // Two columns of two values each would need both joiners.
        let mixed = ViewDraft.filter(nil, adding: ["field.status": ["todo", "done"], "field.done": ["false"]], columns: Self.columns)
        #expect(mixed.filter == nil)
        #expect(mixed.unkept == [.mixedFilters])
    }

    @Test func filtersAddToTheViewsOwnWhereTheJoinerAgrees() {
        let added = ["field.status": Set(["todo"])]
        #expect(ViewDraft.filter(#"type eq "core.task""#, adding: added, columns: Self.columns).filter
            == #"type eq "core.task" AND properties.status eq "todo""#)
        // A filter of ORs cannot take an AND, nor a filter of one condition two values by OR.
        let ors = #"tags contains "a" OR tags contains "b""#
        #expect(ViewDraft.filter(ors, adding: added, columns: Self.columns) == (ors, [.mixedFilters]))
        #expect(ViewDraft.filter(#"type eq "core.task""#, adding: ["field.status": ["todo", "done"]], columns: Self.columns).unkept
            == [.mixedFilters])
    }

    @Test func emptyCellsParentsAndTypesBecomeConditions() {
        let filter = ViewDraft.filter(
            nil, adding: ["field.status": [""], "parent": ["p1"], "type": ["core.task"]], columns: Self.columns)
        #expect(filter.filter == #"properties.status not_exists AND backref[parent-of] eq "p1" AND type eq "core.task""#)
        #expect(ViewDraft.filter(nil, adding: ["parent": [""]], columns: Self.columns).filter == "backref[parent-of] not_exists")
    }

    @Test func valuesAreQuotedAndABackslashIsNotKept() {
        #expect(ViewDraft.filter(nil, adding: ["field.status": [#"say "hi""#]], columns: Self.columns).filter
            == #"properties.status eq "say \"hi\"""#)
        let slash = ViewDraft.filter(nil, adding: ["field.status": [#"a\"#]], columns: Self.columns)
        #expect(slash == (nil, [.filter(column: "Status")]))
        // A collection has no condition Marfa can express.
        #expect(ViewDraft.filter(nil, adding: ["collection": ["c"]], columns: Self.columns).unkept == [.filter(column: "Collection")])
    }

    @Test func moreThanTenConditionsAreNotKept() {
        let values = Set((1...11).map { "v\($0)" })
        let filter = ViewDraft.filter(nil, adding: ["field.status": values], columns: Self.columns)
        #expect(filter == (nil, [.tooManyFilters]))
    }

    @Test func aFiltersShapeIsReadOutsideItsQuotes() {
        #expect(ViewDraft.shape(of: "") == ViewDraft.Shape(conditions: 0, joiner: nil))
        #expect(ViewDraft.shape(of: #"title contains "A AND B""#) == ViewDraft.Shape(conditions: 1, joiner: nil))
        #expect(ViewDraft.shape(of: #"title eq "x \" OR y" OR tags exists"#) == ViewDraft.Shape(conditions: 2, joiner: "OR"))
        #expect(ViewDraft.shape(of: "a exists AND b exists AND c exists") == ViewDraft.Shape(conditions: 3, joiner: "AND"))
    }

    // MARK: Updating a view

    @Test func anUnchangedWindowDiffersFromNothing() {
        let view = LibraryView(id: ItemID("v"), title: "V", sort: [LibraryViewSort(field: "updated_at", ascending: false)])
        let seed = ViewDraft.options(for: view)
        #expect(!ViewDraft.differs(seed, from: seed))
        var filtered = seed
        filtered.filters = ["field.status": ["todo"]]
        #expect(ViewDraft.differs(filtered, from: seed))
        var regrouped = seed
        regrouped.grouping = .column("type")
        #expect(ViewDraft.differs(regrouped, from: seed))
        var resorted = seed
        resorted.sort = nil
        #expect(ViewDraft.differs(resorted, from: seed))
        // Folding a group is the window's own.
        var folded = seed
        folded.collapsed = ["done"]
        #expect(!ViewDraft.differs(folded, from: seed))
    }

    @Test func anUpdateNamesOnlyWhatTheWindowChanged() {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 4, query: LibraryViewQuery(types: [Self.task], filter: #"tags exists"#),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "type"))
        let seed = ViewDraft.options(for: view)

        var grouped = seed
        grouped.grouping = .none
        let ungroup = ViewDraft.change(Self.window(.view(view.id), sort: seed.sort ?? []), options: grouped, seed: seed, view: view)
        #expect(ungroup.change == LibraryViewChange(group: .clear))

        var filtered = seed
        filtered.filters = ["field.status": ["todo"]]
        let filter = ViewDraft.change(
            Self.window(.view(view.id), filters: filtered.filters), options: filtered, seed: seed, view: view)
        #expect(filter.change == LibraryViewChange(
            query: LibraryViewQuery(types: [Self.task], filter: #"tags exists AND properties.status eq "todo""#)))

        var resorted = seed
        resorted.sort = [ItemTableComparator(column: .title)]
        let sort = ViewDraft.change(Self.window(.view(view.id), sort: [ItemTableComparator(column: .title)]), options: resorted, seed: seed, view: view)
        #expect(sort.change == LibraryViewChange(sort: [LibraryViewSort(field: "title", ascending: true)]))
    }
}
