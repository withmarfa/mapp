import Foundation
import Marfa
import Testing
@testable import MarfaMac

extension PropertyRow {
    /// The property block as a type with a status would show it beside its default pins: the type, source and last edit
    /// are the pins' (or not asked for), so the rows are the type's own fields, parent, relationships and tags.
    static func rows(
        of item: MarfaMac.Item, type: ItemTypeInfo?, hidden: Set<String>, relationships: [ItemRelationship], parentField: String, format: DateFormat,
        tags: [String], placement: PagePlacement = .standard, icon: (ItemID) -> String? = { _ in nil },
        isPerson: (ItemID) -> Bool = { _ in false }
    ) -> [PropertyRow] {
        block(
            candidates(
                of: item, type: type, hidden: hidden, relationships: relationships, parentField: parentField, format: format, tags: tags,
                typeLabel: nil, typeIcon: nil, sourceName: nil, now: .now, calendar: .current, locale: .current, icon: icon, isPerson: isPerson),
            placement: placement, excluding: [PagePlacement.updated])
    }
}

struct PropertyRowTests {
    private static func field(_ name: String, _ type: String = "string", label: String? = nil, description: String? = nil, definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, label: label, type: type, description: description, declaredBy: "aic.ticket", definition: definition)
    }

    private static let ticket = MarfaMapping.type(TypeID(ItemType(
        id: "aic.ticket", label: "Ticket",
        fields: [
            field("title"), field("body"),
            field("status", "status", definition: ["status_values": [["value": "pending", "group": "not_started"], ["value": "in_progress", "group": "in_progress"]]]),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]]),
            field("due_at", "datetime", label: "Deadline"), field("done", "boolean"), field("estimate", "integer"),
            field("link", "url"), field("contact", "email"), field("summary"), field("empty")
        ],
        titleField: "title", bodyField: "body")))

    private static func item(_ properties: [String: PropertyValue]) -> MarfaMac.Item {
        MarfaMac.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("aic.ticket"), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: .now, modified: .now)
    }

    private static func rows(
        _ properties: [String: PropertyValue], relationships: [ItemRelationship] = [], tags: [String] = [],
        hidden: Set<String> = ["title", "body"]
    ) -> [PropertyRow] {
        PropertyRow.rows(
            of: item(properties), type: ticket, hidden: hidden, relationships: relationships, parentField: "child-of", format: .standard, tags: tags)
    }

    private static func relationship(_ field: String, _ label: String, _ titles: [(String, String)]) -> ItemRelationship {
        ItemRelationship(
            field: field, label: label,
            targets: titles.map { ItemRelationshipTarget(title: $0.0, itemID: ItemID($0.1), resolution: .resolved(ItemID($0.1))) },
            isEditable: true, allowsMultiple: true)
    }

    @Test func theCollectionsRowIsTheOneLinkRowThePageEditsInPlace() {
        let rows = Self.rows(
            [:], relationships: [
                Self.relationship(MarfaMapping.collectionEdge, "In Collection", [("Reading", "20000000-0000-0000-0000-000000000001")]),
                Self.relationship("related", "Related", [("Other", "20000000-0000-0000-0000-000000000002")]),
            ])
        #expect(rows.first { $0.id == MarfaMapping.collectionEdge }?.editable == true)
        #expect(rows.first { $0.id == "related" }?.editable == false)
    }

    // MARK: Kinds

    @Test func aFalseBooleanIsAValue() {
        #expect(Self.rows(["done": .bool(false)]).first { $0.id == "done" }?.value == .boolean(false))
    }

    // MARK: Hidden keys and order

    @Test func hiddenKeysStayOut() {
        let rows = Self.rows(["priority": .string("low"), "title": .string("Title"), "body": .string("Text")], hidden: ["title", "body", "priority"])
        #expect(rows.map(\.id) == ["status"])
    }

}
