import Foundation
import Testing
@testable import MAPP

extension Browser {
    /// Quick add as a person uses it: open the panel, type, add.
    @discardableResult
    func quickAdded(_ title: String, typeID: String? = nil, body: String = "", in library: any ItemLibrary) async -> ItemID? {
        openQuickAdd(typeID: typeID, in: library)
        quickAdd.draft?.title = title
        quickAdd.draft?.body = body
        return await saveQuickAdd(in: library, undoManager: nil)
    }
}

struct QuickAddTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func anItemIsMadeWithItsTitleTextAndPropertiesAndOpensWithTheCaretWhereItWas() async throws {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.searchText = "Something"
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.draft?.title = "Call Sam"
        browser.quickAdd.draft?.body = "Ask about the date"
        browser.quickAdd.draft?.caret = 9
        browser.quickAdd.draft?.properties = ["priority": .string("high")]
        let id = try #require(await browser.saveQuickAdd(in: library, undoManager: nil))

        let item = try #require(library.item(id))
        #expect(item.type.rawValue == "core.task")
        #expect(item.title == "Call Sam")
        #expect(library.bodies[id] == "Ask about the date")
        #expect(item.value(of: "priority") == .string("high"))
        #expect(!browser.quickAdd.isPresented)
        #expect(browser.quickAdd.draft == nil)
        #expect(browser.selection == [id])
        #expect(!browser.isSearching)
        #expect(browser.focusRequest == .page)
        #expect(browser.focusCaret == .after("Ask about"))
    }

    @Test func theCaretGoesToTheEndWhereItWasThereOrTheTextIsLong() {
        #expect(PageCaret(offset: nil, in: "Text") == .end)
        #expect(PageCaret(offset: 4, in: "Text") == .end)
        #expect(PageCaret(offset: 2, in: "Text") == .after("Te"))
        let long = String(repeating: "a", count: PageCaret.limit + 10)
        #expect(PageCaret(offset: PageCaret.limit + 1, in: long) == .end)
    }

    @Test func anItemWithNoTextOpensWithItsTitleReady() async throws {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        let id = try #require(await browser.quickAdded("Launch", typeID: "test.project", in: library))
        #expect(browser.selection == [id])
        #expect(browser.focusRequest == .title)
        #expect(browser.focusCaret == nil)
    }

    @Test func createMoreClearsWhatWasTypedAndKeepsTheKindAndPlace() async throws {
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Launch", titleRule: .property("title"),
            version: ItemVersion(1), created: start, modified: start)
        let library = FakeItemLibrary(items: [project], now: start)
        library.parentCandidates["core.task"] = [project.id]
        let browser = Browser()
        browser.sidebarItem = .collection(project.id)
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.createsMore = true
        browser.quickAdd.draft?.properties = ["priority": .string("low")]
        let id = try #require(await browser.quickAdded("Book venue", in: library))

        #expect(library.item(id)?.parentID == project.id)
        #expect(browser.quickAdd.isPresented)
        let draft = try #require(browser.quickAdd.draft)
        #expect(draft.title.isEmpty && draft.body.isEmpty && draft.properties.isEmpty)
        #expect(draft.typeID == "core.task")
        #expect(draft.parentID == project.id)
        #expect(browser.selection.isEmpty, "nothing opens while more are made")
    }

    @Test func aRefusedCreateKeepsEverythingAsTyped() async throws {
        let library = FakeItemLibrary(now: start)
        library.refusesCreations = true
        let browser = Browser()
        browser.openQuickAdd(in: library)
        browser.quickAdd.draft?.title = "Plan"
        browser.quickAdd.draft?.body = "Steps"
        let typed = browser.quickAdd.draft
        #expect(await browser.saveQuickAdd(in: library, undoManager: nil) == nil)
        #expect(browser.quickAdd.isPresented)
        #expect(browser.quickAdd.draft == typed)
        #expect(!library.notices.waiting.isEmpty)
    }

    @Test func nothingEmptyIsWritten() async {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        #expect(await browser.quickAdded("  ", body: "Text", in: library) == nil)
        #expect(library.items.isEmpty && library.created.isEmpty)
        #expect(await browser.quickAdded("Untitled", typeID: String(TypeID.file.rawValue), in: library) == nil, "a file needs a file")
        #expect(library.addedFiles.isEmpty)
    }

    @Test func puttingThePanelAwayKeepsTheDraftForTheWindow() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.draft?.title = "Half a thought"
        browser.putAwayQuickAdd()
        #expect(!browser.quickAdd.isPresented)
        browser.openQuickAdd(in: library)
        #expect(browser.quickAdd.draft?.title == "Half a thought")
        #expect(browser.quickAdd.draft?.typeID == "core.task")
        #expect(library.items.isEmpty && library.created.isEmpty)

        browser.palette = .commands
        #expect(!browser.quickAdd.isPresented, "one panel is out at a time")
        #expect(browser.quickAdd.draft?.title == "Half a thought")
    }

    @Test func aDraftLeftAsTheWindowClosesGoesToTheClipboard() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(in: library)
        browser.quickAdd.draft?.title = "Idea"
        browser.quickAdd.draft?.body = "More of it"
        browser.putAwayQuickAdd()
        browser.quickAdd.handOff(to: library.notices, because: .closed)
        #expect(browser.quickAdd.draft == nil)
        var clipboard: [String] = []
        let notice = library.notices.show(in: UUID()) { clipboard.append($0) }
        #expect(notice?.isNotKept == true)
        #expect(clipboard == ["Idea\n\nMore of it"])
    }

    @Test func aDraftLeftAsTheLibraryChangesGoesToTheClipboardAndSaysSo() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(in: library)
        browser.quickAdd.draft?.title = "Idea"
        browser.quickAdd.handOff(to: library.notices, because: .libraryChanged)
        #expect(browser.quickAdd.draft == nil)
        let notice = library.notices.show(in: UUID()) { _ in }
        #expect(notice?.text == "Idea")
        #expect(notice?.message.hasPrefix("The window changed to another library before the item was added.") == true)
    }

    @Test func aFileBeingAddedIsNotHandedOffAsTheWindowCloses() async throws {
        let library = FakeItemLibrary(now: start)
        let (release, released) = AsyncStream<Void>.makeStream()
        library.sendingFile = { for await _ in release { break } }
        let browser = Browser()
        browser.openQuickAdd(typeID: TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.file = QuickAdd.File(name: "photo.png", data: Data("png".utf8))
        browser.quickAdd.draft?.title = "Holiday"
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        #expect(await eventually { browser.quickAdd.isSaving })
        browser.quickAdd.handOff(to: library.notices, because: .closed)
        #expect(library.notices.waiting.isEmpty, "the file and its title are being added")
        released.yield()
        #expect(await saving.value != nil)
        #expect(library.addedFiles.first?.title == "Holiday")
    }

    @Test func textTypedWhileAFileIsAddedIsHandedOffAsTheWindowCloses() async throws {
        let library = FakeItemLibrary(now: start)
        let (release, released) = AsyncStream<Void>.makeStream()
        library.sendingFile = { for await _ in release { break } }
        let browser = Browser()
        browser.openQuickAdd(typeID: TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.file = QuickAdd.File(name: "photo.png", data: Data("png".utf8))
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        #expect(await eventually { browser.quickAdd.isSaving })
        browser.quickAdd.draft?.title = "Typed meanwhile"
        browser.quickAdd.handOff(to: library.notices, because: .closed)
        #expect(library.notices.waiting.map(\.text) == ["Typed meanwhile"])
        released.yield()
        _ = await saving.value
    }

    @Test func textAFileCannotKeepStaysInSightAndHoldsTheFileBack() async throws {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.note", in: library)
        browser.quickAdd.draft?.title = "Holiday"
        browser.quickAdd.draft?.body = "Where we went"
        browser.chooseQuickAddType(TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.file = QuickAdd.File(name: "photo.png", data: Data("png".utf8))
        let draft = try #require(browser.quickAdd.draft)
        #expect(QuickAdd.holdsTextItCannotKeep(draft, in: library.catalogue))
        #expect(QuickAdd.showsBody(draft, in: library.catalogue))
        #expect(!QuickAdd.canSave(draft, in: library.catalogue))

        browser.quickAdd.createsMore = true
        #expect(await browser.saveQuickAdd(in: library, undoManager: nil) == nil)
        #expect(library.addedFiles.isEmpty)
        #expect(browser.quickAdd.draft?.body == "Where we went")

        browser.quickAdd.draft?.body = ""
        #expect(await browser.saveQuickAdd(in: library, undoManager: nil) != nil)
        #expect(library.addedFiles.count == 1)
    }

    @Test func textAKindWithoutTextCannotKeepStaysInSightAndHoldsTheItemBack() async throws {
        let library = FakeItemLibrary(now: start)
        let place = TypeID("test.place")
        library.catalogue.itemTypes[place] = ItemTypeInfo(
            id: place, label: "Place", fields: [], titleField: "title", bodyField: nil, parent: nil)
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.note", in: library)
        browser.quickAdd.draft?.title = "Lisbon"
        browser.chooseQuickAddType(place.rawValue, in: library)
        var draft = try #require(browser.quickAdd.draft)
        #expect(!QuickAdd.showsBody(draft, in: library.catalogue), "no text, so no field for it")
        #expect(QuickAdd.canSave(draft, in: library.catalogue))

        browser.quickAdd.draft?.body = "Typed as a note"
        draft = try #require(browser.quickAdd.draft)
        #expect(QuickAdd.showsBody(draft, in: library.catalogue))
        #expect(!QuickAdd.canSave(draft, in: library.catalogue))
        #expect(await browser.saveQuickAdd(in: library, undoManager: nil) == nil)
        #expect(library.created.isEmpty)

        browser.chooseQuickAddType("core.note", in: library)
        draft = try #require(browser.quickAdd.draft)
        #expect(!QuickAdd.holdsTextItCannotKeep(draft, in: library.catalogue))
        #expect(QuickAdd.canSave(draft, in: library.catalogue))
    }

    @Test func anEmptyDraftTellsNothingAsTheWindowCloses() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(in: library)
        browser.quickAdd.handOff(to: library.notices, because: .closed)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aFileIsAddedAsAnItemOfItsOwnAndOpens() async throws {
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Launch", titleRule: .property("title"),
            version: ItemVersion(1), created: start, modified: start)
        let library = FakeItemLibrary(items: [project], now: start)
        let browser = Browser()
        browser.openQuickAdd(typeID: TypeID.file.rawValue, in: library)
        let data = Data("png".utf8)
        browser.quickAdd.draft?.file = QuickAdd.File(name: "photo.png", data: data)
        browser.quickAdd.draft?.title = "Holiday"
        let id = try #require(await browser.saveQuickAdd(in: library, undoManager: nil))

        let added = try #require(library.addedFiles.first)
        #expect(added.name == "photo.png" && added.data == data && added.title == "Holiday")
        #expect(browser.selection == [id])
        #expect(browser.quickAdd.draft == nil)
    }

    @Test func aRefusedFileKeepsTheDraft() async {
        let library = FakeItemLibrary(now: start)
        library.refusesFiles = true
        let browser = Browser()
        browser.openQuickAdd(typeID: TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.file = QuickAdd.File(name: "a.pdf", data: Data("pdf".utf8))
        #expect(await browser.saveQuickAdd(in: library, undoManager: nil) == nil)
        #expect(browser.quickAdd.draft?.file?.name == "a.pdf")
        #expect(browser.quickAdd.isPresented)
    }

    @Test func theKindIsTheOneChosenThenTheLastUsedThenThePlacesThenANote() {
        let library = FakeItemLibrary(now: start)
        func kind(remembered: String? = nil, place: SidebarItem = .allNotes, chosen: String? = nil) -> String? {
            let browser = Browser()
            browser.sidebarItem = place
            browser.openQuickAdd(typeID: chosen, remembered: remembered, in: library)
            return browser.quickAdd.draft?.typeID
        }
        #expect(kind() == "core.note")
        #expect(kind(place: .itemType("core.task")) == "core.task")
        #expect(kind(remembered: "test.project", place: .itemType("core.task")) == "test.project")
        #expect(kind(remembered: "test.project", chosen: "core.task") == "core.task")
        #expect(kind(remembered: "no.such") == "core.note")
    }

    @Test func changingTheKindDropsWhatItCannotTake() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.openQuickAdd(typeID: "core.task", in: library)
        browser.quickAdd.draft?.title = "Kept"
        browser.quickAdd.draft?.properties = ["priority": .string("high")]
        browser.chooseQuickAddType("core.note", in: library)
        #expect(browser.quickAdd.draft?.title == "Kept")
        #expect(browser.quickAdd.draft?.properties.isEmpty == true)
    }

    @Test func openingQuickAddLeavesSettingsAndPutsThePaletteAway() {
        let library = FakeItemLibrary(now: start)
        let browser = Browser()
        browser.showSettings()
        browser.palette = .commands
        browser.openQuickAdd(in: library)
        #expect(!browser.showsSettings)
        #expect(browser.palette == nil)
        #expect(browser.quickAdd.isPresented)
    }

    @Test func theChipsLeadWithTheSidebarsKindsAndFile() {
        let library = FakeItemLibrary(now: start)
        let types = QuickAdd.types(in: library)
        let (chips, more) = QuickAdd.chips(types, shown: [TypeID("core.task"), TypeID("core.note")], chosen: "test.project")
        #expect(chips.map(\.id.rawValue) == ["core.task", "core.note", TypeID.file.rawValue, "test.project"])
        #expect(more.isEmpty)
        #expect(QuickAdd.chips(types, shown: [], chosen: nil).chips.map(\.id.rawValue) == ["core.note", TypeID.file.rawValue])
    }

    @Test func pinnedFieldsAreKeptForEachLibraryAndKind() {
        var pins = QuickAdd.pinning("priority", true, typeID: "core.task", library: "a", in: [:])
        pins = QuickAdd.pinning("due_at", true, typeID: "core.task", library: "a", in: pins)
        pins = QuickAdd.pinning("priority", true, typeID: "core.task", library: "b", in: pins)
        let read = QuickAdd.pins(from: QuickAdd.text(of: pins))
        #expect(read["a"]?["core.task"] == ["priority", "due_at"])
        #expect(QuickAdd.pinning("priority", false, typeID: "core.task", library: "b", in: read)["b"] == nil)
        #expect(QuickAdd.pins(from: "").isEmpty)
    }

    // MARK: Waiting for the library

    @Test func aLibraryThatShowsTheItemLaterOpensItWhenItArrives() async throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(await browser.quickAdded("Later", in: library))
        #expect(browser.selection.isEmpty)
        #expect(!browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)
        #expect(browser.newItem != nil, "nothing is known of it yet")

        library.deliverCreated()
        #expect(browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)
        #expect(browser.newItem == nil)
        #expect(browser.selection == [id])
        #expect(browser.focusRequest == .title)
    }

    @Test func aCreateRefusedLaterOpensNothing() async throws {
        let library = FakeItemLibrary(now: start)
        library.holdsCreations = true
        let browser = Browser()
        let id = try #require(await browser.quickAdded("Refused", in: library))
        library.refusedCreations.insert(id)
        #expect(browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)
        #expect(browser.newItem == nil)
        #expect(browser.selection.isEmpty)
    }

    @Test func anItemAwaitedIsNotCarriedIntoTheNextLibrary() async throws {
        let old = FakeItemLibrary(now: start)
        old.holdsCreations = true
        let browser = Browser()
        browser.adopt(old)
        _ = try #require(await browser.quickAdded("Old", in: old))
        #expect(browser.newItem != nil)

        browser.adopt(FakeItemLibrary(now: start))
        #expect(browser.newItem == nil)
    }
}
