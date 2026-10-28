import Foundation
import Testing
@testable import MAPP

@MainActor
@Suite(.hangLimit) struct ItemTagTests {
    typealias F = LibraryFixture

    // MARK: Rules

    @Test func aTagIsTrimmedAndKeepsItsCase() {
        #expect(ItemTag.normalized("  Reading List \n") == "Reading List")
        #expect(ItemTag.refusal(of: "Reading List") == nil)
    }

    @Test(arguments: [("", ItemTag.Refusal.empty), ("   ", .empty), (".", .dotSegment), ("..", .dotSegment),
                      (String(repeating: "a", count: 129), .tooLong)])
    func marfaRefusesTheseTags(text: String, refusal: ItemTag.Refusal) {
        #expect(ItemTag.refusal(of: ItemTag.normalized(text)) == refusal)
    }

    @Test func aTagAtTheLimitIsAccepted() {
        #expect(ItemTag.refusal(of: String(repeating: "a", count: 128)) == nil)
        #expect(ItemTag.refusal(of: "...") == nil)
    }

    // MARK: Adding and removing through the library

    @Test func addingATagShowsAtOnceAndKeepsTheTypedTextOnRefusal() {
        let library = FakeItemLibrary()
        let note = library.add("Note")
        #expect(library.addTag(" read ", to: [note.id], undoManager: nil) == nil)
        #expect(library.item(note.id)?.tags == ["read"])
        #expect(library.tags(of: library.item(note.id)!) == ["read"])

        #expect(library.addTag("read", to: [note.id], undoManager: nil) == .alreadyHas)
        #expect(library.addTag("", to: [note.id], undoManager: nil) == .empty)
        #expect(library.addTag("..", to: [note.id], undoManager: nil) == .dotSegment)
        #expect(library.tagWrites.count == 1)
    }

    @Test func theFavoriteTagBelongsToTheFavoriteCommand() {
        let library = FakeItemLibrary()
        let note = library.add("Note")
        #expect(library.addTag("favorite", to: [note.id], undoManager: nil) == .favorite)
        library.setFavorite([note.id], true, undoManager: nil)
        #expect(library.tags(of: library.item(note.id)!).isEmpty, "the editor does not list it")
        library.removeTag("favorite", from: [note.id], undoManager: nil)
        #expect(library.item(note.id)?.isFavorite == true, "and cannot remove it")
        #expect(library.knownTags.isEmpty)
    }

    @Test func anItemInTheBinTakesNoTag() {
        let library = FakeItemLibrary()
        let binned = library.add("Old", state: .trashed)
        #expect(library.addTag("x", to: [binned.id], undoManager: nil) == .cantEdit)
        #expect(!library.canTag([binned.id]))
    }

    @Test func anItemWithTheMostTagsTakesNoMore() {
        let library = FakeItemLibrary()
        var full = library.add("Full")
        full.tags = Set((0..<ItemTag.maxPerItem).map { "t\($0)" })
        library.items[0] = full
        let other = library.add("Other")
        #expect(library.addTag("new", to: [full.id], undoManager: nil) == .full)
        #expect(library.tagWrites.isEmpty)
        // In a set, the full item is skipped and told, and the rest are tagged.
        #expect(library.addTag("new", to: [full.id, other.id], undoManager: nil) == nil)
        #expect(library.item(other.id)?.tags == ["new"])
        #expect(library.item(full.id)?.tags.contains("new") == false)
        #expect(library.notices.waiting.last?.title == String(localized: "Some Items Were Skipped"))
        #expect(library.addTag("t0", to: [full.id, other.id], undoManager: nil) == nil, "an item that holds it is not counted")
        #expect(library.item(other.id)?.tags == ["new", "t0"])
    }

    @Test func removingATagAnotherDeviceRemovedSendsNothing() {
        let library = FakeItemLibrary()
        let note = library.add("Note")
        library.addTag("a", to: [note.id], undoManager: nil)
        library.items[0].tags.remove("a")
        library.removeTag("a", from: [note.id], undoManager: nil)
        #expect(library.tagWrites.count == 1)
    }

    @Test func suggestionsAreTheTagsInUseLessThoseHeldAndTheExactMatch() {
        let library = FakeItemLibrary()
        let first = library.add("One"), second = library.add("Two")
        library.addTag("travel", to: [first.id, second.id], undoManager: nil)
        library.addTag("trade", to: [first.id], undoManager: nil)
        library.addTag("work", to: [second.id], undoManager: nil)
        #expect(library.knownTags == ["travel", "trade", "work"])
        #expect(library.tagSuggestions(matching: "tr", excluding: ["trade"]) == ["travel"])
        #expect(library.tagSuggestions(matching: "travel", excluding: []).isEmpty)
        #expect(library.tagSuggestions(matching: "", excluding: ["work"]) == ["travel", "trade"])
    }

    // MARK: Writes to the source

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func addingAndRemovingAreQueuedAndUndoable() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.addTag(" Plan ", to: [F.n1, F.n3], undoManager: undo) == nil)
        #expect(source.writes == [.tag(F.n1, "Plan", on: true)], "the item in the bin is left alone")
        #expect(undo.undoActionName == String(localized: "Add Tag"))
        // The source applies a write to its copy, which the fake does not, so the test shows the copy as it would be.
        func show(_ tags: Set<String>) async throws {
            var item = try #require(library.item(F.n1))
            item.tags = tags
            item.version = ItemVersion(item.version.rawValue + 1)
            source.send(.upserted([item]))
            try #require(await eventually { library.item(F.n1)?.tags == tags })
        }
        try await show([ItemTag.favorite, "Plan"])
        undo.undo()
        #expect(source.writes.last == .tag(F.n1, "Plan", on: false))
        try await show([ItemTag.favorite])
        undo.redo()
        #expect(source.writes.last == .tag(F.n1, "Plan", on: true))
        #expect(source.writes.count == 3)
        try await show([ItemTag.favorite, "Plan"])
        library.removeTag("Plan", from: [F.n1], undoManager: nil)
        #expect(source.writes.last == .tag(F.n1, "Plan", on: false))
    }

    @Test func aTagTheCopyAlreadyHoldsOrTheLibraryOwnsIsNotSent() async throws {
        let (library, source) = try await loaded()
        #expect(library.addTag("favorite", to: [F.n2], undoManager: nil) == .favorite)
        #expect(library.addTag(MarfaProblems.conflictedCopyTag, to: [F.n2], undoManager: nil) == .reserved)
        library.removeTag("never-held", from: [F.n1], undoManager: nil)
        library.removeTag(ItemTag.favorite, from: [F.n1], undoManager: nil)
        library.removeTag(MarfaProblems.conflictedCopyTag, from: [F.n1], undoManager: nil)
        #expect(source.writes.isEmpty)
        #expect(!library.knownTags.contains(MarfaProblems.conflictedCopyTag))
    }

    @Test func aTagTheServerRefusesIsToldToThePerson() async throws {
        let (library, source) = try await loaded()
        library.addTag("plan", to: [F.n1], undoManager: nil)
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "item_not_found", message: "The server doesn’t hold this item."))))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Add Tag"))
    }
}
