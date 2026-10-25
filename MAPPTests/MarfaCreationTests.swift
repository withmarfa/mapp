import Foundation
import Marfa
import enum MarfaCore.JsonValue
import Testing
@testable import MAPP

@MainActor
struct MarfaCreationTests {
    @Test(arguments: ["core.note", "test.entry"])
    func aTitleOnlyCreateIncludesItsRequiredTextBody(_ typeID: String) async throws {
        let bodyKey = typeID == "core.note" ? "body" : "content"
        let titleKey = typeID == "core.note" ? "title" : "name"
        let catalogue = MarfaMapping.catalogue(itemTypes: [ItemType(
            id: typeID, label: "Entry",
            fields: [
                TypeField(name: titleKey, type: "string", required: typeID != "core.note", declaredBy: typeID),
                TypeField(name: bodyKey, type: "string", required: true, declaredBy: "test.parent"),
            ], titleField: titleKey, bodyField: bodyKey)], edgeTypes: [])
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: [], catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        let browser = Browser()
        browser.adopt(library)
        let id = try #require(browser.startNewItem(typeID: typeID, in: library, undoManager: nil))
        guard case .create(let submittedID, let draft) = try #require(source.writes.last) else {
            Issue.record("Expected a create")
            return
        }
        #expect(submittedID == id)
        #expect(browser.isAwaitingNewItem)
        #expect(library.failure == nil)

        let properties = try MarfaEngine.creationProperties(draft, catalogue: catalogue)

        #expect(properties[titleKey] == .string(String(localized: "Untitled")))
        #expect(properties[bodyKey] == .string(""))
    }

    @Test(arguments: [ItemTypeInfo.Field.Kind.text, .number, .boolean, .date, .choice(["open"]), .other])
    func anUnfilledRequiredFieldMakesNothingAndSaysWhich(_ kind: ItemTypeInfo.Field.Kind) async throws {
        let type = ItemTypeInfo(
            id: TypeID("test.record"), label: "Record",
            fields: [
                .init(key: "title", label: "Title", kind: .text, declaredBy: TypeID("test.record")),
                .init(key: "body", label: "Body", kind: .text, declaredBy: TypeID("test.record"), required: true),
                .init(key: "needed", label: "Needed", kind: kind, declaredBy: TypeID("test.parent"), required: true),
            ], titleField: "title", bodyField: "body", parent: TypeID("test.parent"))
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: [], catalogue: Catalogue(itemTypes: [type], edgeTypes: []))))
        try #require(await eventually { library.isLoaded })
        let browser = Browser()
        browser.adopt(library)
        let undo = UndoManager()

        #expect(browser.startNewItem(typeID: type.id.rawValue, in: library, undoManager: undo) == nil)
        #expect(source.writes.isEmpty)
        #expect(!undo.canUndo)
        #expect(!browser.isAwaitingNewItem)
        #expect(browser.newItems.isEmpty)
        #expect(library.failure?.title == String(localized: "Can’t Create Item"))
        #expect(library.failure?.message.contains("Needed") == true)
        #expect(library.failure?.message.contains("draft") == false)

        source.send(.catalogue(Self.catalogue()))
        try #require(await eventually { library.catalogue.itemTypes[Self.type] != nil })
        let id = try #require(browser.startNewItem(typeID: Self.type.rawValue, in: library, undoManager: undo))
        #expect(source.writes == [.create(id: id, ItemDraft(type: Self.type, title: String(localized: "Untitled"), body: ""))])
    }

    @Test(arguments: [ItemTypeInfo.Field.Kind.number, .boolean, .date, .choice(["open"]), .other])
    func aRequiredBodyOfAnotherShapeIsNotFilledWithEmptyText(_ kind: ItemTypeInfo.Field.Kind) throws {
        let catalogue = Self.catalogue(bodyKind: kind)
        #expect(throws: MarfaEngine.Refused.self) {
            try MarfaEngine.creationProperties(ItemDraft(type: Self.type, title: "Title"), catalogue: catalogue)
        }
    }

    @Test func anOptionalBodyStaysAbsentAndTypedTextIsKeptExactly() throws {
        let catalogue = Self.catalogue(bodyRequired: false)
        var draft = ItemDraft(type: Self.type, title: "Title")
        #expect(try MarfaEngine.creationProperties(draft, catalogue: catalogue)["body"] == nil)
        draft.body = "\r\n  Keep this text.\r\n"
        #expect(try MarfaEngine.creationProperties(draft, catalogue: catalogue)["body"] == .string(draft.body))
        #expect(try MarfaEngine.creationProperties(draft, catalogue: Self.catalogue())["body"] == .string(draft.body))
    }

    @Test func aDeclaredBodyWithoutDisplayHintsStillGetsRequiredText() throws {
        let catalogue = Self.catalogue(titleField: nil)
        let properties = try MarfaEngine.creationProperties(ItemDraft(type: Self.type, title: ""), catalogue: catalogue)
        #expect(properties["body"] == .string(""))
    }

    @Test func aTitleWithoutItsOwnFieldStartsTheBody() throws {
        let draft = ItemDraft(type: Self.type, title: "Title", body: "Text")
        let properties = try MarfaEngine.creationProperties(draft, catalogue: Self.catalogue(titleField: nil))
        #expect(properties["body"] == .string("Title\n\nText"))
        #expect(properties["title"] == nil)
    }

    @Test func providedRequiredPropertiesAreKeptButNullDoesNotFillThem() throws {
        let extra = ItemTypeInfo.Field(key: "count", label: "Count", kind: .number, declaredBy: Self.type, required: true)
        let catalogue = Self.catalogue(extra: [extra])
        var draft = ItemDraft(type: Self.type, title: "Title", properties: ["count": .number(0)])
        let properties = try MarfaEngine.creationProperties(draft, catalogue: catalogue)
        #expect(properties["count"] == .integer(0))
        #expect(properties["body"] == .string(""))
        draft.properties["count"] = .null
        #expect(throws: MarfaEngine.Refused.self) {
            try MarfaEngine.creationProperties(draft, catalogue: catalogue)
        }
    }

    private static let type = TypeID("test.entry")

    private static func catalogue(
        bodyRequired: Bool = true, bodyKind: ItemTypeInfo.Field.Kind = .text,
        titleField: String? = "name", extra: [ItemTypeInfo.Field] = []
    ) -> Catalogue {
        var fields = [ItemTypeInfo.Field(
            key: "body", label: "Body", kind: bodyKind, declaredBy: type, required: bodyRequired)] + extra
        if let titleField {
            fields.append(.init(key: titleField, label: "Name", kind: .text, declaredBy: type, required: true))
        }
        return Catalogue(itemTypes: [ItemTypeInfo(
            id: type, label: "Entry", fields: fields, titleField: titleField, bodyField: nil, parent: nil)], edgeTypes: [])
    }
}
