import Foundation
import SwiftUI
import Testing
@testable import MAPP

struct ItemTableLayoutTests {
    private static let words: [StatusWord] = [
        .init(value: "pending", group: .notStarted), .init(value: "someday", group: .notStarted),
        .init(value: "in_progress", group: .inProgress), .init(value: "blocked", group: .inProgress),
        .init(value: "completed", group: .completed), .init(value: "canceled", group: .canceled),
    ]
    private static let statuses = ItemTypeInfo.Field(key: "status", label: "Status", kind: .status(words), declaredBy: TypeID("core.task"))
    private static let priorities = ItemTypeInfo.Field(
        key: "priority", label: "Priority", kind: .choice(["low", "medium", "high", "urgent"]), declaredBy: TypeID("core.task"))

    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: TypeID("core.task"), label: "Task", fields: [], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(
            id: TypeID("aic.ticket.task"), label: "Ticket Task",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("core.task")),
                .init(key: "body", label: "Body", kind: .text, declaredBy: TypeID("core.task")),
                .init(key: "description", label: "Description", kind: .text, declaredBy: TypeID("core.task")),
                statuses, priorities,
                .init(key: "notes", label: "Notes", kind: .text, declaredBy: TypeID("core.task")),
            ],
            titleField: "title", bodyField: "body", parent: TypeID("core.task")),
        ItemTypeInfo(
            id: TypeID("core.note"), label: "Note",
            fields: [.init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("core.note"))],
            titleField: "title", bodyField: nil, parent: nil),
    ])

    private static func row(
        _ title: String, type: String = "aic.ticket.task", status: String? = nil, priority: String? = nil,
        notes: String? = nil, parent: String? = nil, modified: Date = .now
    ) -> ItemTableRow {
        var properties: [Property] = [Property(key: "title", value: .string(title))]
        if let status { properties.append(Property(key: "status", value: .string(status))) }
        if let priority { properties.append(Property(key: "priority", value: .string(priority))) }
        if let notes { properties.append(Property(key: "notes", value: .string(notes))) }
        let item = Item(
            id: ItemID(title), type: TypeID(type), title: title, titleRule: .property("title"), properties: properties,
            version: ItemVersion(1), created: modified, modified: modified)
        func link(_ title: String?) -> RelatedItem? { title.map { .init(id: ItemID($0), title: $0, icon: "folder") } }
        return ItemTableRow(item: item, typeLabel: type, typeIcon: nil, parent: link(parent))
    }

    /// What the ticket's look shows beyond its status: its priority and when it was edited.
    private static let ticketLook = TypeLook(date: .edited, secondary: [], facts: [.field("priority")])

    private static func columns(_ rows: [ItemTableRow], looks: [TypeID: TypeLook]? = nil) -> [ItemTableColumn] {
        ItemTableLayout.columns(
            for: rows, catalogue: catalogue, hidden: [], looks: looks ?? [TypeID("aic.ticket.task"): ticketLook])
    }

    // MARK: What the header may change

    @MainActor
    @Test func theNameCanNeverBeHiddenOrMovedAndAnyOtherColumnCan() {
        #expect(ItemTable.disabledCustomization(of: .edited) == [])
        // The name keeps both, since one call sets the whole set.
        #expect(ItemTable.disabledCustomization(of: .title) == [.visibility, .reorder])
    }

    @Test func aHeaderDragReadsTheColumnOrderAndAResizeDoesNot() throws {
        let dragged = Data(
            #"{"perColumnState":[],"columnOrder":[{"base":{"explicit":{"_0":"edited"}}},{"base":{"explicit":{"_0":"type"}}}]}"#
                .utf8)
        let customization = try JSONDecoder().decode(TableColumnCustomization<ItemTableRow>.self, from: dragged)
        #expect(ItemTable.headerOrder(in: try JSONEncoder().encode(customization)) == ["edited", "type"])
        let resized = try JSONDecoder().decode(
            TableColumnCustomization<ItemTableRow>.self, from: Data(#"{"perColumnState":[]}"#.utf8))
        #expect(ItemTable.headerOrder(in: try JSONEncoder().encode(resized)) == nil)
    }

    // MARK: Statuses

    @Test(arguments: [
        ("in_progress", StatusBucket.group(.inProgress)), ("blocked", .group(.inProgress)), ("pending", .group(.notStarted)),
        ("someday", .group(.notStarted)), ("completed", .group(.completed)), ("canceled", .group(.canceled)),
        ("Done", .other), ("tentative", .other),
    ])
    func aStatusReadsByTheGroupItsTypeDeclares(status: String, bucket: StatusBucket) throws {
        let column = try #require(Self.columns([Self.row("A", status: status)]).first { $0.id == "field.status" })
        #expect(column.statusBucket(of: status) == bucket)
    }

    // MARK: Columns

    @Test func aTypesLookLeadsAfterTheNameWithTheStatusAndTheRestWaitsInOrder() {
        let rows = [Self.row("A", status: "pending", priority: "low", parent: "P")]
        let ids = Self.columns(rows).map(\.id)
        #expect(ids == [
            "title", "field.status", "field.priority", "edited", "parent", "children", "collections", "field.description", "field.notes", "created", "occurred", "tags",
        ])
    }

    @Test func aTableOfSeveralTypesNamesEachRowsType() {
        let ids = Self.columns([Self.row("A"), Self.row("B", type: "core.note")]).map(\.id)
        #expect(ids.prefix(2) == ["title", "type"])
    }

    @Test func whatTheLookDoesNotShowStartsHidden() {
        let columns = Self.columns([Self.row("A", status: "pending", notes: "Some notes")])
        let shown = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.isShownByDefault) })
        #expect(shown["field.status"] == true)
        #expect(shown["field.priority"] == false, "the look shows it, but no row has one")
        #expect(shown["field.notes"] == false)
        #expect(shown["created"] == false)
        let bare = Self.columns([Self.row("A", status: "pending", notes: "Some notes")], looks: [:])
        #expect(bare.filter(\.isShownByDefault).map(\.id) == ["title", "field.status"])
    }

    @Test func theParentColumnWaitsBehindViewOptionsWhereverItemsAreFiled() {
        let filed = Self.columns([Self.row("A", parent: "Epic")])
        #expect(filed.first { $0.id == "parent" }?.isShownByDefault == false)
        #expect(!filed.contains { $0.id == "collection" })
        #expect(Self.columns([Self.row("A")]).contains { $0.id == "parent" })
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

    @Test func aPlaceThatKeepsItsOrderStartsUnsorted() throws {
        let rows = [Self.row("B", priority: "low"), Self.row("A", priority: "urgent")]
        let columns = Self.columns(rows)
        #expect(ItemTableLayout.sort(ItemTableOptions(), columns: columns, keepsGivenOrder: true).isEmpty)
        #expect(ItemTableLayout.sorted(rows, by: []).map(\.item.title) == ["B", "A"])
        // A sort the person chooses still applies.
        var options = ItemTableOptions()
        options.sort = [ItemTableComparator(column: try #require(columns.first { $0.id == "title" }))]
        #expect(ItemTableLayout.sort(options, columns: columns, keepsGivenOrder: true).map(\.column.id) == ["title"])
    }

    @Test func aStoredSortOnAColumnThePlaceLacksIsDropped() {
        let gone = ItemTableColumn(id: "field.gone", label: "Gone", content: .title, style: .text)
        var options = ItemTableOptions()
        options.sort = [ItemTableComparator(column: gone)]
        let sort = ItemTableLayout.sort(options, columns: Self.columns([Self.row("A")]))
        #expect(!sort.contains { $0.column.id == "field.gone" })
    }

    // MARK: Groups and filters

    @Test func statusGroupsRunFromNotStartedToFinishedWithTheEmptyLast() throws {
        let rows = [
            Self.row("A", status: "completed"), Self.row("B", status: "pending"), Self.row("C"),
            Self.row("D", status: "in_progress"), Self.row("E", status: "someday"), Self.row("F", status: "canceled"),
            Self.row("G", status: "blocked"),
        ]
        let status = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let groups = ItemTableLayout.groups(of: rows, by: status, mode: .statusGroups)
        #expect(groups.map(\.id) == ["not_started", "in_progress", "completed", "canceled", ""])
        #expect(groups.map(\.title) == ["Not Started", "In Progress", "Completed", "Canceled", "No Status"])
        #expect(groups.first?.rows.map(\.item.title) == ["B", "E"])
        #expect(ItemTableLayout.collapsed(ItemTableOptions(), groups: groups, by: status) == ["completed", "canceled"])
    }

    @Test func aWordTheTypeDoesNotDeclareFallsInOtherAfterTheGroups() throws {
        let rows = [Self.row("A", status: "mystery"), Self.row("B", status: "completed"), Self.row("C", status: "pending")]
        let status = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let groups = ItemTableLayout.groups(of: rows, by: status, mode: .statusGroups)
        #expect(groups.map(\.id) == ["not_started", "completed", "other"])
        #expect(groups.last?.title == "Other")
        #expect(groups.last?.rows.map(\.item.title) == ["A"])
        #expect(!ItemTableLayout.collapsed(ItemTableOptions(), groups: groups, by: status).contains("other"))
    }

    @Test func aTypeWithNoStatusFieldHasNoStatusColumn() {
        let columns = Self.columns([Self.row("A", type: "core.note")])
        #expect(!columns.contains { $0.style == .status })
        #expect(ItemTableLayout.grouping(ItemTableOptions(), columns: columns) == nil)
    }

    @Test func anEventsStatusIsAPlainChoiceWithNoGroups() throws {
        let words = ItemTypeInfo.Field(key: "status", label: "Status", kind: .choice(["tentative", "confirmed", "canceled"]), declaredBy: TypeID("core.event"))
        let event = ItemTypeInfo(id: TypeID("core.event"), label: "Event", fields: [words], titleField: "title", bodyField: nil, parent: nil)
        let catalogue = Catalogue(itemTypes: [event])
        #expect(event.statusField == nil)
        #expect(ItemTableLayout.style(of: words, in: event.id, catalogue: catalogue) == .choice)
        let item = Item(
            id: ItemID("e"), type: event.id, title: "e", titleRule: .property("title"),
            properties: [Property(key: "status", value: .string("canceled"))], version: ItemVersion(1), created: .now, modified: .now)
        #expect(catalogue.statusGroup(of: item) == nil, "a choice has no groups, so a canceled event is not folded away")
        let row = ItemTableRow(item: item, typeLabel: "Event", typeIcon: nil, parent: nil)
        let columns = ItemTableLayout.columns(for: [row], catalogue: catalogue, hidden: [], looks: [:])
        let status = try #require(columns.first { $0.id == "field.status" })
        #expect(ItemTableLayout.collapsed(ItemTableOptions(), groups: ItemTableLayout.groups(of: [row], by: status, mode: .value), by: status).isEmpty)
    }

    @Test func aFieldNamedStatusThatIsNotOfTheStatusKindIsNotOne() {
        let plain = ItemTypeInfo.Field(key: "status", label: "Status", kind: .text, declaredBy: TypeID("test.thing"))
        let type = ItemTypeInfo(id: TypeID("test.thing"), label: "Thing", fields: [plain], titleField: "title", bodyField: nil, parent: nil)
        let catalogue = Catalogue(itemTypes: [type])
        #expect(type.statusField == nil)
        #expect(ItemTableLayout.style(of: plain, in: type.id, catalogue: catalogue) == .text)
    }

    @Test func aPriorityFieldIsPriorityOnlyOnATask() {
        let choice = ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: TypeID("test.thing"))
        #expect(ItemTableLayout.style(of: choice, in: TypeID("aic.ticket.task"), catalogue: Self.catalogue) == .priority)
        #expect(ItemTableLayout.style(of: choice, in: TypeID("core.note"), catalogue: Self.catalogue) == .choice)
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
}
