import Foundation
import Testing
@testable import MarfaMac

/// The store that keeps every new item typed and not yet added, on this Mac.
@MainActor
@Suite
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
        draft.chips = [.parent, .field("priority")]
        draft.files = [attached]
        draft.declinedDay = "Fri 27 Nov"
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

    @Test func anUnreadableFileIsSetAsideNeverRemoved() throws {
        let files = TestFiles()
        let file = files.directory.appending(path: "Drafts.json")
        try Data("not json".utf8).write(to: file)
        let drafts = NewItemDrafts(file: file)
        #expect(!drafts.holdsDraft(.line, in: "a"))
        let aside = files.directory.appending(path: "Drafts.unreadable.json")
        #expect(try Data(contentsOf: aside) == Data("not json".utf8))
    }
}
