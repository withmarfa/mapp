import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct InspectorFieldsTests {
    private static func field(_ name: String, _ type: String = "string", description: String? = nil, definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, type: type, description: description, declaredBy: "core.task", definition: definition)
    }

    private static let recommended = "Recommended values: pending, in_progress, completed, canceled"

    private static let task = MarfaMapping.itemType(ItemType(
        id: "aic.ticket.task", label: "Task",
        fields: [
            field("title"), field("body"), field("description"),
            field("status", description: recommended),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]])
        ],
        titleField: "title", bodyField: "body"))

    private static let file = MarfaMapping.itemType(ItemType(
        id: "core.file", label: "File",
        fields: [field("blob_ref"), field("mime_type"), field("title"), field("description"), field("size_bytes", "integer")],
        titleField: "title"))

    private static func item(
        _ type: String, id: String = "10000000-0000-0000-0000-000000000001", properties: [Property] = [],
        rule: MAPP.Item.TitleRule = .property("title"), content: MAPP.Item.Content = .markdown
    ) -> MAPP.Item {
        MAPP.Item(
            id: ItemID(id), type: TypeID(type), title: "Title", titleRule: rule,
            properties: properties, content: content, version: ItemVersion(1), created: .now, modified: .now)
    }

    // MARK: Status

    @Test func aTextStatusThatRecommendsValuesIsAStatus() throws {
        let status = try #require(Self.task.statusField)
        #expect(status.options == ["pending", "in_progress", "completed", "canceled"])
        #expect(status.isPicked)
    }

    @Test func aChoiceStatusIsAStatusWithItsOwnValues() throws {
        let type = MarfaMapping.itemType(ItemType(
            id: "aic.x", label: "X", fields: [Self.field("status", "enum", definition: ["enum_values": ["open", "done"]])]))
        #expect(type.statusField?.options == ["open", "done"])
    }

    @Test func aStatusWithNothingToPickFromIsStillFound() throws {
        let type = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("status")]))
        let status = try #require(type.statusField)
        #expect(status.options.isEmpty)
        #expect(!status.isPicked)
    }

    @Test func aStatusOfAnotherShapeOrNameIsNotAStatus() {
        let number = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("status", "integer")]))
        let renamed = MarfaMapping.itemType(ItemType(id: "aic.y", label: "Y", fields: [Self.field("state")]))
        #expect(number.statusField == nil)
        #expect(renamed.statusField == nil)
    }

    @Test func recommendedValuesAreReadOnlyWhereTheyAreAList() {
        func options(_ description: String?) -> [String] {
            MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("status", description: description)]))
                .fields[0].options
        }
        #expect(options("recommended VALUES: open, done.") == ["open", "done"])
        #expect(options("Where the work stands. Recommended values: open, done") == [])
        #expect(options("Recommended values: whatever fits the work, as you like") == [])
        #expect(options("Recommended values:") == [])
        #expect(options(nil) == [])
    }

    @Test func optionsReadAsWords() {
        #expect(ItemTypeInfo.Field.label(ofOption: "completed") == "Completed")
        #expect(ItemTypeInfo.Field.label(ofOption: "in_progress") == "In Progress")
        #expect(ItemTypeInfo.Field.label(ofOption: "on-hold") == "On Hold")
        #expect(ItemTypeInfo.Field.label(ofOption: "") == "")
    }

    // MARK: The header's status pin

    @MainActor @Test func theHeaderShowsTheStatusOfAnyTypeThatDefinesOne() {
        let library = FakeItemLibrary(items: [Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("in_progress"))])])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        let header = ItemPageHeader.header(of: library.items[0].id, in: library, drafts: DetailsPresentation())
        #expect(header?.status?.label == "In Progress")
        #expect(header?.status?.empty == false)
        #expect(header?.status?.enabled == true)
        #expect(header?.status?.opensMenu == true)
    }

    @MainActor @Test func aStatusWithNoValueIsAnEmptyPinAndATypeWithoutOneHasNone() {
        let library = FakeItemLibrary(items: [Self.item("aic.ticket.task"), Self.item("core.file", id: "10000000-0000-0000-0000-000000000002")])
        library.catalogue = Catalogue(itemTypes: [Self.task, Self.file])
        let empty = ItemPageHeader.header(of: library.items[0].id, in: library, drafts: DetailsPresentation())
        #expect(empty?.status?.label == "Status")
        #expect(empty?.status?.empty == true)
        #expect(ItemPageHeader.header(of: library.items[1].id, in: library, drafts: DetailsPresentation())?.status == nil)
    }

    @Test func theStatusMenuKeepsAValueTheCatalogueDoesNotList() throws {
        let status = try #require(Self.task.statusField)
        let blocked = Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("blocked"))])
        #expect(ItemPageHeader.statusChoices(of: blocked, in: status) == ["pending", "in_progress", "completed", "canceled", "blocked"])
        let completed = Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("completed"))])
        #expect(ItemPageHeader.statusChoices(of: completed, in: status) == status.options)
        #expect(ItemPageHeader.statusValue(of: Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string(""))]), in: status) == nil)
    }

    @Test func aPinSaysWhetherItOpensAMenu() throws {
        let direct = try JSONEncoder().encode(PageHeader.Pin(label: "Parent", enabled: true, empty: true, opensMenu: false))
        let menu = try JSONEncoder().encode(PageHeader.Pin(label: "Status", enabled: true))
        #expect(try JSONSerialization.jsonObject(with: direct) as? [String: Any] != nil)
        #expect(String(decoding: direct, as: UTF8.self).contains("\"opensMenu\":false"))
        #expect(String(decoding: menu, as: UTF8.self).contains("\"opensMenu\":true"))
    }

    // MARK: The inspector's fields

    @Test func theTitleAndTheBodyAreNotProperties() {
        let item = Self.item("aic.ticket.task", properties: [
            Property(key: "title", value: .string("Title")), Property(key: "body", value: .string("Text")),
            Property(key: "description", value: .string("About"))
        ])
        #expect(InspectorFields.properties(of: item, type: Self.task).map(\.key) == ["description", "status", "priority"])
    }

    @Test func aTitleFromTheFirstLineHidesNothingElse() {
        let note = Self.item("core.note", rule: .firstLine)
        #expect(InspectorFields.hiddenKeys(of: note, type: nil).isEmpty)
    }

    @Test func aFileHidesItsBlobAndItsFacts() {
        let item = Self.item("core.file", properties: [
            Property(key: "blob_ref", value: .string("sha256:abc")), Property(key: "mime_type", value: .string("text/plain")),
            Property(key: "title", value: .string("notes.txt")), Property(key: "size_bytes", value: .number(76)),
            Property(key: "description", value: .string("Meeting notes"))
        ], content: .file(.plainText, byteCount: 76))
        #expect(InspectorFields.hiddenKeys(of: item, type: Self.file) == ["blob_ref", "mime_type", "size_bytes", "title"])
        #expect(InspectorFields.properties(of: item, type: Self.file).map(\.key) == ["description"])
        // None of them turns up under the other properties either.
        #expect(InspectorFields.accountedFor(item: item, type: Self.file).isSuperset(of: ["blob_ref", "mime_type", "size_bytes"]))
    }

    @Test func aFieldWithNothingInItAndNoWayToAddToItHasNoRow() {
        let list = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("tags", "array")]))
        let empty = Self.item("aic.x")
        #expect(InspectorFields.properties(of: empty, type: list).isEmpty)
        let full = Self.item("aic.x", properties: [Property(key: "tags", value: .array([.string("a")]))])
        #expect(InspectorFields.properties(of: full, type: list).map(\.key) == ["tags"])
    }
}
