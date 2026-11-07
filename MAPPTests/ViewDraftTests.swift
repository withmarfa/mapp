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
    /// A field Marfa cannot name, so a view cannot sort, group or filter by it.
    private static let dueColumn = ItemTableColumn(
        id: "field.due-date", label: "Due", content: .field(ItemTypeInfo.Field(key: "due-date", label: "Due", kind: .text, declaredBy: task)),
        style: .text)
    private static let columns = [ItemTableColumn.title, statusColumn, doneColumn, .parent, .type, dueColumn, .edited]

    private static func window(
        _ place: SidebarItem, sort: [ItemTableComparator] = [], grouping: ItemTableColumn? = nil,
        filters: [String: Set<String>] = [:], negated: Set<String> = [], search: String? = nil, layout: ViewDraft.Layout = .table,
        timelineDate: String? = nil
    ) -> ViewDraft.Window {
        ViewDraft.Window(
            place: place, columns: columns, sort: sort, grouping: grouping, filters: filters, negated: negated, search: search,
            layout: layout, timelineDate: timelineDate)
    }

    /// A filter added to `base` as a place's filter, through the same call a new view's draft makes.
    private static func filter(
        _ base: String?, adding filters: [String: Set<String>], negated: Set<String> = [], columns: [ItemTableColumn]
    ) -> (filter: String?, unkept: [ViewDraft.Unkept]) {
        let choices = ItemTableOptions(filters: filters, negated: negated).filterChoices
        let result = ViewDraft.adding(choices, to: LibraryViewQuery(filter: base), columns: columns, catalogue: catalogue)
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
        #expect(query(.allNotes) == LibraryViewQuery(states: active))
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
        for place: SidebarItem in [.recents, .recentlyDeleted, .sources, .collections, .favoriteItem(ItemID("a"))] {
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
                ItemTableComparator(column: Self.dueColumn, order: .forward),
                ItemTableComparator(column: .edited, order: .reverse),
            ],
            grouping: Self.statusColumn, search: "plans")
        let draft = try #require(Self.draft(window))
        #expect(draft.sort == [
            LibraryViewSort(field: "properties.status", ascending: true),
            LibraryViewSort(field: "updated_at", ascending: false),
        ])
        #expect(draft.group == LibraryViewGroup(field: "properties.status"))
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
        // A field the table has no column for, here `occurred_at`, is left out of the order.
        #expect(options.sort?.map(\.column.id) == ["field.status", "edited"])
        #expect(options.sort?.map(\.order) == [.forward, .reverse])
        #expect(options.grouping == .column("type"))
        #expect(options.filters.isEmpty)
    }

    @Test func aViewWithoutGroupingOrSortOpensUngroupedInTheTablesOwnOrder() {
        let plain = ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V"), catalogue: Self.catalogue)
        #expect(plain.grouping == .none)
        #expect(plain.sort == nil)
        // The table groups no dates by month, so a bucketed grouping opens ungrouped.
        let monthly = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "created_at", bucket: .month))
        #expect(ViewDraft.options(for: monthly, catalogue: Self.catalogue).grouping == .none)
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
            try #require(Self.draft(Self.window(.allNotes, sort: sort, grouping: Self.statusColumn, filters: ["field.status": ["todo"]], layout: layout)))
        }
        let byTitle = try draft(.list(NoteOrder(sort: .title, groupsByDate: true)))
        #expect(byTitle.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(byTitle.group == nil)
        #expect(byTitle.query.filter == #"properties.status eq "todo""#)
        #expect(byTitle.unkept.isEmpty)

        let byEdit = try draft(.list(NoteOrder(sort: .dateEdited, groupsByDate: true)))
        #expect(byEdit.sort == [LibraryViewSort(field: "updated_at", ascending: false)])
        #expect(byEdit.unkept == [.dateSections])
        #expect(try draft(.list(NoteOrder(sort: .dateCreated, groupsByDate: false))).sort
            == [LibraryViewSort(field: "created_at", ascending: false)])

        let board = try draft(.board(key: "status", label: "Status"))
        #expect(board.group == LibraryViewGroup(field: "properties.status"))
        #expect(board.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(try draft(.board(key: "due-date", label: "Due")).unkept == [.group(column: "Due")])

        let timeline = try draft(.timeline(key: "due_at", label: "Due"))
        #expect(timeline.group == LibraryViewGroup(field: "properties.due_at", bucket: .day))
        #expect(timeline.sort == [LibraryViewSort(field: "properties.due_at", ascending: true)])
    }

    // MARK: Filters

    @Test func filtersJoinAColumnsValuesByOrAndColumnsByAnd() {
        let one = Self.filter(nil, adding: ["field.status": ["todo", "done"]], columns: Self.columns)
        #expect(one.filter == #"properties.status eq "done" OR properties.status eq "todo""#)
        #expect(one.unkept.isEmpty)

        let both = Self.filter(nil, adding: ["field.status": ["todo"], "field.done": ["false"]], columns: Self.columns)
        #expect(both.filter == #"properties.status eq "todo" AND properties.done eq false"#)

        // Two columns of two values each would need both joiners.
        let mixed = Self.filter(nil, adding: ["field.status": ["todo", "done"], "field.done": ["false"]], columns: Self.columns)
        #expect(mixed.filter == nil)
        #expect(mixed.unkept == [.mixedFilters])
    }

    @Test func filtersAddToTheViewsOwnWhereTheJoinerAgrees() {
        let added = ["field.status": Set(["todo"])]
        #expect(Self.filter(#"type eq "core.task""#, adding: added, columns: Self.columns).filter
            == #"type eq "core.task" AND properties.status eq "todo""#)
        // A filter of ORs cannot take an AND, nor a filter of one condition two values by OR.
        let ors = #"tags contains "a" OR tags contains "b""#
        #expect(Self.filter(ors, adding: added, columns: Self.columns) == (ors, [.mixedFilters]))
        #expect(Self.filter(#"type eq "core.task""#, adding: ["field.status": ["todo", "done"]], columns: Self.columns).unkept
            == [.mixedFilters])
    }

    @Test func emptyCellsAndParentsBecomeConditions() {
        let filter = Self.filter(nil, adding: ["field.status": [""], "parent": ["p1"]], columns: Self.columns)
        #expect(filter.filter == #"properties.status not_exists AND backref[parent-of] eq "p1""#)
        #expect(Self.filter(nil, adding: ["parent": [""]], columns: Self.columns).filter == "backref[parent-of] not_exists")
    }

    @Test func valuesAreQuotedByTheCoreAndABackslashIsKept() throws {
        let quoted = Self.filter(nil, adding: ["field.status": [#"say "hi""#]], columns: Self.columns)
        #expect(quoted.filter == #"properties.status eq "say \"hi\"""#)
        for value in [#"a\"#, #"C:\temp\"#, #"\""#, #"x\y"#] {
            let kept = Self.filter(nil, adding: ["field.status": [value]], columns: Self.columns)
            #expect(kept.unkept.isEmpty, "\(value) was not kept")
            let text = try #require(kept.filter)
            let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: text))
            #expect(ViewDraft.options(for: view, catalogue: Self.catalogue).filters == ["field.status": [value]], "\(value) did not come back")
        }
        // A field Marfa cannot name has no condition it can express.
        #expect(Self.filter(nil, adding: ["field.due-date": ["c"]], columns: Self.columns).unkept == [.filter(column: "Due")])
    }

    @Test func aFilterIsMeasuredByTheCoreInUTF16UnitsNotCharacters() throws {
        // Each 🎉 is one character and two UTF-16 units: 1,000 of them fit in 2,048 units and 1,100 do not.
        func filter(_ count: Int) -> (filter: String?, unkept: [ViewDraft.Unkept]) {
            Self.filter(nil, adding: ["field.status": [String(repeating: "🎉", count: count)]], columns: Self.columns)
        }
        let fits = filter(1_000)
        #expect(fits.unkept.isEmpty)
        #expect(try #require(fits.filter).utf16.count <= 2_048)
        let over = filter(1_100)
        #expect(over.filter == nil)
        guard case .refused(let message)? = over.unkept.first else { Issue.record("not refused: \(over.unkept)"); return }
        #expect(!message.isEmpty)
    }

    @Test func moreConditionsThanTheCoreTakesAreToldWithItsMessage() {
        let values = Set((1...11).map { "v\($0)" })
        let filter = Self.filter(nil, adding: ["field.status": values], columns: Self.columns)
        #expect(filter.filter == nil)
        #expect(filter.unkept == [.tooManyFilters])
        // Ten conditions are the most a filter holds.
        #expect(Self.filter(nil, adding: ["field.status": Set((1...10).map { "v\($0)" })], columns: Self.columns).unkept.isEmpty)
        // The view's own conditions count too.
        let held = (1...5).map { #"tags contains "t\#($0)""# }.joined(separator: " AND ")
        let beside = Self.filter(held, adding: ["field.status": ["a"], "field.done": ["true"]], columns: Self.columns)
        #expect(beside.unkept.isEmpty)
        let over = Self.filter(held + " AND " + held, adding: ["field.status": ["a"]], columns: Self.columns)
        #expect(over.unkept == [.tooManyFilters])
    }

    @Test func aSavedFilterTheCoreRefusesShowsNoFiltersAndIsNeverOverwritten() {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 3, query: LibraryViewQuery(types: [Self.task], filter: "properties.status eq"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(seed.filters.isEmpty)
        var options = seed
        options.filters = ["field.status": ["todo"]]
        let update = ViewDraft.change(Self.window(.view(view.id), filters: options.filters), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
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
        filtered.filters = ["field.status": ["todo"]]
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

    @Test func anUpdateNamesOnlyWhatTheWindowChanged() {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 4, query: LibraryViewQuery(types: [Self.task], filter: #"tags exists"#),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "type"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)

        var grouped = seed
        grouped.grouping = .none
        let ungroup = ViewDraft.change(Self.window(.view(view.id), sort: seed.sort ?? []), options: grouped, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(ungroup.change == LibraryViewChange(group: .clear))

        var filtered = seed
        filtered.filters = ["field.status": ["todo"]]
        let filter = ViewDraft.change(
            Self.window(.view(view.id), filters: filtered.filters), options: filtered, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(filter.change == LibraryViewChange(
            query: LibraryViewQuery(types: [Self.task], filter: #"tags exists AND properties.status eq "todo""#)))

        var resorted = seed
        resorted.sort = [ItemTableComparator(column: .title)]
        let sort = ViewDraft.change(Self.window(.view(view.id), sort: [ItemTableComparator(column: .title)]), options: resorted, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(sort.change == LibraryViewChange(sort: [LibraryViewSort(field: "title", ascending: true)]))
    }

    @Test func aViewOpensWithTheFiltersTheTableCanShow() {
        func filters(_ filter: String) -> [String: Set<String>] {
            ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: filter)), catalogue: Self.catalogue).filters
        }
        #expect(filters(#"properties.status eq "todo" AND properties.done eq false AND tags contains "x""#)
            == ["field.status": ["todo"], "field.done": ["false"]])
        #expect(filters(#"properties.status not_exists AND backref[parent-of] eq "p1""#) == ["field.status": [""], "parent": ["p1"]])
        #expect(filters(#"properties.status eq "say \"hi\"""#) == ["field.status": [#"say "hi""#]])
        // One column's values joined by OR is what the table shows; ORs across columns it cannot show.
        #expect(filters(#"properties.status eq "a" OR properties.status eq "b""#) == ["field.status": ["a", "b"]])
        #expect(filters(#"properties.status eq "a" OR properties.done eq true"#).isEmpty)
        // The table joins a column's values by OR, so two that must both hold are not shown.
        #expect(filters(#"properties.status eq "a" AND properties.status eq "b""#).isEmpty)
        // Is Not is a filter of the column's, kept apart from Is.
        #expect(filters(#"properties.status neq "a""#) == ["field.status": ["a"]])
        #expect(negated(#"properties.status neq "a""#) == ["field.status"])
        #expect(negated(#"properties.status neq "a" AND properties.status neq "b""#) == ["field.status"])
        #expect(negated(#"properties.status eq "a""#).isEmpty)
        #expect(filters(#"properties.status neq "a" AND properties.status neq "b""#) == ["field.status": ["a", "b"]])
        // A mixture of Is and Is Not on one column, and Is Not values joined by OR, are not the table's.
        #expect(filters(#"properties.status neq "a" AND properties.status eq "b""#).isEmpty)
        #expect(filters(#"properties.status neq "a" OR properties.status neq "b""#).isEmpty)
        // The empty cell, excluded.
        #expect(filters(#"properties.status exists"#) == ["field.status": [""]])
        #expect(negated(#"properties.status exists"#) == ["field.status"])
    }

    private func negated(_ filter: String) -> Set<String> {
        ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: filter)), catalogue: Self.catalogue).negated
    }

    @Test func isNotValuesJoinByAndAndIsValuesByOr() throws {
        let not = Self.filter(nil, adding: ["field.status": ["todo", "done"]], negated: ["field.status"], columns: Self.columns)
        #expect(not.filter == #"properties.status neq "done" AND properties.status neq "todo""#)
        #expect(not.unkept.isEmpty)
        let single = Self.filter(nil, adding: ["field.done": ["true"]], negated: ["field.done"], columns: Self.columns)
        #expect(single.filter == "properties.done neq true")
        // Is Not on the empty cell asks that the property exist.
        #expect(Self.filter(nil, adding: ["field.status": [""]], negated: ["field.status"], columns: Self.columns).filter
            == "properties.status exists")
        // Is Not with several values beside Is with several would need both joiners.
        let mixed = Self.filter(
            nil, adding: ["field.status": ["a", "b"], "parent": ["p1", "p2"]], negated: ["field.status"], columns: Self.columns)
        #expect(mixed.unkept == [.mixedFilters])
        // Written and read back, it is the same filter.
        let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(filter: try #require(not.filter)))
        let options = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(options.filters == ["field.status": ["todo", "done"]])
        #expect(options.negated == ["field.status"])
    }

    // MARK: Types

    @Test func aTypeFilterGoesIntoTheQueryTypes() throws {
        let window = Self.window(.allNotes, filters: ["type": ["core.task"]])
        let draft = try #require(Self.draft(window))
        #expect(draft.query.types == [Self.task])
        #expect(draft.query.filter == nil)
        #expect(draft.unkept.isEmpty)
        // Several types are all of them.
        let several = try #require(Self.draft(Self.window(.allNotes, filters: ["type": ["core.task", "core.note"]])))
        #expect(several.query.types == [TypeID("core.note"), Self.task])
    }

    @Test func aTypeWithSubtypesIsNotKeptAsAFilterBecauseMarfaListsItsSubtypesToo() throws {
        let draft = try #require(Self.draft(Self.window(.allNotes, filters: ["type": ["aic.ticket"]])))
        #expect(draft.query.types.isEmpty)
        #expect(draft.unkept == [.filter(column: "Type")])
        // Nor beside the types the place already lists.
        let beside = try #require(Self.draft(Self.window(.itemType("core.task"), filters: ["type": ["core.note"]])))
        #expect(beside.query.types == [Self.task])
        #expect(beside.unkept == [.filter(column: "Type")])
        // Is Not is a condition.
        let not = try #require(Self.draft(Self.window(.allNotes, filters: ["type": ["core.task"]], negated: ["type"])))
        #expect(not.query.filter == #"type neq "core.task""#)
    }

    @Test func aViewOfSeveralTypesOpensWithATypeFilter() {
        let view = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task, TypeID("core.note")]))
        #expect(ViewDraft.options(for: view, catalogue: Self.catalogue).filters == ["type": ["core.task", "core.note"]])
        // One type is the view's own place, and a type with subtypes cannot be told from its subtypes.
        #expect(ViewDraft.options(for: LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task])), catalogue: Self.catalogue).filters.isEmpty)
        let nested = LibraryView(id: ItemID("v"), title: "V", query: LibraryViewQuery(types: [Self.task, Self.ticket]))
        #expect(ViewDraft.options(for: nested, catalogue: Self.catalogue).filters.isEmpty)
    }

    @Test func aViewOfSeveralTypesIsSavedAsItWasUntilTheTypeFilterChanges() throws {
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, query: LibraryViewQuery(types: [Self.task, TypeID("core.note")]))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        func update(_ filters: [String: Set<String>]) -> (change: LibraryViewChange, unkept: [ViewDraft.Unkept], unchanged: [String]) {
            var options = seed
            options.filters = filters
            return ViewDraft.change(
                Self.window(.view(view.id), filters: filters), options: options, seed: seed, seedTimelineDate: nil,
                seededTypes: ViewDraft.seededTypes(of: view.query, catalogue: Self.catalogue), view: view, catalogue: Self.catalogue)
        }
        #expect(update(seed.filters).change.query == nil)
        #expect(update(["type": ["core.task"]]).change.query?.types == [Self.task])
        #expect(update([:]).change.query?.types == [])
    }

    // MARK: Timeline date

    @Test func aViewsDayGroupIsTheTimelinesDate() {
        let view = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "properties.due_at", bucket: .day))
        #expect(ViewDraft.timelineDate(of: view) == "due_at")
        #expect(ViewDraft.timelineDate(of: LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "properties.due_at"))) == nil)
        #expect(ViewDraft.timelineDate(of: LibraryView(id: ItemID("v"), title: "V")) == nil)
    }

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
        #expect(seed.filters.isEmpty)
        // ...and the subtype goes away from the catalogue before the filter on Status is saved.
        let later = Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [Self.status, Self.done], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: Self.ticket, label: "Ticket", fields: [], titleField: "title", bodyField: "body", parent: nil),
        ])
        var options = seed
        options.filters = ["field.status": ["todo"]]
        let update = ViewDraft.change(
            Self.window(.view(view.id), filters: options.filters), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view,
            catalogue: later)
        #expect((update.change.query?.types ?? view.query.types) == view.query.types)
    }

    @Test func anUpdateReplacesTheFiltersTheWindowShows() throws {
        let view = LibraryView(
            id: ItemID("v"), title: "V", version: 2,
            query: LibraryViewQuery(types: [Self.task], filter: #"tags contains "x" AND properties.status eq "todo""#))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        #expect(seed.filters == ["field.status": ["todo"]])
        func update(_ filters: [String: Set<String>]) -> (change: LibraryViewChange, unkept: [ViewDraft.Unkept], unchanged: [String]) {
            var options = seed
            options.filters = filters
            return ViewDraft.change(Self.window(.view(view.id), filters: filters), options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        }

        // Removing the filter in the window removes it from the view; what the window cannot show stays.
        let removed = update([:])
        #expect(removed.change.query?.filter == #"tags contains "x""#)
        #expect(removed.unchanged == [#"tags contains "x""#])

        let changed = update(["field.status": ["done"]])
        #expect(changed.change.query?.filter == #"tags contains "x" AND properties.status eq "done""#)

        // A window filter the view cannot hold leaves the view's filter whole, rather than dropping what it showed.
        let mixed = update(["field.status": ["todo", "done"]])
        #expect(mixed.change.query == nil)
        #expect(mixed.unkept == [.mixedFilters])

        // An unchanged window sends no filter.
        #expect(update(seed.filters).change.query == nil)
    }

    @Test func aFilterOnAColumnTheTableLacksStaysAsItIs() {
        let view = LibraryView(
            id: ItemID("v"), title: "V",
            query: LibraryViewQuery(filter: #"properties.owner eq "ann" AND properties.status eq "todo""#))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.filters = [:]
        let window = ViewDraft.Window(place: .view(view.id), columns: Self.columns, sort: [], grouping: nil, filters: [:])
        let update = ViewDraft.change(window, options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change.query?.filter == #"properties.owner eq "ann""#)
        #expect(update.unchanged == [#"properties.owner eq "ann""#])
    }
}
