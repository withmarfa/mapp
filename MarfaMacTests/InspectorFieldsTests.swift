import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

@Suite(.hangLimit)
struct InspectorFieldsTests {
    private static func field(_ name: String, _ type: String = "string", description: String? = nil, definition: JSONObject = [:]) -> TypeField {
        TypeField(name: name, type: type, description: description, declaredBy: "core.task", definition: definition)
    }

    private static let words: JSONObject = [
        "status_values": [
            ["value": "pending", "group": "not_started"], ["value": "in_progress", "group": "in_progress"],
            ["value": "completed", "group": "completed"], ["value": "canceled", "group": "canceled"],
        ]
    ]

    private static let task = MarfaMapping.itemType(ItemType(
        id: "aic.ticket.task", label: "Task",
        fields: [
            field("title"), field("body"), field("description"),
            field("status", "status", definition: words),
            field("priority", "enum", definition: ["enum_values": ["low", "high"]])
        ],
        titleField: "title", bodyField: "body"))

    private static let file = MarfaMapping.itemType(ItemType(
        id: "core.file", label: "File",
        fields: [field("blob_ref"), field("mime_type"), field("title"), field("description"), field("size_bytes", "integer")],
        titleField: "title"))

    private static func item(
        _ type: String, id: String = "10000000-0000-0000-0000-000000000001", properties: [Property] = [],
        rule: MarfaMac.Item.TitleRule = .property("title"), content: MarfaMac.Item.Content = .markdown
    ) -> MarfaMac.Item {
        MarfaMac.Item(
            id: ItemID(id), type: TypeID(type), title: "Title", titleRule: rule,
            properties: properties, content: content, version: ItemVersion(1), created: .now, modified: .now)
    }

    // MARK: Status

    @Test func aFieldIsNotAStatusByItsNameOrItsDescription() {
        let named = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("status")]))
        let choice = MarfaMapping.itemType(ItemType(
            id: "aic.y", label: "Y", fields: [Self.field("status", "enum", definition: ["enum_values": ["open", "done"]])]))
        let described = MarfaMapping.itemType(ItemType(
            id: "aic.z", label: "Z", fields: [Self.field("status", description: "Recommended values: open, done")]))
        let number = MarfaMapping.itemType(ItemType(id: "aic.w", label: "W", fields: [Self.field("status", "integer")]))
        #expect(named.statusField == nil)
        #expect(choice.statusField == nil)
        #expect(described.statusField == nil)
        #expect(number.statusField == nil)
        #expect(choice.fields[0].options == ["open", "done"], "still a choice, only not a status")
        #expect(described.fields[0].options.isEmpty, "a description is never read for values")
    }

    // MARK: The header's status pin

    @MainActor @Test func theHeaderShowsTheStatusOfAnyTypeThatDefinesOne() {
        let library = FakeItemLibrary(items: [Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("in_progress"))])])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        let header = ItemPageHeader.header(of: library.items[0].id, in: library, drafts: DetailsPresentation())
        #expect(header?.status?.label == "In Progress")
        #expect(header?.status?.enabled == true)
    }

    @MainActor @Test func aReadOnlyItemsPinnedStatusCannotBeEdited() {
        var item = Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("in_progress"))])
        item.state = .trashed
        let library = FakeItemLibrary(items: [item])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        let header = ItemPageHeader.header(of: item.id, in: library, drafts: DetailsPresentation())
        #expect(header?.rows.contains { $0.id == "status" && $0.value == .status } == true)
        #expect(header?.status?.enabled == false)
    }

    @MainActor @Test func theHeaderDrawsATitleOnlyForAnItemWhoseTitleIsItsOwn() {
        let titled = Self.item("aic.ticket.task")
        let fromText = Self.item("core.note", id: "10000000-0000-0000-0000-000000000003", rule: .firstLine)
        let library = FakeItemLibrary(items: [titled, fromText])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        #expect(ItemPageHeader.header(of: titled.id, in: library, drafts: DetailsPresentation())?.showsTitle == true)
        #expect(ItemPageHeader.header(of: fromText.id, in: library, drafts: DetailsPresentation())?.showsTitle == false)
    }

    @MainActor @Test func aStatusWithNoValueIsAnEmptyRowAndATypeWithoutOneHasNone() {
        let library = FakeItemLibrary(items: [Self.item("aic.ticket.task"), Self.item("core.file", id: "10000000-0000-0000-0000-000000000002")])
        library.catalogue = Catalogue(itemTypes: [Self.task, Self.file])
        let empty = ItemPageHeader.header(of: library.items[0].id, in: library, drafts: DetailsPresentation())
        #expect(empty?.status == nil)
        #expect(empty?.rows.first { $0.id == "status" }?.isEmpty == true)
        #expect(ItemPageHeader.header(of: library.items[1].id, in: library, drafts: DetailsPresentation())?.status == nil)
    }

    @Test func aStatusKeepsAnyTypedValueInItsMenu() throws {
        let status = try #require(Self.task.statusField)
        #expect(status.options(including: nil) == status.options)
        #expect(status.options(including: "") == status.options)
        #expect(status.options(including: "completed") == status.options)
        #expect(status.options(including: "waiting on Sam") == status.options + ["waiting on Sam"])
        #expect(ItemTypeInfo.Field.label(ofOption: "in_progress") == "In Progress")
        let plain = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("note")])).fields[0]
        #expect(plain.options(including: "anything").isEmpty)
    }

    @Test func theStatusMenuKeepsAValueTheCatalogueDoesNotList() throws {
        let status = try #require(Self.task.statusField)
        let blocked = Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("blocked"))])
        #expect(ItemPageHeader.statusChoices(of: blocked, in: status) == ["pending", "in_progress", "completed", "canceled", "blocked"])
        let completed = Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string("completed"))])
        #expect(ItemPageHeader.statusChoices(of: completed, in: status) == status.options)
        #expect(PageHead.statusValue(of: Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string(""))]), in: status) == nil)
    }

    // MARK: The inspector's fields

    @MainActor private static func marfa(_ items: [MarfaMac.Item], types: [ItemTypeInfo]) async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: Catalogue(itemTypes: types))))
        try #require(await eventually { library.isLoaded })
        return library
    }

    @MainActor @Test func theTitleAndTheBodyAreNotProperties() {
        let item = Self.item("aic.ticket.task", properties: [
            Property(key: "title", value: .string("Title")), Property(key: "body", value: .string("Text")),
            Property(key: "description", value: .string("About"))
        ])
        let library = FakeItemLibrary(items: [item])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        let hidden = library.hiddenPropertyKeys(of: item)
        #expect(hidden == ["title", "body"])
        #expect(InspectorFields.properties(of: item, type: Self.task, hidden: hidden).map(\.key) == ["description"])
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: hidden).map(\.key) == ["status", "priority"])
    }

    @Test func aUrlOrEmailValueIsALinkOnlyToAWebOrMailAddress() {
        func link(_ format: ItemTypeInfo.Field.TextFormat?, _ text: String) -> String? {
            let field = ItemTypeInfo.Field(key: "k", label: "K", kind: .text, declaredBy: TypeID("aic.x"), format: format)
            return InspectorFields.link(of: field, value: .string(text))?.absoluteString
        }
        #expect(link(.url, "https://example.com/a?b=1") == "https://example.com/a?b=1")
        #expect(link(.url, " HTTP://Example.com ") == "HTTP://Example.com")
        #expect(link(.url, "javascript:alert(1)") == nil)
        #expect(link(.url, "file:///etc/passwd") == nil)
        #expect(link(.url, "example.com") == nil, "the page leaves an address with no scheme as text")
        #expect(link(.url, "https://") == nil)
        #expect(link(.email, "ada@example.com") == "mailto:ada@example.com")
        #expect(link(.email, "not an address") == nil)
        #expect(link(.email, "a@b.co\nc@d.co") == nil)
        #expect(link(nil, "https://example.com") == nil, "a plain text field is text")
        #expect(InspectorFields.link(of: ItemTypeInfo.Field(key: "k", label: "K", kind: .text, declaredBy: TypeID("aic.x"), format: .url), value: nil) == nil)
    }

    // MARK: Only what has a value

    @Test func propertiesListOnlyWhatHasAValueInTheCataloguesOrder() {
        let item = Self.item("aic.ticket.task", properties: [
            Property(key: "priority", value: .string("high")), Property(key: "description", value: .string("About")),
            Property(key: "status", value: .string(""))
        ])
        #expect(InspectorFields.properties(of: item, type: Self.task, hidden: ["title", "body"]).map(\.key) == ["description", "priority"])
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: ["title", "body"]).map(\.key) == ["status"])
    }

    @Test func aPropertyTheItemCannotTakeIsNeverOffered() {
        var item = Self.item("aic.ticket.task")
        item.state = .trashed
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: []).isEmpty)
        let list = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("tags", "array"), Self.field("note")]))
        #expect(InspectorFields.addable(of: Self.item("aic.x"), type: list, hidden: []).map(\.key) == ["note"])
    }

    @Test func anAddedOrClearedPropertyStaysListedAndLeavesTheMenu() {
        let item = Self.item("aic.ticket.task")
        let hidden: Set<String> = ["title", "body"]
        let revealed: Set<String> = ["priority"]
        #expect(InspectorFields.properties(of: item, type: Self.task, hidden: hidden, revealed: revealed).map(\.key) == ["priority"])
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: hidden, revealed: revealed).map(\.key) == ["description", "status"])
    }

    @Test func emptyValuesAreNotValues() {
        #expect(!InspectorFields.hasValue(nil))
        #expect(!InspectorFields.hasValue(.null))
        #expect(!InspectorFields.hasValue(.string("")))
        #expect(!InspectorFields.hasValue(.array([])))
        #expect(InspectorFields.hasValue(.string("a")))
        #expect(InspectorFields.hasValue(.bool(false)))
        #expect(InspectorFields.hasValue(.number(0)))
    }

    // MARK: Labels

    @MainActor @Test func aTitleFromTheFirstLineHidesNothingElse() {
        let note = Self.item("core.note", rule: .firstLine)
        let library = FakeItemLibrary(items: [note])
        library.catalogue = Catalogue()
        #expect(library.hiddenPropertyKeys(of: note).isEmpty)
    }

    @MainActor @Test func aTitleKeptInAnotherPropertyHidesThatProperty() {
        let entity = Self.item("core.entity", rule: .property("name"))
        #expect(FakeItemLibrary(items: [entity]).hiddenPropertyKeys(of: entity) == ["name"])
    }

    @MainActor @Test func aMarfaFileHidesItsBlobAndItsFacts() async throws {
        let item = Self.item("core.file", properties: [
            Property(key: "blob_ref", value: .string("sha256:abc")), Property(key: "mime_type", value: .string("text/plain")),
            Property(key: "title", value: .string("notes.txt")), Property(key: "size_bytes", value: .number(76)),
            Property(key: "description", value: .string("Meeting notes"))
        ], content: .file(.plainText, byteCount: 76))
        let library = try await Self.marfa([item], types: [Self.file])
        let hidden = library.hiddenPropertyKeys(of: item)
        #expect(hidden == MarfaMapping.fileFacts.union(["title"]))
        #expect(InspectorFields.properties(of: item, type: Self.file, hidden: hidden).map(\.key) == ["description"])
        // None of them turns up under the other properties either.
        #expect(InspectorFields.accountedFor(type: Self.file, hidden: hidden).isSuperset(of: ["blob_ref", "mime_type", "size_bytes"]))
    }

    @MainActor @Test func aMarfanItemKeepsItsPropertiesNamedLikeAFilesFacts() async throws {
        let note = Self.item("core.note", properties: [Property(key: "size_bytes", value: .number(1))])
        let library = try await Self.marfa([note], types: [MarfaMapping.itemType(ItemType(id: "core.note", label: "Note", titleField: "title"))])
        #expect(library.hiddenPropertyKeys(of: note) == ["title"])
    }

}
