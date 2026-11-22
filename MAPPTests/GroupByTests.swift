import Foundation
import Marfa
import Testing
@testable import MAPP

/// One Group by for every layout and place: what it offers from the types a place lists, the groups each way of grouping
/// makes, the order and hidden groups, where a choice is kept, and what a saved view cannot keep yet.
@MainActor
@Suite(.serialized, .hangLimit)
struct GroupByTests {
    private static let event = TypeID("test.event")
    private static let task = TypeID("test.task")
    private static let note = TypeID("test.note")

    private static let eventStatus = ItemTypeInfo.Field(
        key: "status", label: "Status", kind: .choice(["tentative", "confirmed", "canceled"]), declaredBy: event)
    private static let precision = ItemTypeInfo.Field(key: "precision", label: "Precision", kind: .choice(["day", "time"]), declaredBy: event)
    private static let allDay = ItemTypeInfo.Field(key: "all_day", label: "All Day", kind: .boolean, declaredBy: event)
    private static let starts = ItemTypeInfo.Field(key: "starts_at", label: "Starts", kind: .date(includesTime: true), declaredBy: event)
    private static let ends = ItemTypeInfo.Field(key: "ends_at", label: "Ends", kind: .date(includesTime: true), declaredBy: event)
    private static let place = ItemTypeInfo.Field(key: "place", label: "Place", kind: .text, declaredBy: event)
    private static let attendees = ItemTypeInfo.Field(
        key: "attendees", label: "Attendees", kind: .list(ListShape(members: [])), declaredBy: event)
    private static let code = ItemTypeInfo.Field(key: "code", label: "Code", kind: .text, declaredBy: event, required: true)

    private static let taskStatus = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status([
        StatusWord(value: "todo", group: .notStarted), StatusWord(value: "doing", group: .inProgress),
        StatusWord(value: "done", group: .completed),
    ]), declaredBy: task)
    private static let due = ItemTypeInfo.Field(key: "due_at", label: "Due", kind: .date(includesTime: false), declaredBy: task)
    private static let noteStatus = ItemTypeInfo.Field(key: "progress", label: "Progress", kind: .status([
        StatusWord(value: "draft", group: .notStarted), StatusWord(value: "published", group: .completed),
    ]), declaredBy: note)

    private static let catalogue = MAPP.Catalogue(itemTypes: [
        ItemTypeInfo(
            id: event, label: "Event", fields: [precision, eventStatus, allDay, starts, ends, place, attendees, code],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: task, label: "Task", fields: [taskStatus, due], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: note, label: "Note", fields: [noteStatus], titleField: "title", bodyField: "body", parent: nil),
    ])

    private static func item(_ id: String, _ type: TypeID, _ properties: [String: PropertyValue] = [:]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID(id), type: type, title: id, titleRule: .property("title"),
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: $0.value) },
            version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
    }

    private static func rows(_ items: [MAPP.Item]) -> [ItemTableRow] {
        items.map { ItemTableRow(item: $0, typeLabel: catalogue.label(for: $0.type), typeIcon: nil, parent: nil) }
    }

    private static func columns(_ rows: [ItemTableRow], types: Set<TypeID> = []) -> [ItemTableColumn] {
        ItemTableLayout.columns(for: rows, types: types, catalogue: catalogue, hidden: [], looks: [:])
    }

    private static func offer(
        _ items: [MAPP.Item], types: Set<TypeID>, layout: ItemViewMode, isView: Bool = false
    ) -> GroupOffer {
        let rows = rows(items)
        return GroupOffer.make(
            columns: columns(rows, types: types), types: types.union(items.map(\.type)), rows: rows, catalogue: catalogue,
            layout: layout, isView: isView)
    }

    private static func labels(_ section: [GroupOffer.Entry]) -> [String] { section.map(\.label) }

    /// Events where some have a start and status, and none fills Precision, Place or Attendees.
    private static let events = [
        item("open-day", event, ["status": .string("confirmed"), "all_day": .bool(true)]),
        item("stand-up", event, ["starts_at": .string("2026-11-16T09:30:00Z"), "ends_at": .string("2026-11-16T10:00:00Z")]),
    ]

    // MARK: What is offered

    @Test func aBoardOfOneTypeOffersItsFieldsAndWaitsTheUnfilledOnesUnderMoreFields() {
        let offer = Self.offer(Self.events, types: [Self.event], layout: .board)
        #expect(!offer.offersNone, "a board always has lanes")
        #expect(Self.labels(offer.sections[0]) == ["Status", "All Day", "Starts", "Ends"])
        // A single type has no Type, and the board has no Parent.
        #expect(Self.labels(offer.sections[1]) == ["Created", "Edited", "Happened"])
        #expect(Self.labels(offer.moreFields) == ["Precision", "Place", "Attendees"])
        let starts = offer.sections[0][2].choices
        #expect(starts.map(\.label) == ["Day", "Week", "Month", "Year", "Set or Not Set"])
        #expect(starts.map(\.startsSection) == [false, false, false, false, true])
        // A field no item fills offers its values and Set or Not Set; a required one is never empty, so it is not offered.
        #expect(offer.moreFields[0].choices.map(\.label) == ["Each Option", "Set or Not Set"])
        #expect(offer.moreFields[1].choices.map(\.grouping) == [.column("field.place", by: .presence)])
        #expect(!offer.entries.contains { $0.label == "Code" })
        // Every item has Created, Edited and Happened, so they offer their spans alone.
        #expect(offer.sections[1].allSatisfy { $0.choices.count == 4 })
    }

    @Test func aMixedListOffersNoneTypeAndParentAndStatusAsGroupsWhereTheWordsDiffer() {
        let items = [Self.item("t", Self.task, ["status": .string("todo")]), Self.item("n", Self.note, ["progress": .string("draft")])]
        let offer = Self.offer(items, types: [], layout: .list)
        #expect(offer.offersNone)
        let status = try! #require(offer.sections[0].first { $0.id == GroupOffer.statusID })
        #expect(status.choices.map(\.grouping.mode) == [.statusGroups], "the types keep their status apart, so Words is not offered")
        // Two types with one status field but different words share no words either.
        let other = ItemTypeInfo(id: TypeID("test.chore"), label: "Chore", fields: [ItemTypeInfo.Field(key: "status", label: "Status", kind: .status([
            StatusWord(value: "open", group: .notStarted)]), declaredBy: TypeID("test.chore"))], titleField: "title", bodyField: "body", parent: nil)
        var types = Self.catalogue.itemTypes
        types[other.id] = other
        let mixed = MAPP.Catalogue(itemTypes: Array(types.values))
        let rows = Self.rows([Self.item("t", Self.task, ["status": .string("todo")]), Self.item("c", other.id, ["status": .string("open")])])
        let words = GroupOffer.make(
            columns: ItemTableLayout.columns(for: rows, catalogue: mixed, hidden: [], looks: [:]), types: [Self.task, other.id], rows: rows,
            catalogue: mixed, layout: .table, isView: false)
        #expect(words.sections[0].first?.choices.map(\.grouping) == [.column("field.status", by: .statusGroups)])
        #expect(Self.labels(offer.sections[1]).prefix(2) == ["Type", "Parent"])
    }

    @Test func oneTypesStatusOffersWordsAndGroups() {
        let offer = Self.offer([Self.item("t", Self.task, ["status": .string("todo")])], types: [Self.task], layout: .table)
        let status = try! #require(offer.sections.first?.first)
        #expect(status.choices.map(\.label) == ["Words", "Groups"])
        #expect(status.choices.map(\.grouping) == [.column("field.status"), .column("field.status", by: .statusGroups)])
        // The board falls back to the words where nothing else is chosen.
        #expect(offer.fallback == .column("field.status"))
    }

    @Test func aTypeWithNoDateFieldOffersNoDateOfItsOwn() {
        let offer = Self.offer([Self.item("n", Self.note, ["progress": .string("draft")])], types: [Self.note], layout: .table)
        #expect(offer.sections[0].map(\.label) == ["Progress"])
        #expect(offer.moreFields.isEmpty)
        #expect(offer.entries.allSatisfy { !$0.choices.isEmpty }, "no empty submenu")
    }

    @Test func aTypesFieldsAreOfferedThoughNoItemIsListed() {
        let offer = Self.offer([], types: [Self.task], layout: .table)
        #expect(offer.sections[0].map(\.label) == ["Status"], "the status leads whether or not an item has one yet")
        #expect(offer.moreFields.map(\.label) == ["Due"])
    }

    @Test func aSavedViewShowsWhatItCannotKeepAsNotKept() {
        let offer = Self.offer(Self.events, types: [Self.event], layout: .table, isView: true)
        let starts = try! #require(offer.entries.first { $0.label == "Starts" })
        #expect(starts.choices.map(\.isKept) == [true, true, true, true, false])
        let words = Self.offer([Self.item("t", Self.task, ["status": .string("todo")])], types: [Self.task], layout: .table, isView: true)
        #expect(words.sections[0][0].choices.map(\.isKept) == [true, false])
    }

    // MARK: The groups

    @Test func setOrNotSetIsWhatMarfasExistsTests() throws {
        let items = [
            Self.item("missing", Self.event), Self.item("null", Self.event, ["place": .null]),
            Self.item("empty-text", Self.event, ["place": .string("")]), Self.item("text", Self.event, ["place": .string("Studio")]),
            Self.item("empty-list", Self.event, ["attendees": .array([])]), Self.item("date", Self.event, ["starts_at": .string("2026-11-16")]),
        ]
        let rows = Self.rows(items)
        let columns = Self.columns(rows)
        func groups(_ key: String) throws -> [ItemTableGroup] {
            let column = try #require(columns.first { $0.id == "field." + key })
            return ItemTableLayout.groups(of: rows, by: column, mode: .presence)
        }
        let place = try groups("place")
        #expect(place.map(\.id) == ["false", "true"])
        #expect(place.map(\.title) == ["Not Set", "Set"])
        #expect(place[0].rows.map(\.item.id.rawValue) == ["missing", "null", "empty-list", "date"])
        #expect(place[1].rows.map(\.item.id.rawValue) == ["empty-text", "text"], "an empty text is set")
        #expect(try groups("attendees")[1].rows.map(\.item.id.rawValue) == ["empty-list"], "an empty list is set")
        #expect(try groups("starts_at")[1].rows.map(\.item.id.rawValue) == ["date"])
        // A grouping chosen lists both groups though one is empty, for Hide Empty Groups to leave out.
        let column = try #require(columns.first { $0.id == "field.ends_at" })
        #expect(ItemTableLayout.groups(of: rows, by: column, mode: .presence, declared: true).map(\.id) == ["false", "true"])
        #expect(ItemTableLayout.groups(of: rows, by: column, mode: .presence).map(\.id) == ["false"])
    }

    @Test func statusGroupsGatherEveryTypeByItsOwnStatusAndTheRestUnderNoStatus() throws {
        let items = [
            Self.item("t-doing", Self.task, ["status": .string("doing")]), Self.item("n-published", Self.note, ["progress": .string("published")]),
            Self.item("t-none", Self.task), Self.item("event", Self.event, ["status": .string("confirmed")]),
            Self.item("n-draft", Self.note, ["progress": .string("draft")]),
        ]
        let rows = Self.rows(items)
        let column = try #require(Self.columns(rows).first { $0.style == .status })
        let groups = ItemTableLayout.groups(of: rows, by: column, mode: .statusGroups, catalogue: Self.catalogue, declared: true)
        #expect(groups.map(\.id) == ["not_started", "in_progress", "completed", "canceled", ""])
        #expect(groups.map { $0.rows.map(\.item.id.rawValue) } == [["n-draft"], ["t-doing"], ["n-published"], [], ["t-none", "event"]])
        #expect(groups.last?.title == "No Status")
    }

    @Test func aFieldOnlySomeTypesDeclareGivesTheOthersNotApplicable() throws {
        let items = [Self.item("t", Self.task, ["due_at": .string("2026-11-24")]), Self.item("n", Self.note), Self.item("t2", Self.task)]
        let rows = Self.rows(items)
        let due = try #require(Self.columns(rows).first { $0.id == "field.due_at" })
        let groups = ItemTableLayout.groups(of: rows, by: due, mode: .presence, catalogue: Self.catalogue)
        #expect(groups.map(\.id) == ["false", "true", GroupKey.notApplicable])
        #expect(groups.last?.title == "Not Applicable")
        #expect(groups.last?.rows.map(\.item.id.rawValue) == ["n"])
    }

    @Test func theOrderNamedComesFirstThenTheRestThenNotApplicable() {
        let groups = ["a", "b", "c", "", GroupKey.notApplicable].map { ItemTableGroup(id: $0, title: $0, rows: []) }
        #expect(ItemTableLayout.ordered(groups, by: ["c", GroupKey.notApplicable, "", "gone"]).map(\.id) == ["c", "", "a", "b", GroupKey.notApplicable])
        #expect(ItemTableLayout.ordered(groups, by: nil).map(\.id) == groups.map(\.id))
    }

    // MARK: In a window

    private static func library(_ items: [MAPP.Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items, now: Date(timeIntervalSince1970: 1_794_000_000))
        library.catalogue = catalogue
        return library
    }

    private static func window(_ library: FakeItemLibrary, place: SidebarItem, layout: ItemViewMode, defaults: UserDefaults = ViewPanelTests.defaults()) -> Browser {
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library)
        browser.sidebarItem = place
        browser.followPlaceDefault(in: library)
        browser.set(layout: layout)
        browser.choicesChanged()
        return browser
    }

    @Test func hiddenGroupsLeaveTheTableAndTheirItemsStillCount() {
        let items = [Self.item("a", Self.task, ["status": .string("todo")]), Self.item("b", Self.task, ["status": .string("done")])]
        let library = Self.library(items)
        let browser = Self.window(library, place: .itemType(Self.task.rawValue), layout: .table)
        browser.chooseGrouping(.column("field.status"))
        browser.setGroup("done", hidden: true, in: library)
        browser.moveGroup("done", before: "todo", in: library)
        let content = browser.tableContent(in: library)
        #expect(content.allGroups.map(\.id) == ["done", "todo", "doing"])
        #expect(content.groups.map(\.id) == ["todo", "doing"])
        #expect(content.rows.count == 2, "a hidden group narrows no listing")
        browser.setGroup("todo", hidden: true, in: library)
        browser.setHidesEmptyGroups(true)
        #expect(browser.tableContent(in: library).hidesEveryGroup)
        // A new grouping starts with no order and nothing hidden.
        browser.chooseGrouping(.column("field.status", by: .statusGroups))
        browser.choicesChanged()
        #expect(browser.tableOptions[browser.item]?.groupOrder == nil)
        #expect(browser.tableOptions[browser.item]?.hiddenGroups == nil)
    }

    @Test func aPlacesListKeepsItsOwnSortAndGroupInItsDefaultView() {
        let items = [Self.item("a", Self.task, ["status": .string("todo")])]
        let library = Self.library(items)
        let defaults = ViewPanelTests.defaults()
        let place = SidebarItem.itemType(Self.task.rawValue)
        let first = Self.window(library, place: place, layout: .list, defaults: defaults)
        // The list starts in Settings' order, its edited date by day.
        #expect(first.shownGrouping(in: library) == .column(ItemTableColumn.edited.id, by: .bucket(.day)))
        first.chooseGrouping(.column("field.due_at", by: .presence))
        first.choicesChanged()
        first.setHidesEmptyGroups(true)
        first.setGroup("true", hidden: true, in: library)
        first.choicesChanged()

        let second = Self.window(library, place: place, layout: .list, defaults: defaults)
        let options = second.tableOptions[place]
        #expect(options?.grouping == .column("field.due_at", by: .presence))
        #expect(options?.sort?.map(\.column.id) == [ItemTableColumn.edited.id], "the order the list showed is now the place's own")
        #expect(options?.hiddenGroups == ["true"])
        #expect(second.hidesEmptyGroups)
        #expect(second.shownGrouping(in: library) == .column("field.due_at", by: .presence))
        #expect(second.sections(in: library, order: second.storedOrder, now: library.now()).map { $0.group?.title() } == ["Not Set"])
    }

    @Test func saveAsViewNamesTheGroupingAViewCannotKeep() throws {
        let library = Self.library(Self.events)
        let browser = Self.window(library, place: .itemType(Self.event.rawValue), layout: .board)
        browser.chooseGrouping(.column("field.starts_at", by: .presence))
        let window = SavedViews.window(browser, in: library, order: browser.storedOrder)
        let draft = try #require(ViewDraft.draft(window, catalogue: library.catalogue, views: []))
        #expect(draft.group == nil)
        #expect(draft.unkept == [.groupMode(column: "Starts", mode: "Set or Not Set")])
        #expect(SavedViews.describe(draft.unkept[0]) == "Group by Starts: Set or Not Set")
    }

    @Test func aViewWritesTheGroupsItPutsFirstAndHides() {
        let column = ItemTableColumn(id: "field.all_day", label: "All Day", content: .field(Self.allDay), style: .boolean)
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, group: LibraryViewGroup(field: "properties.all_day"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.groupOrder = ["false", ""]
        options.hiddenGroups = ["true"]
        var window = ViewDraft.Window(place: .view(view.id), columns: [column], sort: [], grouping: column)
        window.layout = .table
        let update = ViewDraft.change(window, options: options, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: Self.catalogue)
        #expect(update.change == LibraryViewChange(group: .set(LibraryViewGroup(
            field: "properties.all_day", order: [.bool(false), .null], hidden: [.bool(true)]))))
        // And a view's lists open as the window's.
        let reread = LibraryView(id: ItemID("v"), title: "V", group: LibraryViewGroup(field: "properties.all_day", order: [.bool(false)], hidden: [.null]))
        let opened = ViewDraft.options(for: reread, catalogue: Self.catalogue)
        #expect(opened.groupOrder == ["false"])
        #expect(opened.hiddenGroups == [""])
    }

    // MARK: The board

    @Test func aBoardByNotSetClearsAnOptionalFieldAndRefusesARequiredOne() {
        let library = Self.library(Self.events)
        let browser = Self.window(library, place: .itemType(Self.event.rawValue), layout: .board)
        browser.chooseGrouping(.column("field.starts_at", by: .presence))
        let lanes = try! #require(browser.boardLanes(in: library))
        #expect(lanes.all.map(\.title) == ["Not Set", "Set"])
        #expect(lanes.all.map(\.takesItems) == [true, false], "Set takes no card, since MAPP would have to invent a value")
        let set = Self.events[1]
        #expect(ItemBoardLayout.move(set, key: "starts_at", to: .missing, catalogue: Self.catalogue) == .set(nil))
        #expect(ItemBoardLayout.move(Self.events[0], key: "starts_at", to: .missing, catalogue: Self.catalogue) == .unchanged)
        #expect(ItemBoardLayout.move(set, key: "code", to: .missing, catalogue: Self.catalogue) == .needsValue)
        var skips = BatchSkips()
        skips.skip(.needsValue)
        #expect(skips != BatchSkips())
    }

    @Test func aBoardShowsLanesWhereThePlaceHasNoneAndKeepsThePlacesChoice() {
        let items = [Self.item("t", Self.task, ["status": .string("todo")])]
        let library = Self.library(items)
        let browser = Self.window(library, place: .itemType(Self.task.rawValue), layout: .table)
        browser.chooseGrouping(.none)
        browser.choicesChanged()
        browser.set(layout: .board)
        #expect(browser.boardGrouping(in: library) == .column("field.status"))
        #expect(browser.tableOptions[browser.item]?.grouping == ItemTableOptions.Grouping.none, "the board leaves the table's choice alone")
        browser.set(layout: .table)
        #expect(browser.shownGrouping(in: library) == .none)
    }
}
