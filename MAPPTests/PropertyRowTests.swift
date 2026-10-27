import Foundation
import Marfa
import Testing
@testable import MAPP

struct PropertyRowTests {
    private static func field(_ name: String, _ type: String = "string", description: String? = nil, definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, type: type, description: description, declaredBy: "aic.ticket", definition: definition)
    }

    private static let ticket = MarfaMapping.itemType(ItemType(
        id: "aic.ticket", label: "Ticket",
        fields: [
            field("title"), field("body"),
            field("status", description: "Recommended values: pending, in_progress"),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]]),
            field("due_at", "datetime"), field("done", "boolean"), field("estimate", "integer"),
            field("link", "url"), field("contact", "email"), field("summary"), field("empty")
        ],
        titleField: "title", bodyField: "body"))

    private static func item(_ properties: [String: PropertyValue], source: String? = nil, created: Date = .now) -> MAPP.Item {
        var item = MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("aic.ticket"), title: "Title", titleRule: .property("title"),
            properties: properties.map { Property(key: $0, value: $1) }, version: ItemVersion(1), created: created, modified: created)
        item.source = source
        return item
    }

    private static func rows(
        _ properties: [String: PropertyValue], relationships: [ItemRelationship] = [], tags: [String] = [],
        hidden: Set<String> = ["title", "body"]
    ) -> [PropertyRow] {
        PropertyRow.rows(
            of: item(properties), type: ticket, hidden: hidden, relationships: relationships, parentField: "child-of", tags: tags)
    }

    private static func relationship(_ field: String, _ label: String, _ titles: [(String, String)]) -> ItemRelationship {
        ItemRelationship(
            field: field, label: label,
            targets: titles.map { ItemRelationshipTarget(title: $0.0, itemID: ItemID($0.1), resolution: .resolved(ItemID($0.1))) },
            isEditable: true, allowsMultiple: true)
    }

    // MARK: Kinds

    @Test func eachKindIsDrawnByItsKind() {
        let rows = Self.rows([
            "status": .string("in_progress"), "priority": .string("high"), "due_at": .string("2026-10-27"),
            "done": .bool(true), "estimate": .number(5), "link": .string("https://example.com/a"),
            "contact": .string("a@example.com")
        ])
        #expect(rows.map(\.id) == ["status", "priority", "due_at", "done", "estimate", "link", "contact"])
        #expect(rows[0].value == .status)
        #expect(rows[1].value == .text("High"))
        #expect(rows[2].value == .date(ItemDate.parse("2026-10-27")!.text()))
        #expect(rows[3].value == .boolean(true))
        #expect(rows[4].value == .text("5"))
        #expect(rows[5].value == .url("https://example.com/a"))
        #expect(rows[6].value == .email("a@example.com"))
    }

    @Test func aDatetimeReadsAsADate() {
        let rows = Self.rows(["due_at": .string("2026-10-27T14:00:00Z")])
        #expect(rows.first { $0.id == "due_at" }?.value == .date(ItemDate.parse("2026-10-27T14:00:00Z")!.text()))
    }

    @Test func labelsComeFromTheCatalogue() {
        let rows = Self.rows(["due_at": .string("2026-10-27")])
        #expect(rows.first { $0.id == "due_at" }?.label == "Due At")
    }

    @Test func aLongTextFieldIsLeftOut() {
        let rows = Self.rows([
            "summary": .string(String(repeating: "word ", count: 40)),
        ])
        #expect(rows.first { $0.id == "summary" } == nil)
        #expect(Self.rows(["summary": .string("one\ntwo")]).first { $0.id == "summary" } == nil)
        #expect(Self.rows(["summary": .string("short")]).first { $0.id == "summary" }?.value == .text("short"))
    }

    @Test func aFieldWithNoValueHasNoRow() {
        let rows = Self.rows(["priority": .string(""), "done": .null, "empty": .string("")])
        #expect(rows.map(\.id) == ["status"])
    }

    @Test func aFalseBooleanIsAValue() {
        #expect(Self.rows(["done": .bool(false)]).first { $0.id == "done" }?.value == .boolean(false))
    }

    // MARK: Status, parent and links

    @Test func theStatusRowShowsWithoutAValue() {
        let rows = Self.rows([:])
        #expect(rows.map(\.value) == [.status])
    }

    @Test func theParentFollowsTheStatusAndKeepsItsOwnLabel() {
        let parent = Self.relationship("child-of", "Epic", [("Project", "p1")])
        let rows = Self.rows(["priority": .string("low")], relationships: [parent])
        #expect(rows.map(\.id) == ["status", "child-of", "priority"])
        #expect(rows[1].label == "Epic")
        #expect(rows[1].value == .parent)
    }

    @Test func aTypeWithNoStatusLeadsWithItsParent() {
        let type = MarfaMapping.itemType(ItemType(id: "aic.note", label: "Note", fields: [Self.field("title")], titleField: "title"))
        let rows = PropertyRow.rows(
            of: Self.item([:]), type: type, hidden: ["title"],
            relationships: [Self.relationship("child-of", "Parent", [])], parentField: "child-of", tags: [])
        #expect(rows.map(\.value) == [.parent])
    }

    @Test func otherRelationshipsShowAsLinksAndIncomingOnesDoNot() {
        let blocks = Self.relationship("blocks", "blocks", [("Ship it", "a"), ("Test it", "b")])
        let incoming = Self.relationship("inverse:references", "Linked from", [("Elsewhere", "c")])
        let none = Self.relationship("supersedes", "Supersedes", [])
        let rows = Self.rows([:], relationships: [blocks, incoming, none])
        #expect(rows.map(\.id) == ["status", "blocks"])
        #expect(rows[1].label == "Blocks")
        #expect(rows[1].value == .items([PropertyRow.Target(title: "Ship it", item: ItemID("a")), PropertyRow.Target(title: "Test it", item: ItemID("b"))]))
    }

    @Test func aLinkThatOpensNothingIsLeftOut() {
        let missing = ItemRelationship(
            field: "blocks", label: "Blocks",
            targets: [ItemRelationshipTarget(title: "Gone", itemID: ItemID("a"), resolution: .missing),
                      ItemRelationshipTarget(title: "Binned", itemID: ItemID("b"), resolution: .resolved(ItemID("b")), isDeleted: true)],
            isEditable: true, allowsMultiple: true)
        #expect(Self.rows([:], relationships: [missing]).map(\.id) == ["status"])
    }

    @Test func tagsEndTheBlockAsChips() {
        let rows = Self.rows(["priority": .string("low")], tags: ["mapp", "storage"])
        #expect(rows.last?.value == .tags(["mapp", "storage"]))
        #expect(Self.rows([:], tags: []).contains { $0.id == "#tags" } == false)
    }

    // MARK: Hidden keys and order

    @Test func hiddenKeysStayOut() {
        let rows = Self.rows(["priority": .string("low"), "title": .string("Title"), "body": .string("Text")], hidden: ["title", "body", "priority"])
        #expect(rows.map(\.id) == ["status"])
    }

    @Test func rowsFollowTheTypesFieldOrderNotTheItems() {
        let rows = Self.rows(["contact": .string("a@example.com"), "priority": .string("low"), "done": .bool(true)])
        #expect(rows.map(\.id) == ["status", "priority", "done", "contact"])
    }

    // MARK: The fold

    @Test func moreThanTheFoldHidesTheRestUntilExpanded() {
        let all = (0..<9).map { PropertyRow(id: "k\($0)", label: "K", value: .text("v")) }
        let folded = PropertyRow.split(all, expanded: false)
        #expect(folded.shown.count == PropertyRow.foldAfter)
        #expect(folded.hidden == 3)
        let expanded = PropertyRow.split(all, expanded: true)
        #expect(expanded.shown.count == 9)
        #expect(expanded.hidden == 0)
        #expect(PropertyRow.split(Array(all.prefix(PropertyRow.foldAfter)), expanded: false).hidden == 0)
    }

    // MARK: Byline

    @Test func theBylineNamesTheSourceAndTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        let created = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let byline = PageByline(item: Self.item([:], source: "workbench-folder", created: created), now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))
        #expect(byline.source == "workbench-folder")
        #expect(byline.date == "Yesterday")
        #expect(PageByline(item: Self.item([:], source: "  "), now: now, calendar: calendar).source == nil)
    }

    // MARK: Linked from

    @Test func linkedItemsAreListedOnceNewestFirstAndLeaveOutTheDeleted() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func held(_ id: String, _ title: String, age: TimeInterval, state: MAPP.ItemState = .active) -> MAPP.Item {
            var item = MAPP.Item(
                id: ItemID(id), type: TypeID("core.note"), title: title, titleRule: .firstLine, version: ItemVersion(1),
                created: day, modified: day.addingTimeInterval(-age))
            item.state = state
            return item
        }
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("core.note"), label: "Note", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "file-text")
        ])
        let items = [held("a", "Old", age: 100), held("b", "New", age: 0), held("c", "Binned", age: 0, state: .trashed)]
        let relationships = [
            Self.relationship("inverse:references", "Linked from", [("Old", "a"), ("New", "b"), ("Binned", "c")]),
            Self.relationship("inverse:parent-of", "Children", [("New", "b")]),
            Self.relationship("blocks", "Blocks", [("Mine", "d")]),
        ]
        let list = LinkedItem.list(
            pointingTo: ItemID("self"), in: relationships, catalogue: catalogue, now: day, item: { id in items.first { $0.id == id } })
        #expect(list.map(\.title) == ["New", "Old"])
        #expect(list.first?.icon == "file-text")
        #expect(list.first?.type == "Note")
    }
}
