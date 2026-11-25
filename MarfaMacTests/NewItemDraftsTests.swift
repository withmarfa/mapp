import Foundation
import Testing
@testable import MarfaMac

/// The store that keeps every new item typed and not yet added, on this Mac.
@MainActor
@Suite(.hangLimit)
struct NewItemDraftsTests {
    static func typed(_ title: String, kind: String = "core.task") -> QuickAdd.Draft {
        var draft = QuickAdd.Draft(typeID: kind)
        draft.title = title
        return draft
    }

    @Test func anEmptyDraftIsNeverKept() {
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.note"), in: "a")
        drafts.release(id)
        #expect(!drafts.holdsDraft(.line, in: "a"))
        #expect(drafts.take(.line, in: "a") == nil)
    }

    @Test func aTypedDraftIsKeptForTheNextHolderInItsLibraryAndSlotAlone() throws {
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("Half a thought"))
        #expect(!drafts.holdsDraft(.line, in: "a"), "the holder has it claimed")
        drafts.release(id)
        #expect(!drafts.holdsDraft(.line, in: "b"))
        #expect(!drafts.holdsDraft(.inPlace("board:todo"), in: "a"))
        let kept = try #require(drafts.take(.line, in: "a"))
        #expect(kept.draft.title == "Half a thought")
        #expect(drafts.take(.line, in: "a") == nil, "two holders never share one draft")
    }

    @Test func clearingTheTextAgainDropsTheDraft() {
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("Something"))
        drafts.update(id, Self.typed(""))
        drafts.release(id)
        #expect(!drafts.holdsDraft(.line, in: "a"))
    }

    @Test func escapeDropsAnEmptyDraftAndKeepsATypedOne() {
        let drafts = NewItemDrafts(file: nil)
        let empty = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        #expect(!drafts.escape(empty))
        let typed = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(typed, Self.typed("Keep me"))
        #expect(drafts.escape(typed))
        drafts.release(typed)
        #expect(drafts.take(.line, in: "a")?.draft.title == "Keep me")
    }

    @Test func dropForgetsADraftForGood() {
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("Gone"))
        drafts.drop(id)
        #expect(!drafts.holdsDraft(.line, in: "a"))
    }

    @Test func anAddedDraftWaitsUntilTheLibraryHoldsTheItem() {
        let library = FakeItemLibrary()
        library.serverKey = "a"
        library.holdsCreations = true
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("On its way"))
        let item = library.createItem(
            typeID: "core.task", title: "On its way", body: "", properties: [:], tags: [], parentID: nil, tier: .library, undoManager: nil)!
        drafts.added(id, as: item)
        #expect(!drafts.holdsDraft(.line, in: "a"), "a draft on its way is offered to no one")
        drafts.settle(in: library)
        #expect(!drafts.holdsDraft(.line, in: "a"))

        library.deliverCreated()
        drafts.settle(in: library)
        library.refusedCreations = [item]
        drafts.settle(in: library)
        #expect(!drafts.holdsDraft(.line, in: "a"), "once held, the draft is gone, whatever comes after")
        #expect(drafts.takeReturned(.line, in: "a") == nil)
    }

    @Test func aRefusedCreateGivesTheDraftBackAsTyped() throws {
        let library = FakeItemLibrary()
        library.serverKey = "a"
        library.holdsCreations = true
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        var draft = Self.typed("Refused one")
        draft.tags = ["home"]
        draft.tier = .feed
        drafts.update(id, draft)
        let item = library.createItem(
            typeID: "core.task", title: "Refused one", body: "", properties: [:], tags: ["home"], parentID: nil, tier: .feed, undoManager: nil)!
        drafts.added(id, as: item)
        library.refusedCreations = [item]

        drafts.settle(in: library)
        drafts.settle(in: library)
        let back = try #require(drafts.takeReturned(.line, in: "a"), "settling twice still gives it back once")
        #expect(back.draft == draft)
        #expect(back.returned)
        #expect(drafts.takeReturned(.line, in: "a") == nil)
    }

    @Test func draftsOutliveTheAppOnDisk() throws {
        let files = TestFiles()
        let file = files.directory.appending(path: "Drafts.json")
        let attached = try files.file("Plan.pdf")
        var draft = Self.typed("Across a quit")
        draft.body = "Body"
        draft.tags = ["work", "q4"]
        draft.tier = .feed
        draft.properties = ["priority": .string("high")]
        draft.chips = [.parent, .field("priority"), .tag("work")]
        draft.files = [attached]
        draft.marks = [QuickAdd.Mark(range: 7..<13, words: "a quit", chip: .tag("work"))]
        draft.declined = ["Fri 27 Nov", "#q3"]
        do {
            let drafts = NewItemDrafts(file: file)
            let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
            drafts.update(id, draft)
            let row = drafts.make(.inPlace("list:x"), QuickAdd.Draft(typeID: "core.note"), in: "a")
            drafts.update(row, Self.typed("A row", kind: "core.note"))
        }
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        let reopened = NewItemDrafts(file: file)
        let kept = try #require(reopened.take(.line, in: "a"))
        #expect(kept.draft == draft)
        #expect(kept.missingFiles.isEmpty)
        #expect(reopened.take(.inPlace("list:x"), in: "a")?.draft.title == "A row")

        reopened.drop(kept.id)
        let rest = try #require(NewItemDrafts(file: file).take(.inPlace("list:x"), in: "a"))
        NewItemDrafts(file: file).drop(rest.id)
    }

    @Test func aFileGoneFromDiskIsNamedWhenTheDraftIsRead() throws {
        let files = TestFiles()
        let file = files.directory.appending(path: "Drafts.json")
        let attached = try files.file("Gone.pdf")
        var draft = Self.typed("With a file")
        draft.files = [attached]
        let drafts = NewItemDrafts(file: file)
        drafts.update(drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a"), draft)
        try FileManager.default.removeItem(at: attached.url)

        let kept = try #require(NewItemDrafts(file: file).take(.line, in: "a"))
        #expect(kept.draft.files.isEmpty)
        #expect(kept.draft.title == "With a file")
        #expect(kept.missingFiles == ["Gone.pdf"])
    }

    @Test func everyUnreadableFileIsSetAsideUnderANameOfItsOwn() throws {
        let files = TestFiles()
        let file = files.directory.appending(path: "Drafts.json")
        try Data("first".utf8).write(to: file)
        #expect(!NewItemDrafts(file: file).holdsDraft(.line, in: "a"))
        try Data("second".utf8).write(to: file)
        _ = NewItemDrafts(file: file)

        let aside = try FileManager.default.contentsOfDirectory(at: files.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Drafts unreadable ") }
        #expect(Set(try aside.map { try String(contentsOf: $0, encoding: .utf8) }) == ["first", "second"])
    }

    // MARK: Marfa's answer

    /// A draft added as `item` in library "a", the way an Add writes it before the create.
    static func sent(_ title: String, as item: ItemID, in drafts: NewItemDrafts, files: [QuickAdd.File] = []) -> UUID {
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        var draft = typed(title)
        draft.files = files
        drafts.update(id, draft)
        #expect(drafts.sending(id, as: item))
        drafts.added(id, as: item)
        return id
    }

    static func problem(_ kind: SyncProblemEntry.Kind, creating item: ItemID) -> SyncProblemEntry {
        SyncProblemEntry(id: .write("w"), itemID: item, kind: kind, change: .create, content: SyncContent(title: "Held up"), actions: [])
    }

    @Test func theCopysOwnRowForACreateIsNoAnswer() throws {
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let drafts = NewItemDrafts(file: nil)
        let item = try #require(library.createItem(
            typeID: "core.task", title: "Offline", body: "", properties: [:], tags: [], parentID: nil, tier: .library, undoManager: nil))
        let index = try #require(library.items.firstIndex { $0.id == item })
        library.items[index].sync = .waiting(writes: 1)
        _ = Self.sent("Offline", as: item, in: drafts)

        drafts.settle(in: library)
        #expect(!drafts.holdsDraft(.line, in: "a"), "waiting to be sent, it is neither back nor gone")
        library.items[index].sync = .settled
        drafts.settle(in: library)
        library.refusedCreations = [item]
        drafts.settle(in: library)
        #expect(drafts.takeReturned(.line, in: "a") == nil, "accepted, the draft is gone")
    }

    @Test func aHeldUpCreateStaysHiddenAndARefusedOneComesBackWithItsFiles() throws {
        let disk = TestFiles()
        let library = FakeItemLibrary()
        library.serverKey = "a"
        library.holdsCreations = true
        let drafts = NewItemDrafts(file: nil)
        let item = ItemID.mint()
        let attached = try disk.file("Plan.pdf")
        _ = Self.sent("Held up", as: item, in: drafts, files: [attached])
        library.syncReport.problems = [Self.problem(.blocked(.failingAlone), creating: item)]
        drafts.settle(in: library)
        #expect(drafts.takeReturned(.line, in: "a") == nil, "a held-up create may still be made, so it is not given back")

        library.syncReport.problems = [Self.problem(.refused, creating: item)]
        drafts.settle(in: library)
        let back = try #require(drafts.takeReturned(.line, in: "a"))
        #expect(back.draft.files == [attached])
    }

    @Test func aCreateFromAnEarlierRunComesBackOnlyOnMarfasRefusal() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let queued = ItemID.mint()
        let absent = ItemID.mint()
        do {
            let drafts = NewItemDrafts(file: file)
            _ = Self.sent("Queued", as: queued, in: drafts)
            // The app stopped after writing the sent ID; the copy may not show the create yet.
            let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
            drafts.update(id, Self.typed("Not in the copy"))
            #expect(drafts.sending(id, as: absent))
        }
        let library = FakeItemLibrary()
        library.serverKey = "a"
        library.items = [Item(
            id: queued, type: TypeID("core.task"), title: "Queued", titleRule: .property("title"), version: ItemVersion(1),
            created: .now, modified: .now, sync: .waiting(writes: 1))]
        let reopened = NewItemDrafts(file: file)
        reopened.settle(in: library)
        #expect(reopened.takeReturned(.line, in: "a") == nil, "a create not in the copy is not given back as refused")

        library.syncReport.problems = [Self.problem(.blocked(.failingAlone), creating: absent)]
        reopened.settle(in: library)
        #expect(reopened.takeReturned(.line, in: "a") == nil, "a blocked create may still be made")

        library.syncReport.problems = [Self.problem(.refused, creating: absent)]
        reopened.settle(in: library)
        #expect(reopened.takeReturned(.line, in: "a")?.draft.title == "Not in the copy")
        #expect(reopened.takeReturned(.line, in: "a") == nil, "the queued create stays hidden")
    }

    @Test func aRefusalIsKeptWithItsDraftAcrossARelaunch() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let item = ItemID.mint()
        do {
            let drafts = NewItemDrafts(file: file)
            _ = Self.sent("Refused before the quit", as: item, in: drafts)
            let library = FakeItemLibrary()
            library.serverKey = "a"
            library.refusedCreations = [item]
            drafts.settle(in: library)
        }
        // After the relaunch the copy knows nothing of the refusal, which only the draft still holds.
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let reopened = NewItemDrafts(file: file)
        reopened.settle(in: library)
        let back = try #require(reopened.takeReturned(.line, in: "a"))
        #expect(back.draft.title == "Refused before the quit")
        #expect(back.returned)
    }

    @Test func aRefusalHeardWithNoNewItemOpenComesBackAfterARelaunch() async throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let item = ItemID.mint()
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let drafts = NewItemDrafts(file: file)
        let following = drafts.follow(library)
        defer { following.cancel() }
        _ = Self.sent("Refused with no window", as: item, in: drafts)
        library.refusedCreations = [item]
        #expect(await eventually { NewItemDrafts(file: file).holdsDraft(.line, in: "a") }, "the refusal is written with the draft at once")

        let reopened = NewItemDrafts(file: file)
        reopened.settle(in: FakeItemLibrary())
        #expect(reopened.takeReturned(.line, in: "a")?.draft.title == "Refused with no window")
    }

    // MARK: Round 1

    @Test func clearingTheEditorWhileAFileIsSentKeepsTheSentDraftUntilItsAnswer() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let drafts = NewItemDrafts(file: file)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.file"), in: "a")
        var draft = Self.typed("Holiday", kind: "core.file")
        draft.files = [try disk.file("photo.png")]
        drafts.update(id, draft)
        #expect(drafts.sendingFile(id))

        let next = drafts.update(id, QuickAdd.Draft(typeID: "core.file"))
        #expect(next != id, "the editor goes on in a new draft")
        #expect(!drafts.holdsDraft(.line, in: "a"), "the sent draft stays hidden until its answer")
        #expect(NewItemDrafts(file: file).takeReturned(.line, in: "a")?.draft.title == "Holiday", "a quit keeps it on disk")
        drafts.giveBack(id)
        #expect(drafts.takeReturned(.line, in: "a")?.draft.title == "Holiday")
    }

    @Test func clearingTheEditorKeepsADraftWhoseCreateIsSent() throws {
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("On its way"))
        #expect(drafts.sending(id, as: .mint()))
        #expect(drafts.update(id, Self.typed("")) != id)
        drafts.drop(id)
        drafts.giveBack(id)
        #expect(drafts.takeReturned(.line, in: "a")?.draft.title == "On its way", "neither update nor drop removes it")
    }

    @Test func aFileCutOffByAQuitStaysMarkedUntilItIsAddedAgain() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        do {
            let drafts = NewItemDrafts(file: file)
            let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.file"), in: "a")
            var draft = Self.typed("Holiday", kind: "core.file")
            draft.files = [try disk.file("photo.png")]
            drafts.update(id, draft)
            #expect(drafts.sendingFile(id))
        }
        let first = NewItemDrafts(file: file)
        let kept = try #require(first.take(.line, in: "a"))
        #expect(kept.interrupted)
        first.release(kept.id)
        #expect(first.take(.line, in: "a")?.interrupted == true, "taken and let go, it still may be in Marfa")
        let again = try #require(NewItemDrafts(file: file).take(.line, in: "a"))
        #expect(again.interrupted, "and after another relaunch")
    }

    @Test func aCreateSentBeforeAQuitComesBackAskingUntilItsItemIsInTheCopy() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let absent = ItemID.mint()
        do {
            let drafts = NewItemDrafts(file: file)
            let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
            drafts.update(id, Self.typed("Force quit"))
            #expect(drafts.sending(id, as: absent))
        }
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let reopened = NewItemDrafts(file: file)
        reopened.settle(in: library)
        let back = try #require(reopened.take(.line, in: "a"), "a create with no known answer comes back")
        #expect(back.draft.title == "Force quit")
        #expect(back.interrupted, "it may already be in Marfa")

        library.items = [Item(
            id: absent, type: TypeID("core.task"), title: "Force quit", titleRule: .property("title"), version: ItemVersion(1),
            created: .now, modified: .now, sync: .settled)]
        reopened.settle(in: library)
        #expect(reopened.update(back.id, Self.typed("Force quit")) == back.id, "the holder keeps it while it holds it")
        reopened.release(back.id)
        reopened.settle(in: library)
        #expect(reopened.take(.line, in: "a") == nil, "once its item is in the copy, the draft closes")
        let again = NewItemDrafts(file: file)
        again.settle(in: FakeItemLibrary())
        #expect(again.take(.line, in: "a") == nil, "and stays closed after a relaunch")
    }

    @Test func editsAfterAddNeverChangeTheSentDraft() throws {
        let disk = TestFiles()
        let drafts = NewItemDrafts(file: nil)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.file"), in: "a")
        var draft = Self.typed("Holiday", kind: "core.file")
        draft.files = [try disk.file("photo.png")]
        drafts.update(id, draft)
        #expect(drafts.sendingFile(id))

        var cleared = draft
        cleared.title = ""
        let next = drafts.update(id, cleared)
        #expect(next != id, "a change after Add is a new draft")
        drafts.update(next, QuickAdd.Draft(typeID: "core.file"))
        drafts.giveBack(id)
        let back = try #require(drafts.takeReturned(.line, in: "a"))
        #expect(back.id == id)
        #expect(back.draft.title == "Holiday", "the draft as it was sent")
    }

    @Test func aFileMarkerThatCannotBeWrittenIsNotSent() throws {
        let disk = TestFiles()
        let blocker = disk.url("Blocker")
        let file = blocker.appending(path: "Drafts.json")
        let drafts = NewItemDrafts(file: file)
        drafts.notices = Notices()
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.file"), in: "a")
        var draft = Self.typed("Holiday", kind: "core.file")
        draft.files = [try disk.file("photo.png")]
        drafts.update(id, draft)
        #expect(!drafts.sendingFile(id))

        try FileManager.default.removeItem(at: blocker)
        drafts.update(id, Self.typed("Holiday again", kind: "core.file"))
        drafts.release(id)
        let kept = try #require(NewItemDrafts(file: file).take(.line, in: "a"), "still a draft to type into")
        #expect(!kept.interrupted, "nothing was on its way")
    }

    @Test func aCreateMadeThisRunStaysHiddenUntilItsAnswer() throws {
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let drafts = NewItemDrafts(file: nil)
        _ = Self.sent("In flight", as: .mint(), in: drafts)
        drafts.settle(in: library)
        #expect(!drafts.holdsDraft(.line, in: "a"), "the copy has not taken it yet")
    }

    @Test func aRefusalHeardBeforeTheLibraryKnowsItsKeyIsTakenOnceItDoes() async throws {
        let library = FakeItemLibrary()
        library.serverKey = ""
        let drafts = NewItemDrafts(file: nil)
        let following = drafts.follow(library)
        defer { following.cancel() }
        let item = ItemID.mint()
        _ = Self.sent("Refused at startup", as: item, in: drafts)
        library.refusedCreations = [item]
        // Lets the watcher hear the refusal while the key is still unknown.
        try await Task.sleep(for: .milliseconds(50))
        library.serverKey = "a"
        #expect(await eventually { drafts.holdsDraft(.line, in: "a") })
    }

    @Test func theWatcherHoldsTheLibraryWeakly() async throws {
        let drafts = NewItemDrafts(file: nil)
        weak var gone: FakeItemLibrary?
        var following: Task<Void, Never>?
        var library: FakeItemLibrary? = FakeItemLibrary()
        gone = library
        following = library.map(drafts.follow)
        library = nil
        #expect(await eventually { gone == nil })
        following?.cancel()
    }

    @Test func aFileRefusedAfterItsWindowClosedIsToldOnceWithTheReason() throws {
        let disk = TestFiles()
        let library = FakeItemLibrary()
        library.serverKey = "a"
        let notices = Notices()
        let drafts = NewItemDrafts(file: nil)
        drafts.notices = notices
        let item = ItemID.mint()
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.file"), in: "a")
        var draft = Self.typed("Holiday", kind: "core.file")
        draft.files = [try disk.file("photo.png")]
        drafts.update(id, draft)
        #expect(drafts.sendingFile(id))
        drafts.release(id)
        drafts.added(id, as: item)
        library.syncReport.problems = [SyncProblemEntry(
            id: .write("w"), itemID: item, kind: .refused, change: .create,
            reason: SyncProblem(code: "too_large", message: "The file is too large."), content: SyncContent(title: "Holiday"), actions: [])]

        drafts.settle(in: library)
        drafts.settle(in: library)
        #expect(notices.told == 1)
        let told = try #require(notices.waiting.last)
        #expect(told.title == "File Not Added")
        #expect(told.message.contains("The file is too large."), "\(told.message)")
        #expect(drafts.takeReturned(.line, in: "a")?.draft.title == "Holiday")
    }

    @Test func aSentIDThatCannotBeWrittenIsNotSent() throws {
        let disk = TestFiles()
        let blocker = disk.url("Blocker")
        let file = blocker.appending(path: "Drafts.json")
        let drafts = NewItemDrafts(file: file)
        drafts.notices = Notices()
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("Typed"))
        #expect(!drafts.sending(id, as: .mint()))

        try FileManager.default.removeItem(at: blocker)
        drafts.update(id, Self.typed("Typed more"))
        drafts.release(id)
        let kept = try #require(NewItemDrafts(file: file).take(.line, in: "a"), "still a draft to type into, not one on its way")
        #expect(kept.sent == nil)
    }

    @Test func aDraftIsNeverWrittenUnderAnUnknownLibrary() throws {
        let disk = TestFiles()
        let file = disk.directory.appending(path: "Drafts.json")
        let drafts = NewItemDrafts(file: file)
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "")
        drafts.update(id, Self.typed("Before the instance"))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(!drafts.sending(id, as: .mint()), "a create no later run could follow is not made")
    }

    @Test func aDraftThatCantBeWrittenIsToldOnceAndWrittenOnceItCanBe() throws {
        let disk = TestFiles()
        let blocker = disk.url("Blocker")
        let file = blocker.appending(path: "Drafts.json")
        let notices = Notices()
        let drafts = NewItemDrafts(file: file)
        drafts.notices = notices
        let id = drafts.make(.line, QuickAdd.Draft(typeID: "core.task"), in: "a")
        drafts.update(id, Self.typed("One"))
        drafts.update(id, Self.typed("Two"))
        #expect(notices.told == 1)

        try FileManager.default.removeItem(at: blocker)
        drafts.update(id, Self.typed("Three"))
        drafts.release(id)
        #expect(NewItemDrafts(file: file).take(.line, in: "a")?.draft.title == "Three")
        #expect(notices.told == 1)
    }
}
