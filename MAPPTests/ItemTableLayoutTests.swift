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
        func link(_ title: String?) -> ItemTableRow.Link? { title.map { .init(id: ItemID($0), title: $0, icon: "folder") } }
        return ItemTableRow(item: item, typeLabel: type, typeIcon: nil, parent: link(parent))
    }

    private static func columns(_ rows: [ItemTableRow]) -> [ItemTableColumn] {
        ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [])
    }

    // MARK: What the header may change

    @MainActor
    @Test func theNameCanNeverBeHiddenAndAViewsOrderIsNotTheHeadersToChange() {
        let name = ItemTableColumn.title
        let other = ItemTableColumn.edited
        #expect(ItemTable.disabledCustomization(of: name, inView: false) == .visibility)
        #expect(ItemTable.disabledCustomization(of: other, inView: false) == [])
        #expect(ItemTable.disabledCustomization(of: other, inView: true) == .reorder)
        // In a view the name keeps both, since one call sets the whole set.
        #expect(ItemTable.disabledCustomization(of: name, inView: true) == [.visibility, .reorder])
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

    @Test func aTypesFieldsFollowTheNameLeadingWithStatusAndPriority() {
        let rows = [Self.row("A", status: "pending", priority: "low", parent: "P")]
        let ids = Self.columns(rows).map(\.id)
        #expect(ids == ["title", "field.status", "field.priority", "parent", "field.notes", "field.description", "edited", "created"])
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

    @Test func theParentColumnShowsWhereItemsAreFiled() {
        let filed = Self.columns([Self.row("A", parent: "Epic")])
        #expect(filed.first { $0.id == "parent" }?.isShownByDefault == true)
        let loose = Self.columns([Self.row("A")])
        #expect(loose.first { $0.id == "parent" }?.isShownByDefault == false)
        #expect(!Self.columns([Self.row("A", parent: "Epic")]).contains { $0.id == "collection" })
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

    @Test func statusGroupsRunFromWorkUnderWayToWorkFinishedWithTheEmptyLast() throws {
        let rows = [
            Self.row("A", status: "completed"), Self.row("B", status: "pending"), Self.row("C"),
            Self.row("D", status: "in_progress"), Self.row("E", status: "someday"), Self.row("F", status: "canceled"),
            Self.row("G", status: "blocked"),
        ]
        let status = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let groups = ItemTableLayout.groups(of: rows, by: status)
        #expect(groups.map(\.id) == ["in_progress", "not_started", "completed", "canceled", ""])
        #expect(groups.map(\.title) == ["In Progress", "Not Started", "Completed", "Canceled", "No Status"])
        #expect(groups.first?.rows.map(\.item.title) == ["D", "G"])
        #expect(ItemTableLayout.collapsed(ItemTableOptions(), groups: groups, by: status) == ["completed", "canceled"])
    }

    @Test func aWordTheTypeDoesNotDeclareFallsInOtherAfterTheGroups() throws {
        let rows = [Self.row("A", status: "mystery"), Self.row("B", status: "completed"), Self.row("C", status: "pending")]
        let status = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let groups = ItemTableLayout.groups(of: rows, by: status)
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
        let columns = ItemTableLayout.columns(for: [row], catalogue: catalogue, hidden: [])
        let status = try #require(columns.first { $0.id == "field.status" })
        #expect(ItemTableLayout.collapsed(ItemTableOptions(), groups: ItemTableLayout.groups(of: [row], by: status), by: status).isEmpty)
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

    @Test func aFilterKeepsTheValuesChosenAndTheEmptyStringKeepsEmptyCells() {
        let rows = [Self.row("A", status: "pending"), Self.row("B", status: "completed"), Self.row("C")]
        let columns = Self.columns(rows)
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending"]], columns: columns).map(\.item.title) == ["A"])
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending", ""]], columns: columns).map(\.item.title) == ["A", "C"])
    }

    @Test func isNotKeepsTheRowsOutsideTheValuesAndDropsEmptyCellsOfAProperty() {
        let rows = [Self.row("A", status: "pending"), Self.row("B", status: "completed"), Self.row("C")]
        let columns = Self.columns(rows)
        // Marfa's `neq` on a property is false where the property is absent, so the empty cell goes too.
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending"]], negated: ["field.status"], columns: columns).map(\.item.title)
            == ["B"])
        #expect(ItemTableLayout.filter(rows, by: ["field.status": ["pending", "completed"]], negated: ["field.status"], columns: columns).isEmpty)
        // Excluding the empty cell keeps every row that has a value.
        #expect(ItemTableLayout.filter(rows, by: ["field.status": [""]], negated: ["field.status"], columns: columns).map(\.item.title)
            == ["A", "B"])
        // A column left in `negated` with no filter filters nothing.
        #expect(ItemTableLayout.filter(rows, by: [:], negated: ["field.status"], columns: columns).count == 3)
    }

    @Test func isNotOnTheParentKeepsRowsWithoutOne() {
        let rows = [Self.row("A", parent: "P"), Self.row("B", parent: "Q"), Self.row("C")]
        let columns = Self.columns(rows)
        #expect(ItemTableLayout.filter(rows, by: ["parent": ["P"]], negated: ["parent"], columns: columns).map(\.item.title) == ["B", "C"])
        #expect(ItemTableLayout.filter(rows, by: ["parent": ["P", ""]], negated: ["parent"], columns: columns).map(\.item.title) == ["B"])
    }

    @Test func optionsKeepIsNotWithTheFilterAndForgetItWithIt() {
        var options = ItemTableOptions()
        options.setFilter("field.status", values: ["a"], negated: true)
        #expect(options.isNegated("field.status"))
        #expect(options.filterChoices == ["field.status": FilterChoice(values: ["a"], isNegated: true)])
        options.setFilter("field.status", values: [])
        #expect(!options.isFiltering)
        #expect(options.negated.isEmpty)
        options.setFilter("field.status", values: ["a"], negated: true)
        options.setFilter("field.done", values: ["true"])
        options.clearFilters()
        #expect(!options.isFiltering && options.negated.isEmpty)
    }

    @Test func aFilterOffersTheValuesItKeepsWhereNoRowHoldsThem() throws {
        // A view's own filter took out every row holding "blocked", and the window's chip keeps it.
        let rows = [Self.row("A", status: "pending"), Self.row("B", status: "pending")]
        let column = try #require(Self.columns(rows).first { $0.id == "field.status" })
        let offered = ItemTableLayout.offered(in: rows, by: column, keeping: ["blocked"])
        let blocked = try #require(offered.first { $0.id == "blocked" })
        #expect(blocked.rows.isEmpty)
        #expect(blocked.title == column.label(ofCategory: "blocked", in: rows))
        #expect(!blocked.title.isEmpty)
    }

    @Test func aChoiceOrStatusColumnOffersEveryOptionItsCatalogueDeclares() throws {
        let rows = [Self.row("A", status: "pending", priority: "high")]
        let columns = Self.columns(rows)
        let status = try #require(columns.first { $0.id == "field.status" })
        let priority = try #require(columns.first { $0.id == "field.priority" })
        let statuses = ItemTableLayout.offered(in: rows, by: status, keeping: []).map(\.id)
        #expect(Set(statuses) == Set(Self.words.map(\.value)))
        #expect(Set(ItemTableLayout.offered(in: rows, by: priority, keeping: []).map(\.id)) == ["low", "medium", "high", "urgent"])
        // Those no row holds are counted as none.
        #expect(ItemTableLayout.offered(in: rows, by: priority, keeping: []).first { $0.id == "low" }?.rows.isEmpty == true)
        #expect(ItemTableLayout.offered(in: rows, by: priority, keeping: []).first { $0.id == "high" }?.rows.count == 1)
    }

    @Test func aTextColumnOffersOnlyWhatRowsHoldAndWhatIsKept() throws {
        let rows = [Self.row("A", notes: "x")]
        let column = try #require(Self.columns(rows).first { $0.id == "field.notes" })
        #expect(Set(ItemTableLayout.offered(in: rows, by: column, keeping: []).map(\.id)) == ["x"])
        #expect(Set(ItemTableLayout.offered(in: rows, by: column, keeping: ["y"]).map(\.id)) == ["x", "y"])
    }
}
