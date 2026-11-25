import Foundation
import Testing
@testable import MarfaMac

/// The new-item line: what its words become, what Add sends, and what stays when the library will not take it.
@MainActor
@Suite(.hangLimit)
struct NewItemLineTests {
    static let start = NewItemTextTests.now
    static let calendar = NewItemTextTests.calendar()
    static let british = Locale(identifier: "en_GB")

    /// The test catalogue, with a due day on tasks and a bookmark kind, as a server's catalogue has them.
    static let catalogue: Catalogue = {
        let base = FakeItemLibrary.testCatalogue
        let task = MarfaMapping.taskType
        let bookmark = MarfaMapping.bookmarkType
        var types = base.itemTypes.values.filter { $0.id != task }
        types.append(ItemTypeInfo(
            id: task, label: "Task",
            fields: [
                ItemTypeInfo.Field(key: "status", label: "Status", kind: .choice(["todo", "done"]), declaredBy: task),
                ItemTypeInfo.Field(key: MarfaMapping.dueField, label: "Due", kind: .date(includesTime: false), declaredBy: task),
            ], titleField: "title", bodyField: "body", parent: nil))
        types.append(ItemTypeInfo(
            id: bookmark, label: "Bookmark",
            fields: [ItemTypeInfo.Field(key: MarfaMapping.urlField, label: "URL", kind: .text, declaredBy: bookmark, required: true)],
            titleField: "title", bodyField: "body", parent: nil))
        return Catalogue(itemTypes: types, edgeTypes: Array(base.edgeTypes.values))
    }()

    static func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(now: start)
        library.catalogue = catalogue
        library.serverKey = "line-tests"
        return library
    }

    static func line(kind: String = "core.task", in library: FakeItemLibrary) -> Browser {
        let browser = Browser()
        browser.openNewItem(kind: kind, form: .line, in: library)
        return browser
    }

    /// Types `text` into the line as a person does, a word at a time, so each change is read as it comes.
    static func type(_ text: String, into browser: Browser, in library: any ItemLibrary) {
        let old = browser.quickAdd.draft?.title ?? ""
        browser.quickAdd.draft?.title = old + text
        browser.lineTextChanged(from: old, in: library)
    }

    static func add(_ browser: Browser, in library: any ItemLibrary, undoManager: UndoManager? = nil) async -> ItemID? {
        await browser.saveQuickAdd(
            in: library, undoManager: undoManager, opening: false, now: start, calendar: calendar, locale: british)
    }

    @Test func aPastedAddressMakesABookmarkOfIt() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("https://example.com/read", into: browser, in: library)
        let draft = try #require(browser.quickAdd.draft)
        #expect(draft.typeID == MarfaMapping.bookmarkType.rawValue)
        #expect(draft.properties[MarfaMapping.urlField] == .string("https://example.com/read"))
        #expect(draft.title.isEmpty)
        #expect(QuickAdd.linePlaceholder(draft, in: library.catalogue) == "Title (optional)")

        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.type == MarfaMapping.bookmarkType)
        #expect(library.item(id)?.title == "", "a bookmark's title may be left out")
    }

    @Test func anAddressTypedAfterWordsStaysText() {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Read ", into: browser, in: library)
        Self.type("https://example.com", into: browser, in: library)
        #expect(browser.quickAdd.draft?.typeID == "core.task")
        #expect(browser.quickAdd.draft?.title == "Read https://example.com")
    }

    @Test func tagsBecomeTokensAndGoInTheOneCreate() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Call #work ", into: browser, in: library)
        #expect(browser.quickAdd.draft?.tags == ["work"])
        #expect(browser.quickAdd.draft?.title == "Call ")
        Self.type("about Issue #12 #home", into: browser, in: library)
        #expect(browser.quickAdd.draft?.tags == ["work"], "the last tag waits for a space or Add")

        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Call about Issue #12")
        #expect(library.createdTags[id] == ["work", "home"])
    }

    @Test func aDayTypedBecomesTheTasksDueDay() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Pay rent Fri 27 Nov", into: browser, in: library)
        let typed = try #require(browser.quickAdd.draft)
        let found = try #require(QuickAdd.foundDay(
            in: typed, catalogue: library.catalogue, now: Self.start, calendar: Self.calendar, locale: Self.british))
        #expect(found.field.key == MarfaMapping.dueField)

        let id = try #require(await Self.add(browser, in: library))
        let item = try #require(library.item(id))
        #expect(item.title == "Pay rent")
        #expect(item.properties.first { $0.key == MarfaMapping.dueField }?.value == .string("2026-11-27"))
    }

    @Test func aDayTakenBackStaysText() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Read 27/11 report", into: browser, in: library)
        browser.declineLineDay("27/11")
        let id = try #require(await Self.add(browser, in: library))
        let item = try #require(library.item(id))
        #expect(item.title == "Read 27/11 report")
        #expect(item.properties.first { $0.key == MarfaMapping.dueField } == nil)
    }

    @Test func aKindWithNoDayKeepsTheDayAsText() async throws {
        let library = Self.library()
        let browser = Self.line(kind: "core.note", in: library)
        Self.type("Notes from Fri 27 Nov", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Notes from Fri 27 Nov")
    }

    @Test func theInRowSetsTheTier() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        #expect(browser.quickAdd.draft?.tier == .library)
        browser.quickAdd.draft?.tier = .feed
        Self.type("Into the Feed", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.tier == .feed)
        #expect(browser.quickAdd.draft?.tier == .feed, "the next item goes to the same place")
    }

    @Test func addKeepsTheLineOpenWithTheSameKindEmptyAndSaysWhatWasAdded() async throws {
        let library = Self.library()
        let browser = Self.line(kind: "test.project", in: library)
        Self.type("Garden", into: browser, in: library)
        _ = try #require(await Self.add(browser, in: library))
        #expect(browser.quickAdd.isPresented)
        #expect(browser.quickAdd.form == .line)
        #expect(browser.quickAdd.draft?.typeID == "test.project")
        #expect(browser.quickAdd.draft?.title == "")
        #expect(browser.quickAdd.lastAdded == "Added “Garden”")
        #expect(NewItemRecents.stored(for: library.serverKey, in: browser.defaults).kinds.first == "test.project")
    }

    @Test func aRequiredValueTheLineCannotTakeHandsTheDraftToTheTextForm() async throws {
        let library = Self.library()
        let browser = Self.line(kind: MarfaMapping.bookmarkType.rawValue, in: library)
        Self.type("No address yet", into: browser, in: library)
        #expect(await Self.add(browser, in: library) == nil)
        #expect(browser.quickAdd.form == .text)
        #expect(browser.quickAdd.draft?.title == "No address yet")
        #expect(library.items.isEmpty && library.created.isEmpty)
    }

    @Test func aBodyAloneMakesAnItemWhereTheTitleMayBeLeftOut() async throws {
        let library = Self.library()
        let browser = Browser()
        browser.openNewItem(kind: "core.note", form: .text, in: library)
        browser.quickAdd.draft?.body = "Only text"
        let id = try #require(await browser.saveQuickAdd(in: library, undoManager: nil))
        #expect(library.bodies[id] == "Only text")
    }

    @Test func aCreateRefusedAfterAddComesBackAsTyped() async throws {
        let library = Self.library()
        library.holdsCreations = true
        let browser = Self.line(in: library)
        Self.type("Refused #work ", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        #expect(browser.quickAdd.draft?.title == "")

        library.refusedCreations = [id]
        browser.finishNewItems(in: library)
        #expect(browser.quickAdd.draft?.title == "Refused")
        #expect(browser.quickAdd.draft?.tags == ["work"])
        #expect(browser.quickAdd.lastAdded == "The item wasn’t added. What you typed is back.")
    }

    @Test func aCreateTheLibraryRefusesAtOnceKeepsEverythingTyped() async {
        let library = Self.library()
        library.refusesCreations = true
        let browser = Self.line(in: library)
        Self.type("Stays #home ", into: browser, in: library)
        #expect(await Self.add(browser, in: library) == nil)
        #expect(browser.quickAdd.draft?.title == "Stays")
        #expect(browser.quickAdd.draft?.tags == ["home"])
        #expect(library.notices.waiting.last?.title == "Can’t Create Item")
    }

    @Test func aDraftTypedAsTheWindowClosesIsTheNextLinesInThatLibrary() {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Unfinished", into: browser, in: library)
        browser.quickAdd.leave(because: .closed, telling: library.notices)

        let next = Browser()
        next.quickAdd.drafts = browser.quickAdd.drafts
        next.openNewItem(form: .line, in: library)
        #expect(next.quickAdd.draft?.title == "Unfinished")

        let other = Self.library()
        other.serverKey = "another"
        let elsewhere = Browser()
        elsewhere.quickAdd.drafts = browser.quickAdd.drafts
        elsewhere.openNewItem(form: .line, in: other)
        #expect(elsewhere.quickAdd.draft?.title == "", "a draft names its own library's items and fields")
    }

    @Test func newOpensChoosesTheFormAndAKindTheLineCannotMakeOpensTheTextForm() {
        let library = Self.library()
        let browser = Browser()
        browser.defaults.set(NewOpens.textForm.rawValue, forKey: NewOpens.key)
        browser.openNewItem(in: library)
        #expect(browser.quickAdd.form == .text)
        browser.putAwayQuickAdd()

        browser.defaults.set(NewOpens.line.rawValue, forKey: NewOpens.key)
        browser.openNewItem(in: library)
        #expect(browser.quickAdd.form == .line)

        browser.defaults.set("someLaterWord", forKey: NewOpens.key)
        #expect(NewOpens.stored(in: browser.defaults) == .line)
    }

    @Test func newOpensSyncsAndRecentsStayOnThisMac() {
        #expect(PreferencesMap.synced.contains { $0.key == NewOpens.key })
        #expect(PreferencesMap.staysOnMac.contains(NewItemRecents.key))
        #expect(!PreferencesMap.synced.contains { $0.key == NewItemRecents.key })
    }

    @Test func recentsPutTheLastFirstAndKeepEachLibraryApart() throws {
        let defaults = ThrowawayDefaults.make("NewItemLineTests.recents")
        let parent = ItemID.mint()
        NewItemRecents.remember(kind: "core.note", tags: ["a"], parent: nil, for: "one", in: defaults)
        NewItemRecents.remember(kind: "core.task", tags: ["b", "a"], parent: parent, for: "one", in: defaults)
        let recents = NewItemRecents.stored(for: "one", in: defaults)
        #expect(recents.kinds == ["core.task", "core.note"])
        #expect(recents.tags == ["b", "a"])
        #expect(recents.parents == [parent])
        #expect(NewItemRecents.stored(for: "two", in: defaults) == NewItemRecents())

        for index in 0..<10 { NewItemRecents.remember(kind: "k\(index)", tags: [], parent: nil, for: "one", in: defaults) }
        #expect(NewItemRecents.stored(for: "one", in: defaults).kinds.count == NewItemRecents.limit)

        defaults.set(Data("not json".utf8), forKey: NewItemRecents.key)
        #expect(NewItemRecents.stored(for: "one", in: defaults) == NewItemRecents())
        #expect(defaults.array(forKey: NewItemRecents.setAsideKey) as? [Data] == [Data("not json".utf8)])
    }
}

/// The line's Add against the real library: one undo step named as every new item is, and the toast's words.
@MainActor
@Suite(.hangLimit)
struct NewItemLineUndoTests {
    @Test func eachAddIsOneNewItemStepThatItsUndoTakesBack() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { library.isLoaded })
        let undo = UndoManager()
        undo.groupsByEvent = false
        let browser = Browser()
        browser.adopt(library)
        browser.openNewItem(kind: "core.note", form: .line, in: library)

        browser.quickAdd.draft?.title = "First"
        _ = try #require(await browser.saveQuickAdd(in: library, undoManager: undo, opening: false))
        #expect(undo.undoActionName == "New Item")
        #expect(browser.quickAdd.lastAdded == "Added “First”")
        let first = try #require(browser.quickAdd.lastUndo)

        browser.quickAdd.draft?.title = "Second"
        _ = try #require(await browser.saveQuickAdd(in: library, undoManager: undo, opening: false))
        #expect(!first.isCurrent, "a later add ends the first one's Undo")
        let second = try #require(browser.quickAdd.lastUndo)

        second.perform()
        #expect(undo.redoActionName == "New Item")
        #expect(undo.canUndo, "only the second add was taken back")
        #expect(undo.undoActionName == "New Item")
        undo.undo()
        #expect(!undo.canUndo, "two adds were two steps")
    }
}
