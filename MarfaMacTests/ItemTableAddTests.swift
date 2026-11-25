import Foundation
import Testing
@testable import MarfaMac

/// Which empty cells of the table offer to take a first value, and in which panel.
@MainActor
struct ItemTableAddTests {
    private static let task = TypeID("core.task")
    private static let issue = TypeID("core.issue")
    private static let people = ListShape(members: [
        .init(key: "name", label: "Name", kind: .text(nil)),
        .init(key: "email", label: "Email", kind: .text(.email)),
    ])
    private static let catalogue = Catalogue(itemTypes: [
        // A second type that gives the keys of the first different kinds, as a merged column meets them.
        ItemTypeInfo(
            id: issue, label: "Issue",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: issue),
                .init(key: "status", label: "Status", kind: .text, declaredBy: issue),
                .init(key: "priority", label: "Priority", kind: .number, declaredBy: issue),
                .init(key: "done", label: "Done", kind: .text, declaredBy: issue),
                .init(key: "assignees", label: "Assignees", kind: .list(people), declaredBy: issue),
            ],
            titleField: "title", bodyField: nil, parent: nil),
        ItemTypeInfo(
            id: task, label: "Task",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: task),
                .init(key: "status", label: "Status", kind: .status([.init(value: "not_started", group: .notStarted)]), declaredBy: task),
                .init(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task),
                .init(key: "due", label: "Due", kind: .date(includesTime: false), declaredBy: task),
                .init(key: "labels", label: "Labels", kind: .words, declaredBy: task),
                .init(key: "estimate", label: "Estimate", kind: .number, declaredBy: task),
                .init(key: "done", label: "Done", kind: .boolean, declaredBy: task),
            ],
            titleField: "title", bodyField: nil, parent: nil),
        ItemTypeInfo(
            id: TypeID("core.note"), label: "Note",
            fields: [.init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("core.note"))],
            titleField: "title", bodyField: nil, parent: nil),
    ])

    private static func row(type: TypeID = task, readOnly: Bool = false, _ properties: [Property] = []) -> ItemTableRow {
        var item = Item(
            id: ItemID("one"), type: type, title: "One", titleRule: .property("title"),
            properties: [Property(key: "title", value: .string("One"))] + properties,
            version: ItemVersion(1), created: .now, modified: .now)
        item.readOnly = readOnly
        return ItemTableRow(item: item, typeLabel: "Task", typeIcon: nil, parent: nil)
    }

    private static func column(_ key: String, _ style: ItemTableColumn.Style) -> ItemTableColumn {
        let field = catalogue.itemTypes[task]!.fields.first { $0.key == key }!
        return ItemTableColumn(id: "field." + key, label: field.label, content: .field(field), style: style)
    }

    @Test func aCellThatHoldsAValueOffersNone() {
        let row = Self.row([Property(key: "due", value: .string("2026-11-17"))])
        #expect(Self.column("due", .date).addKind(for: row, catalogue: Self.catalogue) == nil)
    }

    @Test func noPanelOpensForAnItemThatCannotBeChangedOrWhoseTypeLacksTheField() {
        let due = Self.column("due", .date)
        #expect(due.addKind(for: Self.row(readOnly: true), catalogue: Self.catalogue) == nil)
        #expect(due.addKind(for: Self.row(type: TypeID("core.note")), catalogue: Self.catalogue) == nil)
        #expect(ItemTableColumn.edited.addKind(for: Self.row(), catalogue: Self.catalogue) == nil)
    }

    @Test func theRowsOwnFieldKindDecidesNotTheMergedColumnsStyle() {
        let status = Self.column("status", .status)
        let priority = Self.column("priority", .priority)
        let done = Self.column("done", .boolean)
        let issueRow = Self.row(type: Self.issue)
        // The issue's status, priority and done are plain text, a number and text: each opens a panel.
        #expect(status.addKind(for: issueRow, catalogue: Self.catalogue) != nil)
        #expect(priority.addKind(for: issueRow, catalogue: Self.catalogue) != nil)
        #expect(done.addKind(for: issueRow, catalogue: Self.catalogue) != nil)
        // The task's own are picked or switched in place.
        let taskRow = Self.row()
        for column in [status, priority, done] { #expect(column.addKind(for: taskRow, catalogue: Self.catalogue) == nil) }
        #expect(!status.picksFrom(Self.catalogue.itemTypes[Self.issue]!.fields[1]))
        #expect(status.picksFrom(Self.catalogue.itemTypes[Self.task]!.fields[1]))
    }

    @Test func aColumnStyledAsTextStillLeavesAPickedFieldToItsMenu() {
        let labels = Self.column("labels", .text)
        let priorityAsText = ItemTableColumn(
            id: "field.priority", label: "Priority", content: .field(Self.catalogue.itemTypes[Self.task]!.fields[2]), style: .text)
        #expect(labels.addKind(for: Self.row(), catalogue: Self.catalogue) != nil)
        #expect(priorityAsText.addKind(for: Self.row(), catalogue: Self.catalogue) == nil)
    }

    @Test func anEmptyListOfPeopleOffersThePeoplePanelAndOneWithAPersonDoesNot() throws {
        let field = try #require(Self.catalogue.itemTypes[Self.issue]!.fields.first { $0.key == "assignees" })
        let column = ItemTableColumn(id: "field.assignees", label: "Assignees", content: .field(field), style: .text)
        let none = Self.row(type: Self.issue)
        let empty = Self.row(type: Self.issue, [Property(key: "assignees", value: .array([]))])
        let one = Self.row(type: Self.issue, [Property(key: "assignees", value: .array([.object(["name": .string("Ada")])]))])
        #expect(column.addKind(for: none, catalogue: Self.catalogue) == .people(field, Self.people))
        #expect(column.addKind(for: empty, catalogue: Self.catalogue) == .people(field, Self.people))
        #expect(column.addKind(for: one, catalogue: Self.catalogue) == nil)
    }
}
