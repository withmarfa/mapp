import Foundation
import Testing
@testable import MAPP

/// What a table column, a board lane and a gallery card read where types share a key or inherit a core field.
@Suite(.hangLimit)
struct SharedKeyColumnTests {
    private static let task = TypeID("core.task")
    private static let event = TypeID("core.event")
    private static let ticket = TypeID("example.ticket")
    private static let meeting = TypeID("example.meeting")
    private static let plain = TypeID("example.plain")
    private static let other = TypeID("example.other")

    private static func status(_ words: [(String, StatusGroup)], by type: TypeID) -> ItemTypeInfo.Field {
        .init(key: "state", label: "State", kind: .status(words.map { StatusWord(value: $0.0, group: $0.1) }), declaredBy: type)
    }

    private static func info(_ id: TypeID, fields: [ItemTypeInfo.Field], parent: TypeID? = nil) -> ItemTypeInfo {
        ItemTypeInfo(id: id, label: id.rawValue, fields: fields, titleField: "title", bodyField: "body", parent: parent)
    }

    private static func item(_ id: String, _ type: TypeID, _ properties: [String: PropertyValue] = [:]) -> Item {
        Item(id: ItemID(id), type: type, title: id, titleRule: .property("title"),
             properties: properties.map { Property(key: $0.key, value: $0.value) },
             version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
    }

    private static func row(_ item: Item) -> ItemTableRow {
        ItemTableRow(item: item, typeLabel: item.type.rawValue, typeIcon: nil, parent: nil)
    }

    // MARK: Shared columns

    @Test func aKeyTypesShareKeepsTheMostSpecificStyleWhicheverTypeComesFirst() throws {
        // "example.other" sorts before "example.ticket": its plain choice is met first.
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.other, fields: [.init(key: "state", label: "State", kind: .choice(["a", "b"]), declaredBy: Self.other)]),
            Self.info(Self.ticket, fields: [Self.status([("open", .notStarted), ("shut", .completed)], by: Self.ticket)]),
        ])
        let rows = [Self.row(Self.item("a", Self.other)), Self.row(Self.item("b", Self.ticket))]
        let columns = ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [])
        let column = try #require(columns.first { $0.id == "field.state" })
        #expect(column.style == .status)
        #expect(column.field?.isStatus == true)
    }

    @Test func aPriorityOutranksAChoiceOfTheSameKey() throws {
        let priority = { (type: TypeID) in ItemTypeInfo.Field(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: type) }
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.other, fields: [priority(Self.other)]),
            Self.info(Self.ticket, fields: [priority(Self.ticket)], parent: Self.task),
            Self.info(Self.task, fields: []),
        ])
        let rows = [Self.row(Self.item("a", Self.other)), Self.row(Self.item("b", Self.ticket))]
        let columns = ItemTableLayout.columns(for: rows, catalogue: catalogue, hidden: [])
        #expect(columns.first { $0.id == "field.priority" }?.style == .priority)
    }

    @Test func aTextFieldNamedAssigneeIsPlainText() throws {
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.ticket, fields: [.init(key: "assignee", label: "Assignee", kind: .text, declaredBy: Self.ticket)]),
        ])
        let columns = ItemTableLayout.columns(for: [Self.row(Self.item("a", Self.ticket))], catalogue: catalogue, hidden: [])
        #expect(columns.first { $0.id == "field.assignee" }?.style == .text)
    }

    @Test func aCellOffersOnlyTheWordsOfItsOwnRowsType() throws {
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.ticket, fields: [Self.status([("open", .notStarted), ("shut", .completed)], by: Self.ticket)]),
            Self.info(Self.meeting, fields: [Self.status([("planned", .notStarted), ("held", .completed)], by: Self.meeting)]),
        ])
        let ticket = Self.row(Self.item("a", Self.ticket))
        let meeting = Self.row(Self.item("b", Self.meeting))
        let column = try #require(ItemTableLayout.columns(for: [ticket, meeting], catalogue: catalogue, hidden: [])
            .first { $0.id == "field.state" })
        #expect(column.field?.options == ["planned", "held", "open", "shut"])
        #expect(column.field(for: ticket, catalogue: catalogue)?.options == ["open", "shut"])
        #expect(column.field(for: meeting, catalogue: catalogue)?.options == ["planned", "held"])
        let undeclaring = Self.row(Self.item("c", Self.plain))
        #expect(column.field(for: undeclaring, catalogue: catalogue) == nil)
    }

    // MARK: Board lanes

    @Test func statusLanesOfSeveralTypesFollowTheStatusGroupsThenDeclaredOrder() {
        let catalogue = Catalogue(itemTypes: [
            // Declared with the finished words first on purpose: the group, not the declaration, puts them last.
            Self.info(Self.ticket, fields: [Self.status([("done", .completed), ("doing", .inProgress), ("todo", .notStarted)], by: Self.ticket)]),
            Self.info(Self.meeting, fields: [Self.status([("held", .completed), ("planned", .notStarted), ("running", .inProgress)], by: Self.meeting)]),
        ])
        let items = [Self.item("a", Self.ticket), Self.item("b", Self.meeting)]
        let lanes = ItemBoardLayout.lanes(items: items, key: "state", catalogue: catalogue)
        #expect(lanes.map(\.id) == [
            .option("running"), .option("doing"), .option("planned"), .option("todo"), .option("held"), .option("done"), .missing,
        ])
    }

    @Test func aChoiceBoardKeepsDeclaredOrder() {
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.ticket, fields: [.init(key: "size", label: "Size", kind: .choice(["small", "large", "medium"]), declaredBy: Self.ticket)]),
        ])
        let lanes = ItemBoardLayout.lanes(items: [Self.item("a", Self.ticket)], key: "size", catalogue: catalogue)
        #expect(lanes.map(\.id) == [.option("small"), .option("large"), .option("medium"), .missing])
    }

    // MARK: Gallery start dates

    @Test @MainActor func aStartDateIsTheDeclaredStartsAtOfAnEventOrTaskType() {
        let startsAt = { (type: TypeID) in ItemTypeInfo.Field(key: "starts_at", label: "Starts", kind: .date(includesTime: true), declaredBy: type) }
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.event, fields: [startsAt(Self.event)]),
            Self.info(Self.meeting, fields: [startsAt(Self.meeting)], parent: Self.event),
            Self.info(Self.plain, fields: [startsAt(Self.plain),
                .init(key: "start", label: "Start", kind: .date(includesTime: false), declaredBy: Self.plain)]),
        ])
        let library = FakeItemLibrary()
        library.catalogue = catalogue
        let day = "2026-11-02"
        func date(_ type: TypeID) -> Date? {
            let item = Self.item("x", type, ["starts_at": .string(day), "start": .string(day)])
            return GalleryKind.startDate(of: item, info: catalogue.itemTypes[type], in: library)
        }
        #expect(date(Self.event) != nil)
        #expect(date(Self.meeting) != nil)
        // A type outside event and task ancestry is not read, whatever its fields are called.
        #expect(date(Self.plain) == nil)
        #expect(date(TypeID("example.unknown")) == nil)
    }
}
