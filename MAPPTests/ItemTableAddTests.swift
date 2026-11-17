import Foundation
import Testing
@testable import MAPP

/// Which empty cells of the table offer to take a first value, and in which panel.
@MainActor
struct ItemTableAddTests {
    private static let task = TypeID("core.task")
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(
            id: task, label: "Task",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: task),
                .init(key: "status", label: "Status", kind: .status([.init(value: "pending", group: .notStarted)]), declaredBy: task),
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

    @Test func anEmptyCellOfAPanelValueOffersItsPanel() {
        let row = Self.row()
        #expect(Self.column("due", .date).addKind(for: row, catalogue: Self.catalogue) == .date(Self.catalogue.itemTypes[Self.task]!.fields[3]))
        #expect(Self.column("labels", .text).addKind(for: row, catalogue: Self.catalogue) != nil)
        #expect(Self.column("estimate", .number).addKind(for: row, catalogue: Self.catalogue) != nil)
    }

    @Test func aCellThatHoldsAValueOffersNone() {
        let row = Self.row([Property(key: "due", value: .string("2026-11-17"))])
        #expect(Self.column("due", .date).addKind(for: row, catalogue: Self.catalogue) == nil)
    }

    @Test func aPickedOrSwitchedValueIsEditedInPlaceNotInAPanel() {
        let row = Self.row()
        for (key, style) in [("status", ItemTableColumn.Style.status), ("priority", .priority), ("done", .boolean)] {
            #expect(Self.column(key, style).addKind(for: row, catalogue: Self.catalogue) == nil)
        }
    }

    @Test func noPanelOpensForAnItemThatCannotBeChangedOrWhoseTypeLacksTheField() {
        let due = Self.column("due", .date)
        #expect(due.addKind(for: Self.row(readOnly: true), catalogue: Self.catalogue) == nil)
        #expect(due.addKind(for: Self.row(type: TypeID("core.note")), catalogue: Self.catalogue) == nil)
        #expect(ItemTableColumn.edited.addKind(for: Self.row(), catalogue: Self.catalogue) == nil)
    }
}
