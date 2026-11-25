import Foundation
import Marfa
import Testing
@testable import MarfaMac

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

    private static let catalogue = MarfaMac.Catalogue(itemTypes: [
        ItemTypeInfo(
            id: event, label: "Event", fields: [precision, eventStatus, allDay, starts, ends, place, attendees, code],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: task, label: "Task", fields: [taskStatus, due], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: note, label: "Note", fields: [noteStatus], titleField: "title", bodyField: "body", parent: nil),
    ])

    private static func item(_ id: String, _ type: TypeID, _ properties: [String: PropertyValue] = [:]) -> MarfaMac.Item {
        MarfaMac.Item(
            id: ItemID(id), type: type, title: id, titleRule: .property("title"),
            properties: properties.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: $0.value) },
            version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
    }

    private static func rows(_ items: [MarfaMac.Item]) -> [ItemTableRow] {
        items.map { ItemTableRow(item: $0, typeLabel: catalogue.label(for: $0.type), typeIcon: nil, parent: nil) }
    }

    private static func columns(_ rows: [ItemTableRow], types: Set<TypeID> = []) -> [ItemTableColumn] {
        ItemTableLayout.columns(for: rows, types: types, catalogue: catalogue, hidden: [], looks: [:])
    }

    private static func offer(
        _ items: [MarfaMac.Item], types: Set<TypeID>, layout: ItemViewMode
    ) -> GroupOffer {
        let rows = rows(items)
        return GroupOffer.make(
            columns: columns(rows, types: types), types: types.union(items.map(\.type)), rows: rows, catalogue: catalogue,
            layout: layout)
    }

    /// Events where some have a start and status, and none fills Precision, Place or Attendees.
    private static let events = [
        item("open-day", event, ["status": .string("confirmed"), "all_day": .bool(true)]),
        item("stand-up", event, ["starts_at": .string("2026-11-16T09:30:00Z"), "ends_at": .string("2026-11-16T10:00:00Z")]),
    ]

    // MARK: What is offered

    @Test func aSavedViewCanKeepEveryGroupingOffered() {
        let rows = Self.rows(Self.events)
        let columns = Self.columns(rows, types: [Self.event])
        let offer = Self.offer(Self.events, types: [Self.event], layout: .table)
        for choice in offer.entries.flatMap(\.choices) {
            guard case .column(let id, let mode) = choice.grouping else { continue }
            let kept = ViewDraft.group(columns.first { $0.id == id }, mode: mode)
            #expect(kept.group != nil && kept.unkept.isEmpty, "\(id) by \(mode)")
        }
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

    /// In a saved view the groups are Marfa's: a row whose type lacks the field is Not Set, and a status word its type
    /// does not declare is No Status (`device/view-group-presence`, `device/view-group-status`). A place keeps Not Applicable.
    @Test func aSavedViewGroupsEveryRowAsMarfaDoes() throws {
        let items = [
            Self.item("open-day", Self.event, ["place": .string("Studio")]), Self.item("plan", Self.task),
            Self.item("odd", Self.task, ["status": .string("someday")]), Self.item("done", Self.task, ["status": .string("done")]),
        ]
        let rows = Self.rows(items)
        let columns = Self.columns(rows)
        let place = try #require(columns.first { $0.id == "field.place" })
        #expect(ItemTableLayout.groups(of: rows, by: place, mode: .presence, catalogue: Self.catalogue).map(\.id).contains(GroupKey.notApplicable))
        let marfa = ItemTableLayout.groups(of: rows, by: place, mode: .presence, catalogue: Self.catalogue, declared: true, asMarfa: true)
        #expect(marfa.map(\.id) == ["false", "true"])
        #expect(Set(marfa[0].rows.map(\.item.id.rawValue)) == ["plan", "odd", "done"])
        let status = try #require(columns.first { $0.id == "field.status" && $0.groups(by: .statusGroups) })
        let tasks = Self.rows(Array(items.dropFirst()))
        let none = ItemTableLayout.groups(of: tasks, by: status, mode: .statusGroups, catalogue: Self.catalogue, declared: true, asMarfa: true)
        #expect(Set(try #require(none.first { $0.id == "" }).rows.map(\.item.id.rawValue)) == ["plan", "odd"])
        let lanes = ItemBoardLayout.lanes(items: Array(items.dropFirst()), key: "status", catalogue: Self.catalogue, statusGroups: true, asMarfa: true)
        #expect(Set(try #require(lanes.first { $0.groupKey == "" }).items.map(\.id.rawValue)) == ["plan", "odd"])
    }

    // MARK: In a window

    private static func library(_ items: [MarfaMac.Item]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: items, now: Date(timeIntervalSince1970: 1_794_000_000))
        library.catalogue = catalogue
        return library
    }

    private static func window(_ library: FakeItemLibrary, place: PlaceView, layout: ItemViewMode, defaults: UserDefaults = ViewPanelTests.defaults()) -> Browser {
        let browser = Browser()
        browser.defaults = defaults
        browser.adopt(library)
        browser.showing = place
        browser.followPlaceDefault(in: library)
        browser.set(layout: layout)
        browser.choicesChanged()
        return browser
    }

    @Test func aPlacesListKeepsItsOwnSortAndGroupInItsDefaultView() {
        let items = [Self.item("a", Self.task, ["status": .string("todo")])]
        let library = Self.library(items)
        let defaults = ViewPanelTests.defaults()
        let place = PlaceView.type(Self.task)
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

    @Test func aNewViewKeepsABoardBySetOrNotSet() throws {
        let library = Self.library(Self.events)
        let browser = Self.window(library, place: .type(Self.event), layout: .board)
        browser.chooseGrouping(.column("field.starts_at", by: .presence))
        let window = SavedViews.window(browser, in: library, order: browser.storedOrder)
        let draft = try #require(ViewDraft.draft(window, catalogue: library.catalogue, views: []))
        #expect(draft.group == LibraryViewGroup(field: "properties.starts_at", byPresence: true))
        #expect(draft.unkept.isEmpty)
    }

    @Test func aViewWritesTheGroupsItPutsFirstAndHides() {
        let column = ItemTableColumn(id: "field.all_day", label: "All Day", content: .field(Self.allDay), style: .boolean)
        let view = LibraryView(id: ItemID("v"), title: "V", version: 2, group: LibraryViewGroup(field: "properties.all_day"))
        let seed = ViewDraft.options(for: view, catalogue: Self.catalogue)
        var options = seed
        options.groupOrder = ["false", ""]
        options.hiddenGroups = ["true"]
        var window = ViewDraft.Window(place: .saved(view.id), columns: [column], sort: [], grouping: column)
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

    /// Chooses `mode` on `column` in a view that has no grouping, puts `order` first and hides `hidden`, and reads the
    /// view back as the window opens it.
    private static func roundTrip(
        _ column: ItemTableColumn, mode: GroupMode, types: [TypeID] = [], order: [String], hidden: Set<String>
    ) throws -> (written: LibraryViewGroup, reread: ItemTableOptions) {
        var view = LibraryView(id: ItemID("v"), title: "V", version: 2)
        view.query.types = types
        var window = ViewDraft.Window(place: .saved(view.id), columns: [column], sort: [], grouping: column)
        window.layout = .table
        window.groupMode = mode
        let seed = ViewDraft.options(for: view, catalogue: catalogue)
        var chosen = seed
        chosen.grouping = .column(column.id, by: mode)
        let first = ViewDraft.change(window, options: chosen, seed: seed, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: catalogue)
        guard case .set(let grouped) = try #require(first.change.group) else { throw CancellationError() }
        #expect(first.unkept.isEmpty)
        view.group = grouped
        let regrouped = ViewDraft.options(for: view, catalogue: catalogue)
        #expect(regrouped.grouping == .column(column.id, by: mode), "the view opens with the grouping it was given")
        var arranged = regrouped
        arranged.groupOrder = order
        arranged.hiddenGroups = hidden
        let second = ViewDraft.change(window, options: arranged, seed: regrouped, seedTimelineDate: nil, seededTypes: nil, view: view, catalogue: catalogue)
        guard case .set(let written) = try #require(second.change.group) else { throw CancellationError() }
        view.group = written
        return (written, ViewDraft.options(for: view, catalogue: catalogue))
    }

    @Test func aViewKeepsGroupsByStatusGroupWithTheirOrderAndHiddenGroups() throws {
        let column = ItemTableColumn(id: "field.status", label: "Status", content: .field(Self.taskStatus), style: .status)
        let result = try Self.roundTrip(column, mode: .statusGroups, types: [Self.task], order: ["completed", "not_started"], hidden: [""])
        #expect(result.written == LibraryViewGroup(
            field: "status_group", order: [.string("completed"), .string("not_started")], hidden: [.null]))
        #expect(result.reread.grouping == .column("field.status", by: .statusGroups))
        #expect(result.reread.groupOrder == ["completed", "not_started"])
        #expect(result.reread.hiddenGroups == [""])
    }

    @Test func aViewKeepsGroupsBySetOrNotSetWithTheirOrderAndHiddenGroups() throws {
        let column = ItemTableColumn(id: "field.due_at", label: "Due", content: .field(Self.due), style: .date)
        let result = try Self.roundTrip(column, mode: .presence, order: [GroupKey.notSet], hidden: [GroupKey.set])
        #expect(result.written == LibraryViewGroup(field: "properties.due_at", order: [.bool(false)], hidden: [.bool(true)], byPresence: true))
        #expect(result.reread.grouping == .column("field.due_at", by: .presence))
        #expect(result.reread.groupOrder == [GroupKey.notSet])
        #expect(result.reread.hiddenGroups == [GroupKey.set])
    }

    @Test func aViewKeepsGroupsBySourceWithTheirOrderAndHiddenGroups() throws {
        let result = try Self.roundTrip(.source, mode: .value, order: ["mail", ""], hidden: ["calendar"])
        #expect(result.written == LibraryViewGroup(field: "source", order: [.string("mail"), .null], hidden: [.string("calendar")]))
        #expect(result.reread.grouping == .column(ItemTableColumn.source.id, by: .value))
        #expect(result.reread.groupOrder == ["mail", ""])
        #expect(result.reread.hiddenGroups == ["calendar"])
    }

    // MARK: The board

    @Test func aBoardByNotSetClearsAnOptionalFieldAndRefusesARequiredOne() {
        let library = Self.library(Self.events)
        let browser = Self.window(library, place: .type(Self.event), layout: .board)
        browser.chooseGrouping(.column("field.starts_at", by: .presence))
        let lanes = try! #require(browser.boardLanes(in: library))
        #expect(lanes.all.map(\.title) == ["Not Set", "Set"])
        #expect(lanes.all.map(\.takesItems) == [true, false], "Set takes no card, since the app would have to invent a value")
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
        let browser = Self.window(library, place: .type(Self.task), layout: .table)
        browser.chooseGrouping(.none)
        browser.choicesChanged()
        browser.set(layout: .board)
        #expect(browser.boardGrouping(in: library) == .column("field.status"))
        #expect(browser.tableOptions[browser.shown]?.grouping == ItemTableOptions.Grouping.none, "the board leaves the table's choice alone")
        browser.set(layout: .table)
        #expect(browser.shownGrouping(in: library) == .none)
    }
}
