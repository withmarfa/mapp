import Foundation
import Testing
@testable import MarfaMac

/// Add Sort offers the fields of the types a view shows, and the columns every item has.
struct SortChoicesTests {
    private static let task = TypeID("example.task")
    private static let note = TypeID("example.note")
    private static let place = TypeID("example.place")

    private static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind, in type: TypeID) -> ItemTypeInfo.Field {
        .init(key: key, label: key.capitalized, kind: kind, declaredBy: type)
    }

    private static let status = field("status", .status([StatusWord(value: "todo", group: .notStarted)]), in: task)
    private static let priority = field("priority", .choice(["low", "high"]), in: task)
    private static let language = field("language", .text, in: note)
    private static let altitude = field("altitude", .number, in: place)

    private static let catalogue = Catalogue(itemTypes: [
        info(task, [status, priority]), info(note, [language]), info(place, [altitude]),
    ])

    private static func info(_ id: TypeID, _ fields: [ItemTypeInfo.Field]) -> ItemTypeInfo {
        ItemTypeInfo(id: id, label: id.rawValue, fields: fields, titleField: "title", bodyField: "body", parent: nil)
    }

    private static func column(_ field: ItemTypeInfo.Field, _ style: ItemTableColumn.Style) -> ItemTableColumn {
        ItemTableColumn(id: "field." + field.key, label: field.label, content: .field(field), style: style)
    }

    /// The columns of a table of all three types, as the table lists them: dates and the parent mixed in among the fields.
    private static var columns: [ItemTableColumn] {
        [.title, .type, column(language, .text), .edited, column(status, .status), column(altitude, .number), .parent,
         column(priority, .priority), .created, .tags]
    }

    private static func choices(_ types: Set<TypeID>) -> [String] {
        ItemTableLayout.sortChoices(from: columns, types: types, catalogue: catalogue).map(\.id)
    }

    @Test func aViewOfOneTypeOffersThatTypesFieldsAndTheColumnsEveryItemHas() {
        #expect(Self.choices([Self.task]) == ["title", "field.status", "field.priority", "parent", "edited", "created", "tags"])
    }

    @Test func aViewOfSeveralTypesOffersTheTypeColumnAndTheFieldsOfEachTypeItShows() {
        #expect(Self.choices([Self.task, Self.note]) == [
            "title", "type", "field.status", "field.language", "field.priority", "parent", "edited", "created", "tags"])
    }

    @Test func aFieldOfATypeTheViewDoesNotShowIsNotOffered() {
        let all = Self.choices([Self.task, Self.note, Self.place])
        #expect(all.contains("field.altitude"))
        #expect(!Self.choices([Self.task, Self.note]).contains("field.altitude"))
        #expect(!Self.choices([Self.note]).contains("field.status"))
    }

    @Test func theStatusLeadsTheOtherFieldsAndTheDatesComeLast() {
        let ids = Self.choices([Self.task, Self.note, Self.place])
        #expect(ids.prefix(3) == ["title", "type", "field.status"])
        #expect(ids.suffix(3) == ["edited", "created", "tags"])
    }
}
