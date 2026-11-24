import Foundation
import Testing
@testable import MarfaMac

/// What a table column, a board lane and a gallery card read where types share a key or inherit a core field.
@Suite(.hangLimit)
struct SharedKeyColumnTests {
    private static let ticket = TypeID("example.ticket")
    private static let meeting = TypeID("example.meeting")
    private static let plain = TypeID("example.plain")

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

    @Test func aCellOffersOnlyTheWordsOfItsOwnRowsType() throws {
        let catalogue = Catalogue(itemTypes: [
            Self.info(Self.ticket, fields: [Self.status([("open", .notStarted), ("shut", .completed)], by: Self.ticket)]),
            Self.info(Self.meeting, fields: [Self.status([("planned", .notStarted), ("held", .completed)], by: Self.meeting)]),
        ])
        let ticket = Self.row(Self.item("a", Self.ticket))
        let meeting = Self.row(Self.item("b", Self.meeting))
        let column = try #require(ItemTableLayout.columns(for: [ticket, meeting], catalogue: catalogue, hidden: [], looks: [:])
            .first { $0.id == "field.state" })
        #expect(column.field?.options == ["planned", "held", "open", "shut"])
        #expect(column.field(for: ticket, catalogue: catalogue)?.options == ["open", "shut"])
        #expect(column.field(for: meeting, catalogue: catalogue)?.options == ["planned", "held"])
        let undeclaring = Self.row(Self.item("c", Self.plain))
        #expect(column.field(for: undeclaring, catalogue: catalogue) == nil)
    }
}
