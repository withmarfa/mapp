import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

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

    // MARK: Sorting

    @Test func aStoredSortOnAColumnThePlaceLacksIsDropped() {
        let gone = ItemTableColumn(id: "field.gone", label: "Gone", content: .title, style: .text)
        var options = ItemTableOptions()
        options.sort = [ItemTableComparator(column: gone)]
        let sort = ItemTableLayout.sort(options, columns: Self.columns([Self.row("A")]))
        #expect(!sort.contains { $0.column.id == "field.gone" })
    }
}
