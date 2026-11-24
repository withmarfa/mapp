import Foundation
import Testing
@testable import MarfaMac

/// An Undo or Redo of a property edit is made only while the item holds exactly what the step before it left, and an
/// Undo puts back what the person had on screen, once any earlier edit of this Mac's it came from is known to be made
/// (`MarfaLibrary+PropertyEdits`).
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

    private struct Scene {
        let library: MarfaLibrary
        let source: FakeItemSource
        let undo: UndoManager

        var notices: Notices { library.notices }

        /// Names en1 `name`, as an undo step of its own unless `undoable` is false, and gives the edit's write.
        @discardableResult
        func set(_ name: String, undoable: Bool = true) throws -> WriteID {
            if undoable { undo.beginUndoGrouping() }
            defer { if undoable { undo.endUndoGrouping() } }
            try #require(library.setItemProperties(
                F.en1, changes: ["name": .string(name)], actionName: "Edit", undoManager: undoable ? undo : nil))
            return try #require(source.submitted.last?.id)
        }

        /// The copy shows en1 named `name` at `version`, as the engine publishes a row it read.
        func show(_ name: String, version: Int64) async throws {
            var item = try #require(library.item(F.en1))
            item.properties = [Property(key: "name", value: .string(name))]
            item.version = ItemVersion(version)
            source.send(.upserted([item]))
            try #require(await eventually { library.item(F.en1)?.version == ItemVersion(version) })
        }

        /// The copy takes the write: the engine publishes the row, then says it took it.
        func take(_ write: WriteID, showing name: String, version: Int64) async throws {
            try await show(name, version: version)
            source.send(.taken(write))
        }

        /// The server answers the write, and the engine reads the item again.
        func answer(_ write: WriteID, _ outcome: WriteOutcome, showing name: String, version: Int64) async throws {
            source.send(.answered(write, outcome))
            try await show(name, version: version)
        }

        /// The write each step made last, as the item edit it is.
        var lastWrite: ItemWrite? { source.writes.last }
        var lastID: WriteID? { source.submitted.last?.id }
        var lastMessage: String? { notices.waiting.last?.message }
    }

    private func loaded() async throws -> Scene {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let card = F.item(Self.c1, Self.card, "Card", age: 10, properties: [Property(key: "summary", value: .string("Old"))])
        source.send(.loaded(SourceSnapshot(items: F.items + [card], catalogue: Self.catalogue)))
        try #require(await eventually { library.isLoaded })
        let undo = UndoManager()
        undo.groupsByEvent = false
        return Scene(library: library, source: source, undo: undo)
    }

    private func name(_ name: String, base: Int64) -> ItemWrite {
        .editProperties(F.en1, ["name": .string(name)], base: ItemVersion(base))
    }

    /// #386: the copy had not yet shown the earlier edit when the later one was made.
    @Test func anUndoPutsBackAnEarlierEditTheCopyHadNotShownYet() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L")
        let later = try scene.set("Ada K")
        try await scene.take(earlier, showing: "Ada L", version: 2)
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .accepted, showing: "Ada K", version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 3)
        #expect(scene.lastWrite == name("Ada L", base: 4))
    }

    @Test func anUndoBuiltOnAnEarlierEditThatWasRefusedIsNotMade() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .refused(SyncProblem(code: "validation_error", message: "Not allowed.")), showing: "Ada K", version: 4)
        try await scene.answer(later, .accepted, showing: "Ada K", version: 5)
        let told = scene.notices.told

        scene.undo.undo()
        #expect(scene.source.writes.count == 2, "nothing is written")
        #expect(scene.notices.told == told + 1)
        #expect(scene.lastMessage == MarfaLibrary.earlierNotMade)
        // Long enough for a step put back to have been registered again.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!scene.undo.canUndo, "a step that can't be made is not put back")
    }

    @Test func anUndoBuiltOnAnEarlierEditWithNoAnswerIsPutBackUntilItIsAnswered() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        // A step put back is registered outside any undo, which only a manager grouping by event takes.
        scene.undo.groupsByEvent = true

        scene.undo.undo()
        try #require(await eventually { scene.notices.told == 1 })
        #expect(scene.source.writes.count == 2, "nothing is written")
        #expect(scene.lastMessage?.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        #expect(scene.undo.canUndo)

        try await scene.answer(earlier, .accepted, showing: "Ada K", version: 4)
        scene.undo.undo()
        #expect(scene.lastWrite == name("Ada L", base: 4))
    }

    /// The server kept another value over the edit; before the item is read again, its answer alone says so.
    @Test(arguments: [true, false]) func anUndoOfAnEditThatLostAConflictIsNotMade(readAgain: Bool) async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        let conflict = WriteOutcome.conflicted(sibling: ItemID("copy"), fields: ["name"], resolved: ["name": .string("Ada E")])
        if readAgain {
            try await scene.answer(edit, conflict, showing: "Ada E", version: 3)
        } else {
            scene.source.send(.answered(edit, conflict))
            // Another item's change follows the answer on the one stream, so once it shows, the answer has been taken.
            var other = try #require(scene.library.item(Self.c1))
            other.version = ItemVersion(20)
            scene.source.send(.upserted([other]))
            try #require(await eventually { scene.library.item(Self.c1)?.version == ItemVersion(20) })
            #expect(scene.library.item(F.en1)?.value(of: "name") == .string("Ada L"), "the copy still shows the edit")
        }

        scene.undo.undo()
        #expect(scene.source.writes.count == 1, "the server's value is not written over")
        #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
    }

    @Test func anUndoAfterAnotherDeviceChangedTheKeyIsNotMade() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        try await scene.show("Ada E", version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 1)
        #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
    }

    @Test func aRedoAfterAnotherDeviceChangedTheKeyIsNotMade() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        scene.undo.undo()
        #expect(scene.lastWrite == name("Ada", base: 3))
        let undone = try #require(scene.lastID)
        try await scene.take(undone, showing: "Ada", version: 4)
        try await scene.answer(undone, .accepted, showing: "Ada", version: 5)
        try await scene.show("Ada E", version: 6)

        scene.undo.redo()
        #expect(scene.source.writes.count == 2)
        let notice = try #require(scene.notices.waiting.last)
        #expect(notice.text == "Ada L", "what the person typed is given back")
        #expect(notice.message.contains(MarfaLibrary.changedSince(undoing: false)))
    }

    @Test func anUndoAfterARedoPutsBackWhatTheItemHeldWhenTheRedoRan() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        scene.undo.undo()
        let undone = try #require(scene.lastID)
        // Redo runs before the server answers the Undo, so the Redo's own Undo is built on the Undo's write.
        try await scene.take(undone, showing: "Ada", version: 4)
        scene.undo.redo()
        #expect(scene.lastWrite == name("Ada L", base: 4))
        let redone = try #require(scene.lastID)
        try await scene.take(redone, showing: "Ada L", version: 5)
        scene.undo.groupsByEvent = true

        scene.undo.undo()
        try #require(await eventually { scene.notices.told == 1 })
        #expect(scene.source.writes.count == 3, "nothing is written while the Undo's write has no answer")
        #expect(scene.lastMessage?.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)

        try await scene.answer(undone, .accepted, showing: "Ada L", version: 6)
        scene.undo.undo()
        #expect(scene.source.writes.count == 4)
        #expect(scene.lastWrite == name("Ada", base: 6))
    }

    /// The person withdrew the earlier edit from the queue, so the server will never answer it.
    @Test func anUndoBuiltOnAWithdrawnEditIsNotMade() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .blocked(.failingAlone, nil), showing: "Ada K", version: 4)
        try await scene.answer(earlier, .refused(SyncProblem(code: MarfaEngine.withdrawnCode)), showing: "Ada K", version: 5)
        #expect(scene.notices.told == 0, "the person withdrew it, so nothing is told")

        scene.undo.undo()
        #expect(scene.source.writes.count == 2)
        #expect(scene.lastMessage == MarfaLibrary.earlierNotMade)
        // Long enough for a step put back to have been registered again.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!scene.undo.canUndo)
    }

    @Test func anUndoOfAKeyThatIsNowTheItemsTextIsNotMade() async throws {
        let scene = try await loaded()
        scene.undo.beginUndoGrouping()
        try #require(scene.library.setItemProperties(
            Self.c1, changes: ["summary": .string("New")], actionName: "Edit", undoManager: scene.undo))
        scene.undo.endUndoGrouping()
        // Elsewhere, the item becomes a type that keeps its text in that key.
        var moved = try #require(scene.library.item(Self.c1))
        moved.type = Self.memo
        moved.properties = [Property(key: "summary", value: .string("New"))]
        moved.version = ItemVersion(2)
        scene.source.send(.upserted([moved]))
        try #require(await eventually { scene.library.item(Self.c1)?.type == Self.memo })

        scene.undo.undo()
        #expect(scene.notices.told == 1)
        #expect(scene.source.writes.count == 1, "the text is never written as a property")
    }
}
