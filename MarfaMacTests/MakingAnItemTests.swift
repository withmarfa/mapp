import Foundation
import Testing
@testable import MarfaMac

/// The item kind and defaults used in Quick Add.
@Suite(.hangLimit)
struct MakingAnItemTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func defaults(_ stored: String? = nil) -> UserDefaults {
        let suite = ThrowawayDefaults.make("MakingAnItemTests")
        if let stored { suite.set(stored, forKey: ListKey.openItemsIn) }
        return suite
    }

    /// A kind with a status of four words, a kind whose status has no not-started word and which needs a field quick add
    /// cannot edit, and kinds with no status.
    private static let catalogue: Catalogue = {
        let task = TypeID("core.task")
        let odd = TypeID("test.odd")
        return Catalogue(
            itemTypes: [
                ItemTypeInfo(id: TypeID("core.note"), label: "Note", fields: [], titleField: "title", bodyField: "body", parent: nil),
                ItemTypeInfo(
                    id: task, label: "Task", plural: "Tasks",
                    fields: [
                        .init(key: "status", label: "Status", kind: .status([
                            StatusWord(value: "doing", group: .inProgress), StatusWord(value: "todo", group: .notStarted),
                            StatusWord(value: "backlog", group: .notStarted), StatusWord(value: "done", group: .completed),
                        ]), declaredBy: task),
                        .init(key: "priority", label: "Priority", kind: .choice(["low", "high"]), declaredBy: task),
                    ],
                    titleField: "title", bodyField: "body", parent: nil),
                ItemTypeInfo(
                    id: odd, label: "Odd", plural: "Odds",
                    fields: [
                        .init(key: "status", label: "Status", kind: .status([StatusWord(value: "doing", group: .inProgress)]), declaredBy: odd),
                        .init(key: "tags", label: "Tags", kind: .words, declaredBy: odd, required: true),
                        .init(key: "reference", label: "Reference", kind: .text, declaredBy: odd, required: true),
                    ],
                    titleField: "title", bodyField: "body", parent: nil),
                ItemTypeInfo(id: TypeID("test.plain"), label: "Plain", fields: [], titleField: "title", bodyField: "body", parent: nil),
                ItemTypeInfo(
                    id: FakeItemLibrary.collectionType, label: "Collection", fields: [], titleField: "title", bodyField: "body",
                    parent: nil, roles: ["container"]),
                ItemTypeInfo(id: .file, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
            ],
            edgeTypes: [])
    }()

    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(now: start)
        library.catalogue = Self.catalogue
        return library
    }

    // MARK: The kind it opens in

    private func opened(in place: PlaceView, remembered: String? = nil, asked: String? = nil) -> String? {
        let browser = Browser()
        browser.showing = place
        browser.openQuickAdd(typeID: asked, remembered: remembered, in: library())
        return browser.quickAdd.draft?.typeID
    }

    @Test func aTypesPlaceHoldsItsTypeWhateverWasUsedLast() {
        #expect(opened(in: .type(TypeID("core.task")), remembered: "test.plain") == "core.task")
        #expect(opened(in: .collections, remembered: "test.plain") == FakeItemLibrary.collectionType.rawValue)
        #expect(opened(in: .type(TypeID("core.task")), remembered: "test.plain", asked: "core.note") == "core.note", "a kind asked for wins")
    }

    // MARK: What a kind gives it

    @Test func aKindGivesItsFirstNotStartedWordAndNothingElse() {
        #expect(QuickAdd.prefill(of: "core.task", in: Self.catalogue) == ["status": .string("todo")])
        #expect(QuickAdd.prefill(of: "core.note", in: Self.catalogue).isEmpty)
        #expect(QuickAdd.prefill(of: "test.odd", in: Self.catalogue).isEmpty, "no not-started word is no word to give")
        #expect(QuickAdd.prefill(of: "no.such", in: Self.catalogue).isEmpty)
    }

    @Test func theStatusIsAChipButNotTheirWorkToKeep() throws {
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library())
        let draft = try #require(browser.quickAdd.draft)
        #expect(draft.properties == ["status": .string("todo")])
        #expect(QuickAdd.shownChips(draft, in: Self.catalogue) == [.field("status")])
        #expect(!browser.quickAdd.holdsContent, "a panel with only its kind's own values is empty")
        browser.putAwayQuickAdd()
        #expect(browser.quickAdd.draft == nil)
    }

    @Test func theStatusLeavesWithItsKindUnlessThePersonChangedIt() {
        let library = library()
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.chooseQuickAddType("core.note", in: library)
        #expect(browser.quickAdd.draft?.properties.isEmpty == true)
        browser.chooseQuickAddType("core.task", in: library)
        browser.quickAdd.draft?.properties["status"] = .string("doing")
        #expect(browser.quickAdd.holdsContent)
        browser.chooseQuickAddType("test.odd", in: library)
        #expect(browser.quickAdd.draft?.properties["status"] == .string("doing"), "a word the person chose stays")
    }

    @Test func aStatusThePersonRemovedStaysRemovedWhenTheKindChanges() throws {
        let library = library()
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.draft?.remove(.field("status"), in: Self.catalogue)
        #expect(browser.quickAdd.draft?.properties.isEmpty == true)
        browser.chooseQuickAddType("core.note", in: library)
        browser.chooseQuickAddType("core.task", in: library)
        #expect(browser.quickAdd.draft?.properties.isEmpty == true, "the person took the status away, so no kind gives it again")
        #expect(try #require(browser.quickAdd.draft).typedProperties.isEmpty)
    }

    @Test func theStatusTheKindGaveIsAddedWithTheItem() async throws {
        let library = library()
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.draft?.title = "Pack the samples"
        let id = try #require(await browser.saveQuickAdd(in: library, undoManager: nil, defaults: defaults()))
        #expect(library.items.first { $0.id == id }?.properties.first { $0.key == "status" }?.value == .string("todo"))
    }

    @Test func aRequiredFieldQuickAddCannotEditIsNamedAndNeverHoldsBackAdd() {
        let fields = QuickAdd.unsettableRequired(of: "test.odd", in: Self.catalogue)
        #expect(fields.map(\.key) == ["tags"])
        let note = QuickAdd.unsettableNote(fields)
        #expect(note?.contains("Tags") == true && note?.contains("refused") == true, "the note says what will happen, before anything is typed")
        #expect(QuickAdd.unsettableNote([]) == nil)
        #expect(QuickAdd.unsettableRequired(of: "core.task", in: Self.catalogue).isEmpty)
        var draft = QuickAdd.Draft(typeID: "test.odd")
        draft.title = "Needs a reference"
        draft.properties["reference"] = .string("R1")
        #expect(QuickAdd.canSave(draft, in: library()))
    }

    // MARK: Empty places

}
