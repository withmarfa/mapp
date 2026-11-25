import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// The new-item line: what it reads in the words, which stay as typed until Add, what Add sends, and what stays when
/// the library will not take it.
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

    /// Types `text` a word at a time, each with the space after it, as a person types a sentence.
    static func typeWords(_ text: String, into browser: Browser, in library: any ItemLibrary) {
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init).enumerated() {
            type((word.offset == 0 ? "" : " ") + word.element, into: browser, in: library)
        }
    }

    /// Sets the title to `text` in one edit, as Select All and Delete, or a paste over a selection, does.
    static func replace(with text: String, in browser: Browser, in library: any ItemLibrary) {
        let old = browser.quickAdd.draft?.title ?? ""
        browser.quickAdd.draft?.title = text
        browser.lineTextChanged(from: old, in: library)
    }

    /// A project a task may be made under.
    static func parent(in library: FakeItemLibrary) -> ItemID {
        let project = Item(
            id: .mint(), type: TypeID("test.project"), title: "Lisbon fair", name: "Lisbon fair", titleRule: .property("title"),
            version: ItemVersion(1), created: start, modified: start)
        library.items.append(project)
        library.parentCandidates["core.task"] = [project.id]
        return project.id
    }

    /// What the line reads in the words now, as it shows them.
    static func reads(_ browser: Browser, in library: any ItemLibrary) -> [QuickAdd.ReadWord] {
        guard let draft = browser.quickAdd.draft else { return [] }
        return QuickAdd.lineReads(draft, finishing: false, in: library, now: start, calendar: calendar, locale: british)
    }

    /// The chips the line shows now.
    static func chips(_ browser: Browser, in library: any ItemLibrary) -> [QuickAdd.Chip] {
        guard let draft = browser.quickAdd.draft else { return [] }
        return QuickAdd.lineChips(draft, reads: reads(browser, in: library), in: library.catalogue)
    }

    /// Delete on a chip.
    static func decline(_ chip: QuickAdd.Chip, in browser: Browser, in library: any ItemLibrary) -> Bool {
        browser.declineLineChip(chip, in: library, now: start, calendar: calendar, locale: british)
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
        #expect(draft.title == "https://example.com/read", "the address stays as typed")
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.urlField)])

        let id = try #require(await Self.add(browser, in: library))
        let item = try #require(library.item(id))
        #expect(item.type == MarfaMapping.bookmarkType)
        #expect(item.title == "", "a bookmark's title may be left out")
        #expect(item.properties.first { $0.key == MarfaMapping.urlField }?.value == .string("https://example.com/read"))
    }

    @Test func anAddressTypedAfterWordsStaysText() {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Read ", into: browser, in: library)
        Self.type("https://example.com", into: browser, in: library)
        #expect(browser.quickAdd.draft?.typeID == "core.task")
        #expect(browser.quickAdd.draft?.title == "Read https://example.com")
    }

    @Test func tagsAreChipsWhileTheirWordsStayUntilAdd() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Call #work ", into: browser, in: library)
        #expect(browser.quickAdd.draft?.title == "Call #work ")
        #expect(browser.quickAdd.draft?.tags.isEmpty == true, "a read tag is not in the draft until Add")
        #expect(Self.chips(browser, in: library) == [.tag("work")])
        Self.type("about Issue #12 #home", into: browser, in: library)
        #expect(Self.chips(browser, in: library) == [.tag("work")], "the last tag waits for a space or Add")

        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Call about Issue #12")
        #expect(library.createdTags[id] == ["work", "home"])
    }

    @Test func aDayTypedBecomesTheTasksDueDay() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Pay rent Fri 27 Nov", into: browser, in: library)
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.dueField)])
        #expect(browser.quickAdd.draft?.title == "Pay rent Fri 27 Nov")

        let id = try #require(await Self.add(browser, in: library))
        let item = try #require(library.item(id))
        #expect(item.title == "Pay rent")
        #expect(item.properties.first { $0.key == MarfaMapping.dueField }?.value == .string("2026-11-27"))
    }

    @Test func deleteOnAReadChipKeepsItsWordsAsText() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.typeWords("Read 27/11 report ", into: browser, in: library)
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.dueField)])
        #expect(Self.decline(.field(MarfaMapping.dueField), in: browser, in: library))
        #expect(browser.quickAdd.draft?.title == "Read 27/11 report ")
        #expect(Self.chips(browser, in: library).isEmpty)
        Self.type("now", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        let item = try #require(library.item(id))
        #expect(item.title == "Read 27/11 report now")
        #expect(item.properties.first { $0.key == MarfaMapping.dueField } == nil)
    }

    @Test func theChipsStandInTheOrderTheirWordsWereTyped() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.typeWords("Send the second proofs to Calverts fri #print @lis", into: browser, in: library)
        let draft = try #require(browser.quickAdd.draft)
        #expect(draft.title == "Send the second proofs to Calverts fri #print @lis")
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.dueField), .tag("print")])
        let read = QuickAdd.withReads(draft, Self.reads(browser, in: library))
        #expect(read.properties[MarfaMapping.dueField] == .string("2026-11-27"))
        #expect(read.tags == ["print"])
    }

    @Test func noTypedWordLeavesTheTitleWhileTyping() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        for word in ["Pay", " rent", " Fri", " 27", " Nov", " today", " #home", " "] {
            let before = browser.quickAdd.draft?.title ?? ""
            Self.type(word, into: browser, in: library)
            #expect(browser.quickAdd.draft?.title == before + word)
        }
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.dueField), .tag("home")])
    }

    @Test func repeatedTagsAndPunctuationLeaveOnlyAtAddAndOnlyTheirOwnWords() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Buy milk #home. Then #home call #work", into: browser, in: library)
        #expect(browser.quickAdd.draft?.title == "Buy milk #home. Then #home call #work")
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Buy milk. Then call")
        #expect(library.createdTags[id] == ["home", "work"])
    }

    @Test func aChosenChipGoesWithoutTouchingTheWordsUnlessItHoldsAValueSetByHand() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Plan ", into: browser, in: library)
        browser.chooseLineMatch(.tag("work"), in: library)
        browser.chooseLineMatch(.field("status"), in: library)
        browser.quickAdd.draft?.properties["status"] = .string("done")
        #expect(!Self.decline(.field("status"), in: browser, in: library), "a value set in its panel stays")
        #expect(Self.decline(.tag("work"), in: browser, in: library))
        #expect(browser.quickAdd.draft?.title == "Plan ", "a chip chosen from a row gives no words back")
        #expect(browser.quickAdd.draft?.tags.isEmpty == true)
    }

    @Test func aParentChosenForTheWordTypedKeepsTheWordUntilAdd() async throws {
        let library = Self.library()
        let parent = Self.parent(in: library)
        let browser = Self.line(in: library)
        Self.type("Send proofs @lis", into: browser, in: library)
        browser.chooseLineMatch(.parent(parent), in: library)
        #expect(browser.quickAdd.draft?.title == "Send proofs @lis", "the typed word stays")
        #expect(browser.quickAdd.draft?.parentID == parent)
        #expect(QuickAdd.lineTyping(try #require(browser.quickAdd.draft)) == nil, "the word is read, so no row offers for it")
        #expect(Self.chips(browser, in: library) == [.parent])

        Self.type(" now", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Send proofs now")
    }

    @Test func choosingAnOfferForOneWordLeavesEveryOtherMarkedWord() async throws {
        let library = Self.library()
        let parent = Self.parent(in: library)
        let browser = Self.line(in: library)
        Self.type("Send @lis", into: browser, in: library)
        browser.chooseLineMatch(.parent(parent), in: library)
        Self.type(" with /sta", into: browser, in: library)
        browser.chooseLineMatch(.field("status"), in: library)
        #expect(browser.quickAdd.draft?.title == "Send @lis with /sta")
        #expect(browser.quickAdd.draft?.marks.map(\.words) == ["@lis", "/sta"])
        browser.quickAdd.draft?.properties["status"] = .string("todo")
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Send with")
    }

    @Test func anEditInsideAChosenWordMakesItTextAgain() async throws {
        let library = Self.library()
        let parent = Self.parent(in: library)
        let browser = Self.line(in: library)
        Self.type("Send @lis", into: browser, in: library)
        browser.chooseLineMatch(.parent(parent), in: library)
        Self.replace(with: "Send @lisbon", in: browser, in: library)
        #expect(browser.quickAdd.draft?.marks.isEmpty == true)
        browser.quickAdd.draft?.parentID = nil
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Send @lisbon")
    }

    @Test func emptyingTheTitleLeavesNoChipReadFromIt() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.typeWords("Call fri #zine about ", into: browser, in: library)
        #expect(Self.chips(browser, in: library).count == 2)
        Self.replace(with: "", in: browser, in: library)
        #expect(Self.chips(browser, in: library).isEmpty, "nothing is rebuilt from chips")
        #expect(browser.quickAdd.draft?.tags.isEmpty == true)
    }

    @Test func aPastedAddressIsAChipWhoseDeleteKeepsItAsText() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("https://finishingnotes.example/oil-finishes", into: browser, in: library)
        let draft = try #require(browser.quickAdd.draft)
        #expect(Self.chips(browser, in: library) == [.field(MarfaMapping.urlField)])
        let words = QuickAdd.lineChipWords(
            .field(MarfaMapping.urlField), in: QuickAdd.withReads(draft, Self.reads(browser, in: library)), library: library,
            calendar: Self.calendar, locale: Self.british)
        #expect(words.name == "URL")
        #expect(words.value == "finishingnotes.example/oil-finishes")

        #expect(Self.decline(.field(MarfaMapping.urlField), in: browser, in: library))
        #expect(browser.quickAdd.draft?.title == "https://finishingnotes.example/oil-finishes")
        Self.type(" ", into: browser, in: library)
        #expect(Self.chips(browser, in: library).isEmpty)
    }

    @Test func aKindChangeKeepsTheWordsAndAKindWithoutTheFieldKeepsThemInTheTitle() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.typeWords("Plan fri #home", into: browser, in: library)
        browser.chooseQuickAddType("core.note", in: library)
        #expect(browser.quickAdd.draft?.title == "Plan fri #home")
        #expect(Self.chips(browser, in: library) == [.tag("home")], "a note has no day")
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id)?.title == "Plan fri")
        #expect(library.createdTags[id] == ["home"])
    }

    @Test func returnTakesTheTypedTagFirstAndNeverOffersFavorite() {
        let library = Self.library()
        let draft = QuickAdd.Draft(typeID: "core.task")
        #expect(QuickAdd.tagOffers("home", draft: draft, recents: ["homework", "home"], in: library).known.first == "home")
        #expect(!QuickAdd.tagOffers("", draft: draft, recents: [ItemTag.favorite], in: library).known.contains(ItemTag.favorite))
    }

    @Test func aChipSaysWhatItSetsThenItsValueAndADayInShort() throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.typeWords("Send proofs fri #print ", into: browser, in: library)
        let draft = QuickAdd.withReads(try #require(browser.quickAdd.draft), Self.reads(browser, in: library))
        let day = QuickAdd.lineChipWords(
            .field(MarfaMapping.dueField), in: draft, library: library, calendar: Self.calendar, locale: Self.british)
        #expect(day.name == "Due")
        #expect(day.value == "Fri 27 Nov")
        let tag = QuickAdd.lineChipWords(.tag("print"), in: draft, library: library, calendar: Self.calendar, locale: Self.british)
        #expect(tag.name == "Tag")
        #expect(tag.value == "print")
        let unset = QuickAdd.lineChipWords(.field("status"), in: QuickAdd.Draft(typeID: "core.task"), library: library,
                                           calendar: Self.calendar, locale: Self.british)
        #expect(unset.value == nil)
    }


    @Test func theKindMenuListsTheSidebarsKindsThenFileThenTheRestByName() {
        func option(_ id: String, _ label: String) -> ItemTypeOption { ItemTypeOption(id: TypeID(id), label: label, icon: nil) }
        let types = [
            option("core.note", "Note"), option("core.task", "Task"), option("test.project", "Project"), option("test.book", "Book"),
            option("core.bookmark", "Bookmark"), option(TypeID.file.rawValue, "File"), option("test.article", "Article"),
        ]
        let menu = QuickAdd.kindMenu(types, shown: [.file, TypeID("core.note"), TypeID("core.task"), TypeID("core.bookmark")], chosen: "core.note")
        #expect(menu.first.map(\.label) == ["Note", "Task", "Bookmark", "File"])
        #expect(menu.rest.map(\.label) == ["Article", "Book", "Project"])
    }

    @Test func theKindRowOffersTheKindsLastUsedFirstAndTheRestUnderMore() {
        func option(_ id: String) -> ItemTypeOption { ItemTypeOption(id: TypeID(id), label: id, icon: nil) }
        let kinds = ["a", "b", "c", "d", "e", "f", "g", "h"].map(option)
        let offers = QuickAdd.kindOffers(kinds, recents: ["g", "c"], chosen: "a", shown: 4)
        #expect(offers.offered.map(\.id.rawValue) == ["g", "c", "a", "b"])
        #expect(offers.more.map(\.id.rawValue) == ["d", "e", "f", "h"])
        let late = QuickAdd.kindOffers(kinds, recents: [], chosen: "h", shown: 4)
        #expect(late.offered.map(\.id.rawValue) == ["h", "a", "b", "c"], "the chosen kind is always offered")
        let none = QuickAdd.kindOffers(kinds, recents: [], chosen: "a", shown: 6)
        #expect(none.offered.count == 6, "with nothing used yet, the row still offers kinds")
    }

    @Test func beforeTypingTheParentRowOffersTheNewestFirst() {
        let items = ["Old", "Newest", "Middle"].enumerated().map { index, name in
            Item(id: .mint(), type: TypeID("test.project"), title: name, name: name, titleRule: .property("title"),
                 version: ItemVersion(1), created: Self.start, modified: Self.start.addingTimeInterval(Double([0, 200, 100][index])))
        }
        #expect(QuickAdd.bestParents(items, matching: "", first: [], limit: 3, newest: true).map(\.displayTitle) == ["Newest", "Middle", "Old"])
        #expect(QuickAdd.bestParents(items, matching: "", first: [items[0].id], limit: 2, newest: true).map(\.displayTitle) == ["Old", "Newest"])
    }

    @Test func aMatchIsCutWhereItHoldsWhatWasTyped() {
        let runs = NewItemText.matchRuns(of: "lis", in: "Feira Gráfica, the Lisbon print fair")
        #expect(runs.map(\.text) == ["Feira Gráfica, the ", "Lis", "bon print fair"])
        #expect(runs.map(\.matches) == [false, true, false])
        #expect(NewItemText.matchRuns(of: "", in: "Note").map(\.text) == ["Note"])
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
        #expect(browser.quickAdd.draft?.title == "Refused #work ", "the words come back as typed")
        #expect(browser.quickAdd.lastAdded == "The item wasn’t added. What you typed is back.")
    }

    @Test func aRefusalThatComesAfterTheRowGivesTheDraftBack() async throws {
        let library = Self.library()
        let browser = Self.line(in: library)
        Self.type("Shown then refused", into: browser, in: library)
        let id = try #require(await Self.add(browser, in: library))
        #expect(library.item(id) != nil, "the copy shows the row")
        browser.finishNewItems(in: library)
        #expect(browser.newItems.isEmpty)

        library.refusedCreations = [id]
        browser.finishNewItems(in: library)
        #expect(browser.quickAdd.draft?.title == "Shown then refused")
    }

    @Test func aCreateTheLibraryRefusesAtOnceKeepsEverythingTyped() async {
        let library = Self.library()
        library.refusesCreations = true
        let browser = Self.line(in: library)
        Self.type("Stays #home ", into: browser, in: library)
        #expect(await Self.add(browser, in: library) == nil)
        #expect(browser.quickAdd.draft?.title == "Stays #home ")
        #expect(library.notices.waiting.last?.title == "Can’t Create Item")
    }

    @Test func aSentIDThatCannotBeSavedSendsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        let library = Self.library()
        let browser = Browser()
        browser.quickAdd.drafts = NewItemDrafts(file: folder.appending(path: "New Item Drafts.json"))
        browser.openNewItem(kind: "core.task", form: .line, in: library)
        Self.type("Kept here", into: browser, in: library)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))

        #expect(await Self.add(browser, in: library) == nil)
        #expect(library.created.isEmpty, "nothing is made that a crash could make twice")
        #expect(browser.quickAdd.draft?.title == "Kept here")
        #expect(library.notices.waiting.contains { $0.title == "Item Not Added" })
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

    // MARK: Kinds, tags, parents and the any-app line

    @Test func aPastedAddressSetsAsideWhatTheTaskHeldUntilItIsATaskAgain() {
        let library = Self.library()
        let browser = Self.line(in: library)
        browser.quickAdd.draft?.properties["status"] = .string("done")
        Self.type("https://example.com/read", into: browser, in: library)
        #expect(browser.quickAdd.draft?.typeID == MarfaMapping.bookmarkType.rawValue)
        #expect(browser.quickAdd.draft?.setAside["status"] == .string("done"))

        browser.chooseQuickAddType("core.task", in: library)
        #expect(browser.quickAdd.draft?.properties["status"] == .string("done"))
    }

    @Test func aFilesUndoTakesBackThatFileAndNotTheItemBefore() async throws {
        let disk = TestFiles()
        let library = Self.library()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let browser = Self.line(in: library)
        Self.type("First", into: browser, in: library)
        let first = try #require(await Self.add(browser, in: library, undoManager: undo))
        browser.chooseQuickAddType(TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.files = [try disk.file("photo.png")]
        let file = try #require(await Self.add(browser, in: library, undoManager: undo))

        try #require(browser.quickAdd.lastUndo).perform()
        #expect(library.item(file)?.state == .trashed)
        #expect(library.item(first)?.state == .active)
    }

    @Test func favoriteIsNeverOfferedOrTakenAsANewTag() {
        let library = Self.library()
        let browser = Self.line(in: library)
        let draft = browser.quickAdd.draft!
        #expect(QuickAdd.tagOffers(ItemTag.favorite, draft: draft, recents: [], in: library).new == nil)
        #expect(QuickAdd.tagOffers("work", draft: draft, recents: [], in: library).new == "work")
        browser.chooseLineMatch(.tag(ItemTag.favorite), in: library)
        Self.type("Star #\(ItemTag.favorite) ", into: browser, in: library)
        #expect(browser.quickAdd.draft?.tags.isEmpty == true)
        #expect(Self.chips(browser, in: library).isEmpty)
    }

    @Test func aFileAddedFromTheLineKeepsItsTags() async throws {
        let disk = TestFiles()
        let library = Self.library()
        let browser = Self.line(in: library)
        browser.chooseQuickAddType(TypeID.file.rawValue, in: library)
        browser.quickAdd.draft?.files = [try disk.file("scan.png")]
        Self.type("Receipt #tax", into: browser, in: library)
        _ = try #require(await Self.add(browser, in: library))
        #expect(library.addedFileTags == [["tax"]])
        #expect(library.addedFiles.first?.title == "Receipt")
    }


    @Test func parentsAreTheBestSixByNameWithRecentsFirst() {
        let names = ["Delta", "alpha", "Charlie", "Echo", "Bravo", "Golf", "Foxtrot", "Hotel", "Zulu"]
        let items = names.map { name in
            Item(id: .mint(), type: TypeID("test.project"), title: name, name: name, titleRule: .property("title"),
                 version: ItemVersion(1), created: Self.start, modified: Self.start)
        }
        let zulu = items.last!.id
        let best = QuickAdd.bestParents(items, matching: "", first: [zulu], limit: 6)
        #expect(best.map(\.displayTitle) == ["Zulu", "alpha", "Bravo", "Charlie", "Delta", "Echo"])
        #expect(QuickAdd.bestParents(items, matching: "o", first: [], limit: 6).map(\.displayTitle) == ["Bravo", "Echo", "Foxtrot", "Golf", "Hotel"])
    }

    @Test func parentsComeQuicklyFromFiftyThousandItems() {
        let items = (0..<50_000).map { index in
            Item(id: .mint(), type: TypeID("test.project"), title: "Project \(index)", name: "Project \(index)",
                 titleRule: .property("title"), version: ItemVersion(1), created: Self.start, modified: Self.start)
        }
        let clock = ContinuousClock()
        let took = clock.measure { _ = QuickAdd.bestParents(items, matching: "9", first: [], limit: 6) }
        #expect(took < .milliseconds(500), "took \(took)")
    }

    @Test func theLineGivesTheKeyboardBackOnlyWhileItHadItAndTheAppIsStillInFront() {
        #expect(NewItemAnywhere.returnsFocus(panelIsKey: true, previous: 10, front: 10))
        #expect(!NewItemAnywhere.returnsFocus(panelIsKey: false, previous: 10, front: 10), "the person went elsewhere")
        #expect(!NewItemAnywhere.returnsFocus(panelIsKey: true, previous: 10, front: 20), "another app is in front now")
        #expect(!NewItemAnywhere.returnsFocus(panelIsKey: true, previous: nil, front: 20))
    }

    @Test func addTextOpensTheLinesOwnDraftAndLeavesAWindowsDraftAlone() throws {
        let library = Self.library()
        let drafts = NewItemDrafts(file: nil)
        let window = Browser()
        window.quickAdd.drafts = drafts
        window.openNewItem(kind: "core.task", form: .text, in: library)
        window.quickAdd.draft?.title = "The window's own"
        let line = Browser()
        line.quickAdd.drafts = drafts
        line.openNewItem(kind: "core.task", form: .line, in: library)
        line.quickAdd.draft?.title = "Typed over another app"
        let handed = try #require(line.quickAdd.entry)
        line.quickAdd.leave(because: .closed, telling: library.notices)

        #expect(!window.openHandedNewItem(handed, in: library), "a window holding its own draft is left alone")
        #expect(window.quickAdd.draft?.title == "The window's own")
        let other = Browser()
        other.quickAdd.drafts = drafts
        #expect(other.openHandedNewItem(handed, in: library))
        #expect(other.quickAdd.draft?.title == "Typed over another app")
        #expect(other.quickAdd.form == .text)
    }
}

/// The line's Add against the real library: one undo step named as every new item is, and the toast's words.
@MainActor
@Suite(.hangLimit)
struct NewItemLineUndoTests {
    @Test func eachAddIsOneNewItemStepThatItsUndoTakesBack() async throws {
        let source = FakeItemSource()
        source.heldInstanceID.withLock { $0 = "Instance-A" }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { library.serverKey == "instance:instance-a" })
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

    @Test func draftsAreKeptForTheInstanceNotTheAddressSoAReplacementFindsNone() async throws {
        let drafts = NewItemDrafts(file: nil)
        let old = FakeItemSource()
        old.heldInstanceID.withLock { $0 = "old" }
        let first = MarfaLibrary(source: old, notices: Notices())
        old.send(.loaded(SourceSnapshot(items: [], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { !first.serverKey.isEmpty })
        let browser = Browser()
        browser.quickAdd.drafts = drafts
        browser.adopt(first)
        browser.openNewItem(kind: "core.note", form: .line, in: first)
        browser.quickAdd.draft?.title = "For the old server"
        browser.quickAdd.leave(because: .libraryChanged, telling: first.notices)

        let replacement = FakeItemSource()
        let second = MarfaLibrary(source: replacement, notices: Notices())
        replacement.send(.loaded(SourceSnapshot(items: [], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { second.isLoaded })
        #expect(!QuickAdd.isAvailable(in: second), "no new item before the copy names its instance")
        let browserBefore = Browser()
        browserBefore.quickAdd.drafts = drafts
        browserBefore.openNewItem(kind: "core.note", form: .line, in: second)
        #expect(browserBefore.quickAdd.draft == nil, "New Item does nothing until then")
        replacement.heldInstanceID.withLock { $0 = "new" }
        // The copy names its instance as it fills; the next step it takes in reads it.
        replacement.send(.changed(ItemChanges(upserted: [])))
        try #require(await eventually { !second.serverKey.isEmpty })
        #expect(QuickAdd.isAvailable(in: second))
        #expect(!drafts.holdsDraft(.line, in: second.serverKey))
        #expect(drafts.holdsDraft(.line, in: first.serverKey))
    }
}
