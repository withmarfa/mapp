import Foundation
import Testing
@testable import MAPP

struct ItemBoardTests {
    private static let first = TypeID("example.first")
    private static let second = TypeID("example.second")
    private static let text = TypeID("example.text")

    private static func type(_ id: TypeID, fields: [ItemTypeInfo.Field], parent: TypeID? = nil) -> ItemTypeInfo {
        ItemTypeInfo(id: id, label: id.rawValue, fields: fields, titleField: "title", bodyField: "body", parent: parent)
    }

    private static func choice(_ options: [String], required: Bool = false, key: String = "status") -> ItemTypeInfo.Field {
        .init(key: key, label: key, kind: .choice(options), declaredBy: first, required: required)
    }

    private static var catalogue: Catalogue {
        Catalogue(itemTypes: [
            type(second, fields: [choice(["review", "done"], required: true)]),
            type(first, fields: [choice(["todo", "done"]), choice(["low", "high"], key: "priority")]),
            type(text, fields: [.init(key: "status", label: "Status", kind: .text, declaredBy: text,
                                     description: "Recommended values: waiting, done")]),
        ])
    }

    private static func item(_ id: String, type: TypeID = first, value: PropertyValue? = nil) -> Item {
        Item(id: ItemID(id), type: type, title: id, titleRule: .property("title"),
             properties: value.map { [Property(key: "status", value: $0)] } ?? [],
             version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
    }

    @Test func optionOrderUsesTypeIdentifiersAndDeclarationOrder() {
        let items = [Self.item("B", type: Self.second), Self.item("A")]
        let lanes = ItemBoardLayout.lanes(items: items, key: "status", catalogue: Self.catalogue)
        #expect(lanes.map(\.id) == [.option("todo"), .option("done"), .option("review"), .missing])
        #expect(ItemBoardLayout.lanes(items: Array(items.reversed()), key: "status", catalogue: Self.catalogue) == lanes)
        #expect(lanes.first?.items.isEmpty == true)
    }

    @Test func everyItemHasExactlyOneLaneIncludingUnknownTypesAndBadValues() {
        let items = [
            Self.item("valid", value: .string("todo")),
            Self.item("missing"),
            Self.item("null", value: .null),
            Self.item("empty", value: .string("")),
            Self.item("bad choice", value: .string("elsewhere")),
            Self.item("bad shape", value: .array([.string("todo")])),
            Self.item("unknown type", type: TypeID("example.unknown"), value: .string("todo")),
        ]
        let lanes = ItemBoardLayout.lanes(items: items, key: "status", catalogue: Self.catalogue)
        #expect(lanes.flatMap(\.items).count == items.count)
        #expect(Set(lanes.flatMap(\.items).map(\.id)) == Set(items.map(\.id)))
        #expect(lanes.first { $0.id == .missing }?.items.count == 3)
        #expect(lanes.first { $0.id == .invalid }?.items.count == 2)
        #expect(lanes.first { $0.id == .notApplicable }?.items.count == 1)
    }

    @Test func eachItemsOwnChoiceDefinitionControlsItsLaneAndMoves() {
        let first = Self.item("A", value: .string("review"))
        let second = Self.item("B", type: Self.second, value: .string("review"))
        #expect(ItemBoardLayout.lane(for: first, key: "status", catalogue: Self.catalogue) == .invalid)
        #expect(ItemBoardLayout.lane(for: second, key: "status", catalogue: Self.catalogue) == .option("review"))
        #expect(ItemBoardLayout.move(first, key: "status", to: .option("review"), catalogue: Self.catalogue) == .refused)
        #expect(ItemBoardLayout.move(first, key: "status", to: .option("done"), catalogue: Self.catalogue) == .set(.string("done")))
        #expect(ItemBoardLayout.move(second, key: "status", to: .option("todo"), catalogue: Self.catalogue) == .refused)
        #expect(ItemBoardLayout.move(second, key: "status", to: .option("review"), catalogue: Self.catalogue) == .unchanged)
    }

    @Test func textRecommendationsDoNotInvalidateOtherText() {
        let item = Self.item("Text", type: Self.text, value: .string("custom_value"))
        let lanes = ItemBoardLayout.lanes(items: [item], key: "status", catalogue: Self.catalogue)
        #expect(lanes.map(\.id) == [.option("waiting"), .option("done"), .option("custom_value"), .missing])
        #expect(ItemBoardLayout.move(item, key: "status", to: .option("waiting"), catalogue: Self.catalogue) == .set(.string("waiting")))
        #expect(ItemBoardLayout.move(item, key: "status", to: .option("new_value"), catalogue: Self.catalogue) == .set(.string("new_value")))
    }

    @Test func requiredFieldsCannotBeRemoved() {
        let required = Self.item("Required", type: Self.second, value: .string("review"))
        let optional = Self.item("Optional", value: .string("todo"))
        #expect(ItemBoardLayout.move(required, key: "status", to: .missing, catalogue: Self.catalogue) == .refused)
        #expect(ItemBoardLayout.move(optional, key: "status", to: .missing, catalogue: Self.catalogue) == .set(nil))
        #expect(ItemBoardLayout.lane(for: Self.item("Missing required", type: Self.second), key: "status", catalogue: Self.catalogue) == .missing)
    }

    @Test func readOnlyItemsAndDiagnosticLanesCannotBeMoved() {
        var archived = Self.item("Archived"); archived.state = .archived
        var trashed = Self.item("Trashed"); trashed.state = .trashed
        var broken = Self.item("Broken"); broken.problem = ItemProblem(message: "Unreadable properties")
        for item in [archived, trashed, broken] {
            #expect(ItemBoardLayout.move(item, key: "status", to: .option("done"), catalogue: Self.catalogue) == .refused)
        }
        for lane in [ItemBoardLane.ID.invalid, .notApplicable, .option("")] {
            #expect(ItemBoardLayout.move(Self.item("A"), key: "status", to: lane, catalogue: Self.catalogue) == .refused)
        }
        #expect(ItemBoardLayout.move(Self.item("Unknown", type: TypeID("missing")), key: "status", to: .option("done"), catalogue: Self.catalogue) == .refused)
    }

    @Test func resolvedInheritedFieldsKeepTheirRequiredness() {
        let child = TypeID("example.child")
        let catalogue = Catalogue(itemTypes: [
            Self.type(Self.first, fields: [Self.choice(["todo", "done"])]),
            Self.type(child, fields: [Self.choice(["todo", "done"], required: true)], parent: Self.first),
        ])
        let item = Self.item("Child", type: child, value: .string("todo"))
        #expect(ItemBoardLayout.availableFields(items: [item], catalogue: catalogue).map(\.key) == ["status"])
        #expect(ItemBoardLayout.move(item, key: "status", to: .missing, catalogue: catalogue) == .refused)
    }

    @Test func fieldPickerPrefersStatusAndRejectsStaleSelections() {
        let fields = ItemBoardLayout.availableFields(items: [Self.item("A")], catalogue: Self.catalogue)
        #expect(fields.map(\.key) == ["status", "priority"])
        #expect(ItemBoardLayout.selectedField(nil, available: fields)?.key == "status")
        #expect(ItemBoardLayout.selectedField("priority", available: fields)?.key == "priority")
        #expect(ItemBoardLayout.selectedField("removed", available: fields)?.key == "status")
        #expect(ItemBoardLayout.selectedField(nil, available: []) == nil)
    }

    @Test func nonCategoricalFieldsAreNotOffered() {
        let catalogue = Catalogue(itemTypes: [Self.type(Self.first, fields: [
            .init(key: "status", label: "Status", kind: .number, declaredBy: Self.first),
            .init(key: "notes", label: "Notes", kind: .text, declaredBy: Self.first),
            Self.choice(["short", "long"], key: "title"),
        ])])
        let item = Self.item("A", value: .number(1))
        #expect(ItemBoardLayout.availableFields(items: [item], catalogue: catalogue).isEmpty)
        #expect(ItemBoardLayout.lane(for: item, key: "status", catalogue: catalogue) == .notApplicable)
    }

    @Test func equalTitlesHaveStableItemIdentityOrder() {
        var first = Self.item("b", value: .string("todo")); first.title = "Same"
        var second = Self.item("a", value: .string("todo")); second.title = "Same"
        let lanes = ItemBoardLayout.lanes(items: [first, second], key: "status", catalogue: Self.catalogue)
        #expect(lanes.first?.items.map(\.id) == [ItemID("a"), ItemID("b")])
    }

    @Test func mixedTypePageFieldsCannotBeUsedAsBoardFields() {
        for isTitle in [true, false] {
            let catalogue = Catalogue(itemTypes: [
                Self.type(Self.first, fields: [Self.choice(["todo", "done"])]),
                ItemTypeInfo(id: Self.second, label: "Page", fields: [Self.choice(["page_only"])],
                             titleField: isTitle ? "status" : "title", bodyField: isTitle ? "body" : "status", parent: nil),
            ])
            let ordinary = Self.item("Task", value: .string("todo"))
            let page = Self.item("Page", type: Self.second, value: .string("page_only"))
            #expect(ItemBoardLayout.availableFields(items: [page], catalogue: catalogue).isEmpty)
            #expect(ItemBoardLayout.availableFields(items: [ordinary, page], catalogue: catalogue).map(\.key) == ["status"])
            #expect(ItemBoardLayout.field("status", of: page, catalogue: catalogue) == nil)
            let lanes = ItemBoardLayout.lanes(items: [ordinary, page], key: "status", catalogue: catalogue)
            #expect(lanes.map(\.id) == [.option("todo"), .option("done"), .missing, .notApplicable])
            #expect(lanes.first { $0.id == .notApplicable }?.items.map(\.id) == [page.id])
            #expect(ItemBoardLayout.move(page, key: "status", to: .option("page_only"), catalogue: catalogue) == .refused)
            #expect(ItemBoardLayout.move(page, key: "status", to: .missing, catalogue: catalogue) == .refused)
            #expect(ItemBoardLayout.move(ordinary, key: "status", to: .option("done"), catalogue: catalogue) == .set(.string("done")))
        }
    }

    @Test func literalTitleAliasCannotBeUsedEvenWithACustomTitleField() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: Self.first, label: "Page", fields: [Self.choice(["short", "long"], key: "title")],
                         titleField: "heading", bodyField: "content", parent: nil),
        ])
        let page = Self.item("Page")
        #expect(ItemBoardLayout.availableFields(items: [page], catalogue: catalogue).isEmpty)
        #expect(ItemBoardLayout.field("title", of: page, catalogue: catalogue) == nil)
        let lanes = ItemBoardLayout.lanes(items: [page], key: "title", catalogue: catalogue)
        #expect(lanes.map(\.id) == [.missing, .notApplicable])
        #expect(ItemBoardLayout.move(page, key: "title", to: .option("short"), catalogue: catalogue) == .refused)
        #expect(ItemBoardLayout.move(page, key: "title", to: .missing, catalogue: catalogue) == .refused)
    }
}
