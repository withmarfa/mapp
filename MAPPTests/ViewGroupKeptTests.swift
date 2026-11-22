import Foundation
import Marfa
import Testing
@testable import MAPP

/// What a saved view's group holds survives MAPP: the order and hidden groups another app set, a grouping MAPP cannot
/// show, and a date's day, week, month or year, which MAPP reads and groups by.
@MainActor
struct ViewGroupKeptTests {
    private static let task = TypeID("core.task")
    private static let status = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status([
        StatusWord(value: "done", group: .completed), StatusWord(value: "todo", group: .notStarted),
        StatusWord(value: "doing", group: .inProgress),
    ]), declaredBy: task)
    private static let priority = ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task)
    private static let due = ItemTypeInfo.Field(key: "due_at", label: "Due", kind: .date(includesTime: false), declaredBy: task)
    private static let starts = ItemTypeInfo.Field(key: "starts_at", label: "Starts", kind: .date(includesTime: true), declaredBy: task)
    private static let note = ItemTypeInfo.Field(key: "note", label: "Note", kind: .text, declaredBy: task)
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: task, label: "Task", fields: [status, priority, due, starts, note], titleField: "title", bodyField: "body", parent: nil),
    ])
    private static let statusColumn = ItemTableColumn(id: "field.status", label: "Status", content: .field(status), style: .status)
    private static let priorityColumn = ItemTableColumn(id: "field.priority", label: "Priority", content: .field(priority), style: .priority)
    private static let dueColumn = ItemTableColumn(id: "field.due_at", label: "Due", content: .field(due), style: .date)
    private static let columns = [ItemTableColumn.title, statusColumn, priorityColumn, dueColumn, .edited, .created, .occurred]

    /// A view's group with what another app set: groups first, and groups left out.
    private static let otherApps: (order: [JSONValue], hidden: [JSONValue]) = ([.string("2026-11-16"), .null], [.string("2026-11-30")])

    private static func view(_ group: LibraryViewGroup?) -> LibraryView {
        LibraryView(
            id: ItemID("view-tasks"), title: "Tasks", version: 3, query: LibraryViewQuery(types: [task]),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: group)
    }

    private static func window(
        grouping: ItemTableColumn? = nil, mode: GroupMode = .value, sort: [ItemTableComparator] = [],
        filters: [String: Set<String>] = [:], layout: ViewDraft.Layout = .table, timelineDate: String? = nil
    ) -> ViewDraft.Window {
        var window = ViewDraft.Window(
            place: .view(ItemID("view-tasks")), columns: columns, sort: sort, grouping: grouping, filters: filters, layout: layout,
            timelineDate: timelineDate)
        window.groupMode = mode
        return window
    }

    private static func change(
        _ view: LibraryView, window: ViewDraft.Window, _ edit: (inout ItemTableOptions) -> Void, timelineDate: String? = nil
    ) -> (change: LibraryViewChange, unkept: [ViewDraft.Unkept]) {
        let seed = ViewDraft.options(for: view, catalogue: catalogue)
        var options = seed
        edit(&options)
        return ViewDraft.change(
            window, options: options, seed: seed, seedTimelineDate: ViewDraft.timelineDate(of: view), seededTypes: nil, view: view,
            catalogue: catalogue)
    }

    // MARK: Reading and writing every part of a group

    @Test func everyBucketAndTheGroupsAnotherAppSetRoundTrip() throws {
        let buckets: [ViewGrouping.Bucket?] = [nil] + ViewGrouping.Bucket.allCases.map { $0 }
        for bucket in buckets {
            let grouping = ViewGrouping(by: "properties.due_at", bucket: bucket, order: Self.otherApps.order, hidden: Self.otherApps.hidden)
            let saved = SavedView(id: "v", version: 1, settings: ViewSettings(title: "Tasks", group: grouping))
            let read = try #require(MarfaMapping.view(saved))
            #expect(read.group?.order == Self.otherApps.order)
            #expect(read.group?.hidden == Self.otherApps.hidden)
            #expect(MarfaMapping.viewSettings(read.settings).group == grouping, "\(String(describing: bucket)) did not come back as read")
            #expect(MarfaMapping.viewChange(LibraryViewChange(group: .set(read.group!))).group == .set(grouping))
        }
    }

    @Test func aDateOpensGroupedByItsDayWeekMonthOrYear() {
        for bucket in LibraryViewGroup.Bucket.allCases {
            for (field, column) in [("properties.due_at", "field.due_at"), ("created_at", "created"), ("updated_at", "edited"), ("occurred_at", "occurred")] {
                let options = ViewDraft.options(for: Self.view(LibraryViewGroup(field: field, bucket: bucket)), catalogue: Self.catalogue)
                #expect(options.grouping == .column(column, by: .bucket(bucket)), "\(field) by \(bucket)")
            }
        }
        // A span of something that is no date, and a link MAPP has no column for, open ungrouped.
        #expect(ViewDraft.options(for: Self.view(LibraryViewGroup(field: "properties.note", bucket: .week)), catalogue: Self.catalogue).grouping == .none)
        #expect(ViewDraft.options(for: Self.view(LibraryViewGroup(field: "edge[cites]")), catalogue: Self.catalogue).grouping == .none)
        #expect(ViewDraft.options(for: Self.view(LibraryViewGroup(field: "tier")), catalogue: Self.catalogue).grouping == .none)
    }

    // MARK: Writes that leave the group alone

    @Test func aChangeOfNameQueryOrSortLeavesTheGroupAsRead() {
        let groups = [
            LibraryViewGroup(field: "properties.due_at", bucket: .week, order: Self.otherApps.order, hidden: Self.otherApps.hidden),
            LibraryViewGroup(field: "properties.status", order: [.string("doing")], hidden: [.null]),
            // Groupings MAPP cannot show, which open ungrouped.
            LibraryViewGroup(field: "edge[cites]", order: [.string("item-1")], hidden: [.string("item-2")]),
            LibraryViewGroup(field: "properties.note", bucket: .month, order: [.string("2026-11-01")]),
        ]
        for group in groups {
            let view = Self.view(group)
            let sorted = Self.change(view, window: Self.window(sort: [ItemTableComparator(column: .title)])) {
                $0.sort = [ItemTableComparator(column: .title)]
            }
            #expect(sorted.change == LibraryViewChange(sort: [LibraryViewSort(field: "title", ascending: true)]), "\(group.field)")
            let filtered = Self.change(view, window: Self.window(filters: ["field.priority": ["high"]])) {
                $0.filters = ["field.priority": ["high"]]
            }
            #expect(filtered.change.group == nil && filtered.change.query != nil, "\(group.field)")
        }
    }

    @Test func aViewKeepsEveryPartOfItsGroupThroughAWindowsWrites() async throws {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        let group = LibraryViewGroup(field: "edge[cites]", order: [.string("item-1")], hidden: [.string("item-2")])
        library.views = [Self.view(group)]
        let browser = Browser()
        browser.defaults = ViewPanelTests.defaults()
        browser.adopt(library)
        browser.sidebarItem = .view(ItemID("view-tasks"))
        browser.viewMode = .table
        browser.followView(in: library)
        browser.choicesChanged()
        #expect(browser.tableOptions[browser.item]?.grouping == ItemTableOptions.Grouping.none)

        browser.tableOptions[browser.item]?.sort = [ItemTableComparator(column: .title)]
        await browser.choicesChanged()?.value
        #expect(library.views.first?.sort == [LibraryViewSort(field: "title", ascending: true)])
        #expect(library.views.first?.group == group)
    }

    // MARK: Writes that change the group

    @Test func aNewSpanKeepsTheGroupsAnotherAppOrderedAndHid() {
        let view = Self.view(LibraryViewGroup(field: "properties.due_at", bucket: .week, order: Self.otherApps.order, hidden: Self.otherApps.hidden))
        let monthly = Self.change(view, window: Self.window(grouping: Self.dueColumn, mode: .bucket(.month))) {
            $0.grouping = .column("field.due_at", by: .bucket(.month))
        }
        #expect(monthly.change.group == .set(LibraryViewGroup(
            field: "properties.due_at", bucket: .month, order: Self.otherApps.order, hidden: Self.otherApps.hidden)))
        #expect(monthly.unkept.isEmpty)
    }

    @Test func anotherFieldDropsTheOldGroupsAndWritesMappsOrder() {
        let view = Self.view(LibraryViewGroup(field: "properties.priority", order: [.string("high")], hidden: [.string("low")]))
        let byStatus = Self.change(view, window: Self.window(grouping: Self.statusColumn)) { $0.grouping = .column("field.status") }
        // The words by their groups, as MAPP lists them: Not Started, In Progress, Completed.
        #expect(byStatus.change.group == .set(LibraryViewGroup(
            field: "properties.status", order: [.string("todo"), .string("doing"), .string("done")], hidden: [])))

        let byPriority = Self.change(Self.view(LibraryViewGroup(field: "properties.status", hidden: [.null])),
                                     window: Self.window(grouping: Self.priorityColumn)) { $0.grouping = .column("field.priority") }
        #expect(byPriority.change.group == .set(LibraryViewGroup(field: "properties.priority", order: [.string("low"), .string("high")])))

        // Grouping again by a field the window replaced, as an Undo does, gives back what another app set there.
        let earlier = LibraryViewGroup(field: "properties.status", order: [.string("done")], hidden: [.null])
        let back = ViewDraft.change(
            Self.window(grouping: Self.statusColumn), options: ItemTableOptions(grouping: .column("field.status")),
            seed: ViewDraft.options(for: view, catalogue: Self.catalogue), seedTimelineDate: nil, seededTypes: nil, view: view,
            catalogue: Self.catalogue, replaced: ["properties.status": earlier])
        #expect(back.change.group == .set(earlier))

        // A date has no order of MAPP's: its groups follow Marfa's.
        let byDue = Self.change(view, window: Self.window(grouping: Self.dueColumn, mode: .bucket(.week))) {
            $0.grouping = .column("field.due_at", by: .bucket(.week))
        }
        #expect(byDue.change.group == .set(LibraryViewGroup(field: "properties.due_at", bucket: .week)))
    }

    @Test func aNewViewWritesTheOrderMappListsItsGroupsIn() throws {
        var window = Self.window(grouping: Self.statusColumn)
        window.place = .itemType(Self.task.rawValue)
        let draft = try #require(ViewDraft.draft(window, catalogue: Self.catalogue, views: []))
        #expect(draft.group?.order == [.string("todo"), .string("doing"), .string("done")])
        window.layout = .board(key: "priority", label: "Priority")
        window.sort = [ItemTableComparator(column: Self.dueColumn, order: .forward)]
        let board = try #require(ViewDraft.draft(window, catalogue: Self.catalogue, views: []))
        #expect(board.group == LibraryViewGroup(field: "properties.priority", order: [.string("low"), .string("high")]))
        // The board's cards follow the window's sort, which the view keeps.
        #expect(board.sort == [LibraryViewSort(field: "properties.due_at", ascending: true)])
    }

    @Test func theTimelinesDayKeepsTheGroupsOfTheSameField() {
        let view = Self.view(LibraryViewGroup(field: "properties.due_at", bucket: .week, order: Self.otherApps.order, hidden: Self.otherApps.hidden))
        let window = Self.window(grouping: Self.dueColumn, mode: .bucket(.day), layout: .timeline(key: "due_at", label: "Due"), timelineDate: "due_at")
        let update = Self.change(view, window: window) { $0.grouping = .column("field.due_at", by: .bucket(.day)) }
        #expect(update.change.group == .set(LibraryViewGroup(
            field: "properties.due_at", bucket: .day, order: Self.otherApps.order, hidden: Self.otherApps.hidden)))
        #expect(update.unkept.isEmpty)
    }

    /// In a view the timeline's date and a grouping by its day are one setting, so changing either writes once and the
    /// window then agrees with the view.
    @Test func theTimelinesDateAndADayGroupingMoveTogether() async throws {
        let library = FakeItemLibrary()
        library.catalogue = Self.catalogue
        library.views = [Self.view(LibraryViewGroup(field: "properties.due_at", bucket: .day))]
        library.items.append(Self.row("due-soon", due: "2026-11-24").item)
        library.viewMembers[ItemID("view-tasks")] = [ItemID("due-soon")]
        let browser = Browser()
        browser.defaults = ViewPanelTests.defaults()
        browser.adopt(library)
        browser.sidebarItem = .view(ItemID("view-tasks"))
        browser.viewMode = .table
        browser.followView(in: library)
        browser.choicesChanged()
        #expect(browser.timelineFields[browser.item] == "due_at")
        #expect(browser.tableOptions[browser.item]?.grouping == .column("field.due_at", by: .bucket(.day)))

        browser.timelineFields[browser.item] = "starts_at"
        await browser.choicesChanged()?.value
        #expect(browser.tableOptions[browser.item]?.grouping == .column("field.starts_at", by: .bucket(.day)))
        #expect(library.views.first?.group == LibraryViewGroup(field: "properties.starts_at", bucket: .day))
        #expect(!browser.hasViewChanges)

        browser.tableOptions[browser.item]?.grouping = .column("field.priority")
        await browser.choicesChanged()?.value
        #expect(browser.timelineFields[browser.item] == nil)
        #expect(library.views.first?.group?.field == "properties.priority")
        #expect(!browser.hasViewChanges)
    }

    // MARK: Grouping by a date

    private static func row(_ id: String, due: String?) -> ItemTableRow {
        let item = MAPP.Item(
            id: ItemID(id), type: task, title: id, titleRule: .property("title"),
            properties: due.map { [Property(key: "due_at", value: .string($0))] } ?? [],
            version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
        return ItemTableRow(item: item, typeLabel: "Task", typeIcon: nil, parent: nil)
    }

    @Test func weeksInAViewStartOnMondayAndTheUndatedComeLast() {
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "Europe/London")!
        base.firstWeekday = 1
        let calendar = DateGroups.viewCalendar(base)
        // Saturday 21 November 2026 and Sunday 22 November are in the week of Monday 16; Monday 23 starts the next.
        let rows = [Self.row("sun", due: "2026-11-22"), Self.row("none", due: nil), Self.row("mon", due: "2026-11-23"),
                    Self.row("sat", due: "2026-11-21"), Self.row("bad", due: "soon")]
        let now = base.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let groups = ItemTableLayout.groups(of: rows, by: Self.dueColumn, mode: .bucket(.week), calendar: calendar, now: now)
        #expect(groups.map(\.id) == ["2026-11-16", "2026-11-23", ""])
        #expect(groups.map { $0.rows.map(\.item.id.rawValue) } == [["sun", "sat"], ["mon"], ["none", "bad"]])
        #expect(groups[0].title == String(localized: "Week of \(base.date(from: DateComponents(year: 2026, month: 11, day: 16))!.formatted(Date.FormatStyle(locale: base.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)))"))
        // A place's own weeks start where Settings says, here Sunday, which moves Sunday 22 into the next week.
        let sundays = ItemTableLayout.groups(of: rows, by: Self.dueColumn, mode: .bucket(.week), calendar: base, now: now)
        #expect(sundays.map(\.id) == ["2026-11-15", "2026-11-22", ""])

        let months = ItemTableLayout.groups(of: rows, by: Self.dueColumn, mode: .bucket(.month), calendar: calendar, now: now)
        #expect(months.map(\.id) == ["2026-11-01", ""])
        let years = ItemTableLayout.groups(of: rows, by: Self.dueColumn, mode: .bucket(.year), calendar: calendar, now: now)
        #expect(years.map(\.id) == ["2026-01-01", ""])
        let days = ItemTableLayout.groups(of: rows, by: Self.dueColumn, mode: .bucket(.day), calendar: calendar, now: now)
        #expect(days.map(\.title).prefix(3) == [String(localized: "Today"), String(localized: "Tomorrow"), days[2].title])
    }

    @Test func aPlaceKeepsADateGroupingInItsDefaultView() throws {
        var kept = PlaceDefault()
        kept.keep(ItemTableOptions(grouping: .column("field.due_at", by: .bucket(.week))))
        let data = try JSONEncoder().encode(kept)
        let read = try JSONDecoder().decode(PlaceDefault.self, from: data)
        #expect(read.grouping == .column("field.due_at", by: .bucket(.week)))
        #expect(String(data: data, encoding: .utf8)?.contains("week:field.due_at") == true)
    }

    // MARK: The board follows the sort

    @Test func aBoardsCardsFollowTheViewsSortWithinEachLane() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.task, label: "Task", fields: [Self.priority, Self.due], titleField: "title", bodyField: "body", parent: nil),
        ])
        func item(_ title: String, priority: String, due: String) -> MAPP.Item {
            MAPP.Item(id: ItemID(title), type: Self.task, title: title, titleRule: .property("title"),
                 properties: [Property(key: "priority", value: .string(priority)), Property(key: "due_at", value: .string(due))],
                 version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
        }
        let items = [item("A", priority: "high", due: "2026-12-03"), item("B", priority: "high", due: "2026-11-24"),
                     item("C", priority: "high", due: "2026-11-30")]
        let byTitle = ItemBoardLayout.lanes(items: items, key: "priority", catalogue: catalogue)
        #expect(byTitle.first { $0.id == .option("high") }?.items.map(\.id.rawValue) == ["A", "B", "C"])
        let rows = items.map { ItemTableRow(item: $0, typeLabel: "Task", typeIcon: nil, parent: nil) }
        let sorted = ItemTableLayout.sorted(rows, by: [ItemTableComparator(column: Self.dueColumn, order: .forward)])
        let order = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element.item.id, $0.offset) })
        let byDue = ItemBoardLayout.lanes(items: items, key: "priority", catalogue: catalogue, order: order)
        #expect(byDue.first { $0.id == .option("high") }?.items.map(\.id.rawValue) == ["B", "C", "A"])
    }
}
