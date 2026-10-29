import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@Suite(.hangLimit)
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

    @MainActor @Test func theHeaderDrawsATitleOnlyForAnItemWhoseTitleIsItsOwn() {
        let titled = Self.item("aic.ticket.task")
        let fromText = Self.item("core.note", id: "10000000-0000-0000-0000-000000000003", rule: .firstLine)
        let library = FakeItemLibrary(items: [titled, fromText])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        #expect(ItemPageHeader.header(of: titled.id, in: library, drafts: DetailsPresentation())?.showsTitle == true)
        #expect(ItemPageHeader.header(of: fromText.id, in: library, drafts: DetailsPresentation())?.showsTitle == false)
    }

    @MainActor @Test func aStatusWithNoValueIsAnEmptyPinAndATypeWithoutOneHasNone() {
        let library = FakeItemLibrary(items: [Self.item("aic.ticket.task"), Self.item("core.file", id: "10000000-0000-0000-0000-000000000002")])
        library.catalogue = Catalogue(itemTypes: [Self.task, Self.file])
        let empty = ItemPageHeader.header(of: library.items[0].id, in: library, drafts: DetailsPresentation())
        #expect(empty?.status?.label == "Status")
        #expect(empty?.status?.empty == true)
        #expect(ItemPageHeader.header(of: library.items[1].id, in: library, drafts: DetailsPresentation())?.status == nil)
    }

    @Test func aFieldThatOnlyRecommendsValuesKeepsAnyTypedValueInItsMenu() throws {
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
        #expect(ItemPageHeader.statusValue(of: Self.item("aic.ticket.task", properties: [Property(key: "status", value: .string(""))]), in: status) == nil)
    }

    @Test func aPinSaysWhetherItOpensAMenu() throws {
        let direct = try JSONEncoder().encode(PageHeader.Pin(label: "Parent", enabled: true, empty: true, opensMenu: false))
        let menu = try JSONEncoder().encode(PageHeader.Pin(label: "Status", enabled: true))
        #expect(try JSONSerialization.jsonObject(with: direct) as? [String: Any] != nil)
        #expect(String(decoding: direct, as: UTF8.self).contains("\"opensMenu\":false"))
        #expect(String(decoding: menu, as: UTF8.self).contains("\"opensMenu\":true"))
    }

    @MainActor @Test func aRefusedRemoveParentIsToldAndAnAcceptedOneClearsTheTelling() throws {
        let child = Self.item("aic.ticket.task")
        let target = ItemRelationshipTarget(title: "Field Research", itemID: ItemID("10000000-0000-0000-0000-000000000009"), resolution: .resolved(ItemID("10000000-0000-0000-0000-000000000009")))
        let parent = ItemRelationship(field: "child-of", label: "Parent", targets: [target], isEditable: true, allowsMultiple: false)
        let library = FakeItemLibrary(items: [child])
        library.catalogue = Catalogue(itemTypes: [Self.task])
        library.relationshipsByItem[child.id] = [parent]
        let drafts = DetailsPresentation()

        ItemPageHeader.removeParent(parent, of: child.id, in: library, drafts: drafts, undoManager: nil)
        #expect(library.relationshipWrites.map(\.targets) == [[]])
        #expect(ItemPageHeader.header(of: child.id, in: library, drafts: drafts)?.parentRejected == true)

        library.acceptsRelationships = true
        ItemPageHeader.removeParent(parent, of: child.id, in: library, drafts: drafts, undoManager: nil)
        #expect(ItemPageHeader.header(of: child.id, in: library, drafts: drafts)?.parentRejected == false)
    }

    // MARK: The inspector's fields

    @MainActor private static func marfa(_ items: [MAPP.Item], types: [ItemTypeInfo]) async throws -> MarfaLibrary {
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

    // MARK: Only what has a value

    @Test func propertiesListOnlyWhatHasAValueInTheCataloguesOrder() {
        let item = Self.item("aic.ticket.task", properties: [
            Property(key: "priority", value: .string("high")), Property(key: "description", value: .string("About")),
            Property(key: "status", value: .string(""))
        ])
        #expect(InspectorFields.properties(of: item, type: Self.task, hidden: ["title", "body"]).map(\.key) == ["description", "priority"])
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: ["title", "body"]).map(\.key) == ["status"])
    }

    @Test func anItemWithNoValuesListsNothingAndOffersEveryProperty() {
        let item = Self.item("aic.ticket.task")
        #expect(InspectorFields.properties(of: item, type: Self.task, hidden: ["title", "body"]).isEmpty)
        #expect(InspectorFields.addable(of: item, type: Self.task, hidden: ["title", "body"]).map(\.key) == ["description", "status", "priority"])
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

    // MARK: Display labels

    @Test func aCatalogueLabelReadsInTitleCase() {
        #expect(ItemTypeInfo.Field.displayLabel("Completed at") == "Completed At")
        #expect(ItemTypeInfo.Field.displayLabel("Starts at") == "Starts At")
        #expect(ItemTypeInfo.Field.displayLabel("Linked from") == "Linked From")
        #expect(ItemTypeInfo.Field.displayLabel("URL") == "URL")
        #expect(ItemTypeInfo.Field.displayLabel("Due") == "Due")
        #expect(ItemTypeInfo.Field.displayLabel("") == "")
        let field = ItemTypeInfo.Field(key: "completed_at", label: "Completed at", kind: .date(includesTime: false), declaredBy: TypeID("aic.x"))
        #expect(field.displayLabel == "Completed At")
        #expect(field.label == "Completed at")
    }

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
        #expect(hidden == ["blob_ref", "mime_type", "size_bytes", "title"])
        #expect(InspectorFields.properties(of: item, type: Self.file, hidden: hidden).map(\.key) == ["description"])
        // None of them turns up under the other properties either.
        #expect(InspectorFields.accountedFor(type: Self.file, hidden: hidden).isSuperset(of: ["blob_ref", "mime_type", "size_bytes"]))
    }

    @MainActor @Test func aMarfaNoteKeepsItsPropertiesNamedLikeAFilesFacts() async throws {
        let note = Self.item("core.note", properties: [Property(key: "size_bytes", value: .number(1))])
        let library = try await Self.marfa([note], types: [MarfaMapping.itemType(ItemType(id: "core.note", label: "Note", titleField: "title"))])
        #expect(library.hiddenPropertyKeys(of: note) == ["title"])
    }

    @Test func aFieldWithNothingInItAndNoWayToAddToItHasNoRow() {
        let list = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [Self.field("tags", "array")]))
        let empty = Self.item("aic.x")
        #expect(InspectorFields.properties(of: empty, type: list, hidden: []).isEmpty)
        let full = Self.item("aic.x", properties: [Property(key: "tags", value: .array([.string("a")]))])
        #expect(InspectorFields.properties(of: full, type: list, hidden: []).map(\.key) == ["tags"])
    }

    @Test func aWebAddressShowsAsALinkHoweverTheCatalogueSpellsItsKind() {
        let type = MarfaMapping.itemType(ItemType(id: "aic.x", label: "X", fields: [
            Self.field("home", "url"),
            Self.field("site", "string", definition: ["format": "url"]),
            Self.field("contact", "email"),
            Self.field("mail", "string", definition: ["format": "email"]),
            Self.field("notes", "string", definition: ["format": "bcp47"]),
        ]))
        let item = Self.item("aic.x", properties: [
            Property(key: "home", value: .string("https://example.com/a")),
            Property(key: "site", value: .string(" https://example.com/b ")),
            Property(key: "contact", value: .string("a@example.com")),
            Property(key: "mail", value: .string("b@example.com")),
            Property(key: "notes", value: .string("en-GB")),
        ])
        let values = Dictionary(uniqueKeysWithValues: type.fields.map { ($0.key, PropertyRow.value(of: $0, in: item)) })
        #expect(values["home"] == .url("https://example.com/a"))
        #expect(values["site"] == .url("https://example.com/b"))
        #expect(values["contact"] == .email("a@example.com"))
        #expect(values["mail"] == .email("b@example.com"))
        #expect(values["notes"] == .text("en-GB"))
    }

    // MARK: Labels for other properties

    @Test func aKeyEveryTypeLabelsTheSameKeepsThatLabel() {
        func type(_ id: String, _ label: String) -> ItemTypeInfo {
            ItemTypeInfo(id: TypeID(id), label: id, fields: [.init(key: "due", label: label, kind: .date(includesTime: false), declaredBy: TypeID(id))], titleField: nil, bodyField: nil, parent: nil)
        }
        let types = [type("aic.b", "Due B"), type("aic.a", "Due A"), type("aic.c", "Due C")]
        // The same answer whatever order the types arrive in and however the dictionary lays them out.
        for order in [types, types.reversed(), [types[1], types[2], types[0]]] {
            let catalogue = Catalogue(itemTypes: order)
            #expect(catalogue.label(ofField: "due", for: nil) == "Due A")
            #expect(catalogue.label(ofField: "due", for: TypeID("aic.x")) == "Due A")
            #expect(catalogue.label(ofField: "due", for: TypeID("aic.c")) == "Due C", "the item's own type labels it first")
            #expect(catalogue.label(ofField: "missing", for: TypeID("aic.c")) == nil)
        }
    }

    @Test func theLabelsFollowTheCatalogueWhenItsTypesChange() {
        var catalogue = Catalogue(itemTypes: [Self.task])
        #expect(catalogue.label(ofField: "priority", for: nil) == "Priority")
        catalogue.itemTypes[Self.task.id] = nil
        #expect(catalogue.label(ofField: "priority", for: nil) == nil)
    }
}
