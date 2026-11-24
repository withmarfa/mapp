import Foundation
import Testing
@testable import MarfaMac

/// An Undo of a property edit writes what the server's answers say the item held before it, never what the copy showed
/// while an earlier edit had no answer.
@MainActor
@Suite(.hangLimit) struct MarfaPropertyUndoTests {
    typealias F = LibraryFixture

    private static let card = TypeID("user.card"), memo = TypeID("user.memo")
    private static let c1 = ItemID("c1")

    /// The fixture, with a type that keeps a summary and one that keeps its text in it.
    private static var catalogue: Catalogue {
        var catalogue = F.catalogue
        let fields = [F.field("title", .text, in: card), F.field("summary", .text, in: card)]
        catalogue.itemTypes[card] = ItemTypeInfo(
            id: card, label: "Card", plural: "Cards", fields: fields, titleField: "title", bodyField: nil, parent: nil)
        catalogue.itemTypes[memo] = ItemTypeInfo(
            id: memo, label: "Memo", plural: "Memos", fields: fields, titleField: "title", bodyField: "summary", parent: nil)
        return catalogue
    }

    private func loaded(waiting limit: Duration = .seconds(30)) async throws -> (MarfaLibrary, FakeItemSource, UndoManager) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices(), answerWait: limit)
        let card = F.item(Self.c1, Self.card, "Card", age: 10, properties: [Property(key: "summary", value: .string("Old"))])
        source.send(.loaded(SourceSnapshot(items: F.items + [card], catalogue: Self.catalogue)))
        try #require(await eventually { library.isLoaded })
        let undo = UndoManager()
        undo.groupsByEvent = false
        return (library, source, undo)
    }

    /// Makes `changes` as an undo step of its own, and gives the edit's write.
    @discardableResult
    private func set(
        _ changes: [String: PropertyValue?], of id: ItemID = F.en1, _ library: MarfaLibrary, _ source: FakeItemSource, _ undo: UndoManager
    ) throws -> WriteID {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        try #require(library.setItemProperties(id, changes: changes, actionName: "Edit", undoManager: undo))
        return try #require(source.submitted.last?.id)
    }

    /// The copy shows en1 named `name` at `version`.
    private func show(_ name: String, version: Int64, _ library: MarfaLibrary, _ source: FakeItemSource) async throws {
        var item = try #require(library.item(F.en1))
        item.properties = [Property(key: "name", value: .string(name))]
        item.version = ItemVersion(version)
        source.send(.upserted([item]))
        try #require(await eventually { library.item(F.en1)?.version == ItemVersion(version) })
    }

    private func name(_ name: String, base: Int64) -> ItemWrite {
        .editProperties(F.en1, ["name": .string(name)], base: ItemVersion(base))
    }

    @Test func anUndoWaitsForAnEarlierEditAndPutsBackWhatItSet() async throws {
        let (library, source, undo) = try await loaded()
        let earlier = try set(["name": .string("Ada L")], library, source, undo)
        try set(["name": .string("Ada K")], library, source, undo)
        undo.undo()
        #expect(source.submitted.count == 2, "nothing is written while the earlier edit has no answer")

        source.send(.answered(earlier, .accepted))
        #expect(await eventually { source.submitted.count == 3 })
        #expect(source.writes.last == name("Ada L", base: 1))
    }

    @Test func anUndoLeavesOutAnEarlierEditRefusedAfterTheCopyShowedIt() async throws {
        let (library, source, undo) = try await loaded()
        let earlier = try set(["name": .string("Ada L")], library, source, undo)
        source.send(.taken(earlier))
        try await show("Ada L", version: 2, library, source)
        let later = try set(["name": .string("Ada K")], library, source, undo)
        source.send(.taken(later))
        try await show("Ada K", version: 3, library, source)
        source.send(.answered(earlier, .refused(SyncProblem(code: "validation_error", message: "Not allowed."))))
        source.send(.answered(later, .accepted))
        try #require(await eventually { library.notices.told == 1 })

        undo.undo()
        #expect(source.writes.last == name("Ada", base: 3))
    }

    @Test func anUndoWaitingForAnEarlierEditThatIsRefusedPutsBackTheValueBeforeIt() async throws {
        let (library, source, undo) = try await loaded()
        let earlier = try set(["name": .string("Ada L")], library, source, undo)
        try set(["name": .string("Ada K")], library, source, undo)
        undo.undo()
        #expect(source.submitted.count == 2)

        source.send(.answered(earlier, .refused(SyncProblem(code: "validation_error", message: "Not allowed.", notQueued: true))))
        #expect(await eventually { source.submitted.count == 3 })
        #expect(source.writes.last == name("Ada", base: 1))
    }

    /// Never answered, or changed again by the person while it waits: the step goes back on the stack and is told once.
    @Test(arguments: [false, true]) func anUndoThatCannotWaitIsGivenBack(editedAgain: Bool) async throws {
        let (library, source, undo) = try await loaded(waiting: .milliseconds(300))
        try set(["name": .string("Ada L")], library, source, undo)
        try set(["name": .string("Ada K")], library, source, undo)
        // A step given back is registered outside any undo, which only a manager grouping by event takes.
        undo.groupsByEvent = true
        undo.undo()
        if editedAgain {
            #expect(library.setItemProperties(F.en1, changes: ["name": .string("Ada J")], actionName: "Edit", undoManager: nil))
        }
        try #require(await eventually { library.notices.told == 1 })
        #expect(source.writes.count == (editedAgain ? 3 : 2), "the Undo writes nothing")
        #expect(library.notices.waiting.last?.message.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        #expect(undo.canUndo)
        // Long enough for the wait to have ended had it not already.
        try await Task.sleep(for: .milliseconds(600))
        #expect(library.notices.told == 1)
        #expect(source.writes.count == (editedAgain ? 3 : 2))
    }

    @Test func anUndoAfterARedoPutsBackWhatTheItemHeldWhenTheRedoRan() async throws {
        let (library, source, undo) = try await loaded()
        func answer(version: Int64, showing name: String) async throws {
            let id = try #require(source.submitted.last?.id)
            source.send(.taken(id))
            try await show(name, version: version, library, source)
            source.send(.answered(id, .accepted))
        }
        try set(["name": .string("Ada L")], library, source, undo)
        try await answer(version: 2, showing: "Ada L")
        undo.undo()
        try await answer(version: 3, showing: "Ada")
        // Another device names it.
        try await show("Ada E", version: 4, library, source)
        undo.redo()
        #expect(source.writes.last == name("Ada L", base: 4))
        try await answer(version: 5, showing: "Ada L")

        undo.undo()
        #expect(await eventually { source.writes.count == 4 })
        #expect(source.writes.last == name("Ada E", base: 5))
    }

    /// A key whose value lost on the original item holds what the server kept, which only its answer says.
    @Test(arguments: [true, false]) func anUndoAfterAConflictPutsBackWhatTheServerKept(answerRead: Bool) async throws {
        let (library, source, undo) = try await loaded()
        let earlier = try set(["status": .string("done"), "due": .string("2026-10-06")], of: F.t1, library, source, undo)
        try set(["status": .string("open"), "due": .string("2026-12-01")], of: F.t1, library, source, undo)
        undo.groupsByEvent = true
        undo.undo()
        let held: [String: PropertyValue?]? = answerRead ? ["status": .string("done"), "due": .string("2026-11-01")] : nil
        source.send(.answered(earlier, .conflicted(sibling: ItemID("copy"), fields: ["status", "due"], resolved: held)))
        if answerRead {
            #expect(await eventually { source.writes.count == 3 })
            #expect(source.writes.last == .editProperties(
                F.t1, ["status": .string("done"), "due": .string("2026-11-01")], base: ItemVersion(1)))
        } else {
            try #require(await eventually { library.notices.told == 1 })
            #expect(source.writes.count == 2)
            #expect(undo.canUndo)
        }
    }

    @Test func anUndoOfAKeyThatIsNowTheItemsTextIsRefused() async throws {
        let (library, source, undo) = try await loaded()
        try set(["summary": .string("New")], of: Self.c1, library, source, undo)
        // Elsewhere, the item becomes a type that keeps its text in that key.
        var moved = try #require(library.item(Self.c1))
        moved.type = Self.memo
        moved.version = ItemVersion(2)
        source.send(.upserted([moved]))
        try #require(await eventually { library.item(Self.c1)?.type == Self.memo })

        undo.undo()
        try #require(await eventually { library.notices.told == 1 })
        #expect(source.writes.count == 1, "the text is never written as a property")
    }
}
