import Foundation
import Testing
@testable import MAPP

struct ItemTableLayoutTests {
    private static let statuses = ItemTypeInfo.Field(
        key: "status", label: "Status", kind: .text, declaredBy: TypeID("core.task"),
        description: "Recommended values: pending, in_progress, completed, canceled")
    private static let priorities = ItemTypeInfo.Field(
        key: "priority", label: "Priority", kind: .choice(["low", "medium", "high", "urgent"]), declaredBy: TypeID("core.task"))

    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(
            id: TypeID("aic.ticket.task"), label: "Task",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("core.task")),
                .init(key: "body", label: "Body", kind: .text, declaredBy: TypeID("core.task")),
                .init(key: "description", label: "Description", kind: .text, declaredBy: TypeID("core.task")),
                statuses, priorities,
                .init(key: "notes", label: "Notes", kind: .text, declaredBy: TypeID("core.task")),
            ],
            titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(
            id: TypeID("core.note"), label: "Note",
            fields: [.init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("core.note"))],
            titleField: "title", bodyField: nil, parent: nil),
    ])

    private static func row(
        _ title: String, type: String = "aic.ticket.task", status: String? = nil, priority: String? = nil,
        notes: String? = nil, parent: String? = nil, collection: String? = nil, modified: Date = .now
    ) -> ItemTableRow {
        var properties: [Property] = [Property(key: "title", value: .string(title))]
        if let status { properties.append(Property(key: "status", value: .string(status))) }
        if let priority { properties.append(Property(key: "priority", value: .string(priority))) }
        if let notes { properties.append(Property(key: "notes", value: .string(notes))) }
        let item = Item(
            id: ItemID(title), type: TypeID(type), title: title, titleRule: .property("title"), properties: properties,
            version: ItemVersion(1), created: modified, modified: modified)
        func link(_ title: String?) -> ItemTableRow.Link? { title.map { .init(id: ItemID($0), title: $0, symbol: "folder") } }
        return ItemTableRow(item: item, typeLabel: type, typeSymbol: "doc", parent: link(parent), collection: link(collection))
    }

    private static func columns(_ rows: [ItemTableRow], place: SidebarItem = .allNotes) -> [ItemTableColumn] {
        ItemTableLayout.columns(for: rows, catalogue: catalogue, place: place, hidden: [])
    }

    // MARK: Statuses

    @Test(arguments: [
        ("in_progress", StatusTone.active), ("blocked", .waiting), ("pending", .planned), ("someday", .later),
        ("completed", .done), ("canceled", .canceled), ("Done", .done), ("tentative", .other),
    ])
    func aStatusReadsByItsTone(status: String, tone: StatusTone) {
        #expect(StatusTone(status) == tone)
    }

    @Test func theRingFollowsTheTone() {
        #expect(PageHeader.Mark(status: "done") == PageHeader.Mark(tone: .green, fill: .full))
        #expect(PageHeader.Mark(status: "someday") == PageHeader.Mark(tone: .neutral, fill: .none))
        #expect(PageHeader.Mark(status: nil) == PageHeader.Mark(tone: .neutral, fill: .none))
    }

    // MARK: Columns

    @Test func aTypesFieldsFollowTheNameLeadingWithStatusAndPriority() {
        let rows = [Self.row("A", status: "pending", priority: "low", collection: "P")]
        let ids = Self.columns(rows).map(\.id)
        #expect(ids == ["title", "field.status", "field.priority", "parent", "collection", "field.notes", "field.description", "edited", "created"])
    }

    @Test func theTitleAndTextAreNotColumns() {
        let ids = Self.columns([Self.row("A")]).map(\.id)
        #expect(!ids.contains("field.title"))
        #expect(!ids.contains("field.body"))
    }

    @Test func aTableOfSeveralTypesNamesEachRowsType() {
        let ids = Self.columns([Self.row("A"), Self.row("B", type: "core.note")]).map(\.id)
        #expect(ids.prefix(2) == ["title", "type"])
    }

    @Test func quietFieldsAndEmptyOnesStartHidden() {
        let columns = Self.columns([Self.row("A", status: "pending", notes: "Some notes")])
        let shown = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.isShownByDefault) })
        #expect(shown["field.status"] == true)
        #expect(shown["field.priority"] == false)
        #expect(shown["field.notes"] == false)
        #expect(shown["created"] == false)
    }

    @Test func aParentThatIsTheCollectionStartsHidden() {
        let filed = Self.columns([Self.row("A", parent: "P", collection: "P")])
        #expect(filed.first { $0.id == "parent" }?.isShownByDefault == false)
        let underEpic = Self.columns([Self.row("A", parent: "Epic", collection: "P")])
        #expect(underEpic.first { $0.id == "parent" }?.isShownByDefault == true)
    }

    @Test func aCollectionsTableHasNoCollectionColumn() {
        let ids = Self.columns([Self.row("A", collection: "P")], place: .collection(ItemID("P"))).map(\.id)
        #expect(!ids.contains("collection"))
    }

    // MARK: Sorting

    @Test func emptyCellsGoLastWhicheverWayAColumnSorts() throws {
        let rows = [Self.row("None"), Self.row("Low", priority: "low"), Self.row("Urgent", priority: "urgent")]
        let priority = try #require(Self.columns(rows).first { $0.id == "field.priority" })
        let highest = ItemTableLayout.sorted(rows, by: [ItemTableComparator(column: priority, order: .reverse)])
        #expect(highest.map(\.item.title) == ["Urgent", "Low", "None"])
        let lowest = ItemTableLayout.sorted(rows, by: [ItemTableComparator(column: priority, order: .forward)])
        #expect(lowest.map(\.item.title) == ["Low", "Urgent", "None"])
    }

    @Test func aPlaceStartsWithTheMostPressingFirst() {
        let rows = [Self.row("A", priority: "low")]
        let sort = ItemTableLayout.sort(ItemTableOptions(), columns: Self.columns(rows))
        #expect(sort.map(\.column.id) == ["field.priority", "edited"])
        #expect(sort.map(\.order) == [.reverse, .reverse])
    }

    @Test func aStoredSortOnAColumnThePlaceLacksIsDropped() {
        let gone = ItemTableColumn(id: "field.gone", label: "Gone", content: .title, style: .text)
        var options = ItemTableOptions()
        options.sort = [ItemTableComparator(column: gone)]
        let sort = ItemTableLayout.sort(options, columns: Self.columns([Self.row("A")]))
        #expect(!sort.contains { $0.column.id == "field.gone" })
    }

    // MARK: Groups and filters

    @Test func statusGroupsRunFromWorkUnderWayToWorkFinishedWithTheEmptyLast() throws {
        let rows = [
            Self.row("A", status: "completed"), Self.row("B", status: "pending"), Self.row("C"),
            Self.row("D", status: "in_progress"), Self.row("E", status: "someday"),
        ]
        let status = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let groups = ItemTableLayout.groups(of: rows, by: status)
        #expect(groups.map(\.id) == ["in_progress", "pending", "someday", "completed", ""])
        #expect(groups.map(\.title) == ["In Progress", "Pending", "Someday", "Completed", "No Status"])
        #expect(ItemTableLayout.collapsed(ItemTableOptions(), groups: groups, by: status) == ["completed"])
    }

    @Test func aPlaceIsGroupedByStatusOnlyWhereItsItemsHaveOne() {
        let tasks = [Self.row("A", status: "pending")]
        #expect(ItemTableLayout.grouping(ItemTableOptions(), columns: Self.columns(tasks))?.id == "field.status")
        let unset = [Self.row("A"), Self.row("B")]
        #expect(ItemTableLayout.grouping(ItemTableOptions(), columns: Self.columns(unset)) == nil)
        var none = ItemTableOptions()
        none.grouping = .none
        #expect(ItemTableLayout.grouping(none, columns: Self.columns(tasks)) == nil)
    }

    @Test func aFilterKeepsTheValuesChosenAndTheEmptyStringKeepsEmptyCells() {
        let rows = [Self.row("A", status: "pending"), Self.row("B", status: "completed"), Self.row("C")]
        let columns = Self.columns(rows)
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending"]], columns: columns).map(\.item.title) == ["A"])
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending", ""]], columns: columns).map(\.item.title) == ["A", "C"])
    }

    // MARK: Dates

    @Test func datesAreReadAsDaysOrMoments() throws {
        #expect(ItemTableValue.date("2026-10-23") != nil)
        #expect(ItemTableValue.date("2026-10-23T09:30:00Z") != nil)
        #expect(ItemTableValue.date("2026-10-23T09:30:00.250Z") != nil)
        #expect(ItemTableValue.date("next week") == nil)
    }

    @Test func aDayReadsAsPeopleSayIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        let locale = Locale(identifier: "en_GB")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)))
        func label(_ days: Int) -> String {
            ItemTableDate.label(for: calendar.date(byAdding: .day, value: days, to: now)!, now: now, calendar: calendar, locale: locale)
        }
        #expect(label(0) == "Today")
        #expect(label(1) == "Tomorrow")
        #expect(label(-1) == "Yesterday")
        #expect(label(-3) == "Tuesday")
        // The month's abbreviation is the locale's own, so only what the label must hold is checked.
        #expect(label(-30).hasPrefix("23 Sep") && !label(-30).contains("2026"))
        #expect(label(-400).hasSuffix("2025"))
    }
}
