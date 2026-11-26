import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

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
            type(text, fields: [.init(key: "status", label: "Status", kind: .status([
                StatusWord(value: "waiting", group: .notStarted), StatusWord(value: "done", group: .completed)]), declaredBy: text)]),
        ])
    }

    private static func item(_ id: String, type: TypeID = first, value: PropertyValue? = nil) -> Item {
        Item(id: ItemID(id), type: type, title: id, titleRule: .property("title"),
             properties: value.map { [Property(key: "status", value: $0)] } ?? [],
             version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
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

    @Test func aWordTheTypeDoesNotDeclareIsInvalidAndCannotBeMovedTo() {
        let item = Self.item("Text", type: Self.text, value: .string("custom_value"))
        let lanes = ItemBoardLayout.lanes(items: [item], key: "status", catalogue: Self.catalogue)
        #expect(lanes.map(\.id) == [.option("waiting"), .option("done"), .missing, .invalid])
        #expect(ItemBoardLayout.move(item, key: "status", to: .option("waiting"), catalogue: Self.catalogue) == .set(.string("waiting")))
        #expect(ItemBoardLayout.move(item, key: "status", to: .option("new_value"), catalogue: Self.catalogue) == .refused)
    }

    @Test func aMoveToALaneNamesTheTrueReasonForEachItemItLeavesAlone() {
        var binned = Self.item("binned", value: .string("todo"))
        binned.state = .trashed
        var problem = Self.item("problem", value: .string("todo"))
        problem.problem = ItemProblem(message: "Unreadable properties")
        let file = Item(
            id: ItemID("file"), type: .file, title: "file", titleRule: .property("title"), content: .file(.data, byteCount: 1),
            version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
        let items = [
            Self.item("moves", value: .string("todo")), Self.item("there", value: .string("done")),
            Self.item("review", type: Self.second, value: .string("done")), Self.item("hidden", value: .string("todo")),
            binned, problem, file,
        ]
        let library = FakeItemLibrary(items: items)
        library.catalogue = Self.catalogue
        let shown = Set(items.map(\.id)).subtracting([ItemID("hidden")])
        let ids = shown.union([ItemID("hidden"), ItemID("ghost")])

        let plan = ItemBoardLayout.movePlan(ids, key: "status", to: .option("done"), shown: shown, in: library)
        #expect(plan.changes.map(\.id) == [ItemID("moves")], "an item already in the lane is no skip, and the others move")
        var expected = BatchSkips()
        for reason in [BatchSkips.Reason.gone, .notShown, .inBin, .cantChange, .fileHasNoLane] { expected.skip(reason) }
        #expect(plan.skips == expected)
        #expect(plan.skips.message?.contains("isn’t on this board") == true)
        #expect(plan.skips.message?.contains("lane") == true)

        let wrongType = ItemBoardLayout.movePlan([ItemID("review")], key: "status", to: .option("todo"), shown: shown, in: library)
        var cantGo = BatchSkips()
        cantGo.skip(.cantMoveToLane)
        #expect(wrongType.skips == cantGo, "only an item whose type doesn’t take the lane reads as one that can’t go in it")
    }

    /// A board of rows and files, both with a `width`, where only the row's is the person's to change.
    static func widths() -> (catalogue: Catalogue, row: Item, file: Item) {
        let width = ItemTypeInfo.Field(key: "width", label: "Width", kind: .number, declaredBy: first)
        let catalogue = Catalogue(itemTypes: [
            type(first, fields: [width]),
            ItemTypeInfo(id: .file, label: "File", fields: [width], titleField: "title", bodyField: nil, parent: nil),
        ])
        let wide = Property(key: "width", value: .number(640))
        var row = item("row")
        row.properties = [wide]
        var file = Item(
            id: ItemID("file"), type: .file, title: "file", titleRule: .property("title"), content: .file(.png, byteCount: 1),
            version: ItemVersion(1), created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0))
        file.properties = [wide]
        return (catalogue, row, file)
    }

    @Test func aMixedBoardNeverClearsAFactMarfaSetsOnAFile() {
        let (catalogue, row, file) = Self.widths()
        let library = FakeItemLibrary(items: [row, file])
        library.catalogue = catalogue
        let plan = ItemBoardLayout.movePlan([row.id, file.id], key: "width", to: .missing, shown: [row.id, file.id], in: library)
        #expect(plan.changes.map(\.id) == [row.id])
        var skipped = BatchSkips()
        skipped.skip(.fileFact)
        #expect(plan.skips == skipped)
    }

    @Test func requiredFieldsCannotBeRemoved() {
        let required = Self.item("Required", type: Self.second, value: .string("review"))
        let optional = Self.item("Optional", value: .string("todo"))
        #expect(ItemBoardLayout.move(required, key: "status", to: .missing, catalogue: Self.catalogue) == .needsValue)
        #expect(ItemBoardLayout.move(optional, key: "status", to: .missing, catalogue: Self.catalogue) == .set(nil))
        #expect(ItemBoardLayout.lane(for: Self.item("Missing required", type: Self.second), key: "status", catalogue: Self.catalogue) == .missing)
    }

    @Test func readOnlyItemsAndDiagnosticLanesCannotBeMoved() {
        var archived = Self.item("Archived"); archived.state = .archived
        #expect(ItemBoardLayout.move(archived, key: "status", to: .option("done"), catalogue: Self.catalogue) == .set(.string("done")))
        var trashed = Self.item("Trashed"); trashed.state = .trashed
        var broken = Self.item("Broken"); broken.problem = ItemProblem(message: "Unreadable properties")
        for item in [trashed, broken] {
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
        #expect(ItemBoardLayout.eligibleFields(of: child, catalogue: catalogue).map(\.key) == ["status"])
        #expect(ItemBoardLayout.move(item, key: "status", to: .missing, catalogue: catalogue) == .needsValue)
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
            #expect(ItemBoardLayout.eligibleFields(of: Self.second, catalogue: catalogue).isEmpty)
            #expect(ItemBoardLayout.eligibleFields(of: Self.first, catalogue: catalogue).map(\.key) == ["status"])
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
        #expect(ItemBoardLayout.eligibleFields(of: Self.first, catalogue: catalogue).isEmpty)
        #expect(ItemBoardLayout.field("title", of: page, catalogue: catalogue) == nil)
        let lanes = ItemBoardLayout.lanes(items: [page], key: "title", catalogue: catalogue)
        #expect(lanes.map(\.id) == [.missing, .notApplicable])
        #expect(ItemBoardLayout.move(page, key: "title", to: .option("short"), catalogue: catalogue) == .refused)
        #expect(ItemBoardLayout.move(page, key: "title", to: .missing, catalogue: catalogue) == .refused)
    }

    // MARK: Mixed status fields

    private static let reading = TypeID("example.reading")
    private static let ticket = TypeID("example.ticket")

    private static func status(_ key: String, _ words: [(String, StatusGroup)], by type: TypeID) -> ItemTypeInfo.Field {
        .init(key: key, label: key, kind: .status(words.map { StatusWord(value: $0.0, group: $0.1) }), declaredBy: type)
    }

    private static var mixedCatalogue: Catalogue {
        Catalogue(itemTypes: [
            type(reading, fields: [status("reading_status", [("queued", .notStarted), ("reading", .inProgress), ("read", .completed)], by: reading)]),
            type(ticket, fields: [status("state", [("todo", .notStarted), ("doing", .inProgress), ("done", .completed), ("dropped", .canceled)], by: ticket),
                                  choice(["low", "high"], key: "priority")]),
            type(text, fields: []),
        ])
    }

    private static func mixed(_ id: String, _ type: TypeID, key: String? = nil, _ word: String? = nil) -> Item {
        var item = Self.item(id, type: type)
        if let key, let word { item.properties = [Property(key: key, value: .string(word))] }
        return item
    }

    @Test func aGroupLaneTakesCardsOnlyWhereEveryTypeHasAWord() {
        let items = [Self.mixed("a", Self.reading, key: "reading_status", "reading"), Self.mixed("b", Self.ticket, key: "state", "todo")]
        let lanes = ItemBoardLayout.lanes(items: items, key: "state", catalogue: Self.mixedCatalogue, statusGroups: true)
        let takes = Dictionary(uniqueKeysWithValues: lanes.map { ($0.id, $0.takesItems) })
        #expect(takes[.group(.inProgress)] == true)
        #expect(takes[.group(.canceled)] == false, "reading has no canceled word")
        #expect(takes[.missing] == false)
    }

    @Test func movingIntoAGroupWritesTheTypesOwnFirstWordForIt() {
        let ticket = Self.mixed("b", Self.ticket, key: "state", "todo")
        let reading = Self.mixed("a", Self.reading, key: "reading_status", "queued")
        let catalogue = Self.mixedCatalogue
        #expect(ItemBoardLayout.move(ticket, key: "state", to: .group(.completed), catalogue: catalogue) == .set(.string("done")))
        #expect(ItemBoardLayout.move(reading, key: "state", to: .group(.completed), catalogue: catalogue) == .set(.string("read")))
        #expect(ItemBoardLayout.move(ticket, key: "state", to: .group(.notStarted), catalogue: catalogue) == .unchanged)
        #expect(ItemBoardLayout.move(reading, key: "state", to: .group(.canceled), catalogue: catalogue) == .refused)
        #expect(ItemBoardLayout.move(Self.mixed("t", Self.text), key: "state", to: .group(.completed), catalogue: catalogue) == .refused)
        let library = FakeItemLibrary(items: [ticket, reading])
        library.catalogue = catalogue
        let plan = ItemBoardLayout.movePlan([ticket.id, reading.id], key: "state", to: .group(.completed), shown: [ticket.id, reading.id], in: library)
        #expect(plan.changes.map(\.key).sorted() == ["reading_status", "state"], "each item is written through its own status field")
    }

    @Test func anInvalidCardOnAMixedBoardShowsItsOwnStatusFieldEvenWithEmptyLanesHidden() {
        let items = [Self.mixed("a", Self.reading, key: "reading_status", "odd"), Self.mixed("b", Self.ticket, key: "state", "strange")]
        let catalogue = Self.mixedCatalogue
        let grouped = true
        let shown = ItemBoardLayout.lanes(items: items, key: "state", catalogue: catalogue, statusGroups: true).filter { !$0.items.isEmpty }
        #expect(shown.map(\.id) == [.invalid], "no group lane is left to show that the board groups by status")
        let keys = items.map { ItemBoardLayout.invalidValueKey(of: $0, key: "state", groupsByStatus: grouped, catalogue: catalogue) }
        #expect(keys == ["reading_status", "state"])
        #expect(ItemBoardLayout.invalidValueKey(of: items[0], key: "state", groupsByStatus: false, catalogue: catalogue) == "state")
    }

    @Test func aStoredLaneOrderPutsNewValuesLastAndIgnoresValuesThatAreGone() {
        func lane(_ word: String) -> ItemBoardLane { ItemBoardLane(id: .option(word), title: word, items: []) }
        let lanes = ["todo", "doing", "done", "review"].map(lane)
        // "review" is new here, and "waiting" and a renamed "in progress" are values this copy does not have.
        let order = ["done", "waiting", "todo", "in progress"]
        let arranged = ItemBoardLayout.arranged(lanes, order: order, hidden: nil, hidesEmpty: false)
        #expect(arranged.map(\.title) == ["done", "todo", "doing", "review"])
        #expect(ItemBoardLayout.arranged(lanes, order: [], hidden: nil, hidesEmpty: false).map(\.title) == ["todo", "doing", "done", "review"])
    }
}
