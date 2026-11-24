import Foundation
import Testing
@testable import MarfaMac

/// Undo and Redo of a change to an item's state judge the item as it stands, and an item moved from the archive to
/// Recently Deleted comes back archived (`MarfaLibrary.setStates`). The source applies nothing itself, so each test
/// shows the copy's state and gives the queue's answers as the engine would.
@MainActor
@Suite(.hangLimit) struct MarfaStateUndoTests {
    typealias F = LibraryFixture

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// The copy shows the item in `state`, as another device's change or the engine's read of a write shows it.
    private func show(_ id: ItemID, _ state: ItemState, in library: MarfaLibrary, _ source: FakeItemSource) async throws {
        var item = try #require(library.item(id))
        item.state = state
        source.send(.upserted([item]))
        try #require(await eventually { library.item(id)?.state == state })
    }

    /// The last write is in the copy, which shows the item in `state`, and the server accepted it.
    private func accept(_ id: ItemID, _ state: ItemState, in library: MarfaLibrary, _ source: FakeItemSource) async throws {
        let write = try #require(source.submitted.last?.id)
        try await show(id, state, in: library, source)
        source.send(.taken(write))
        source.send(.answered(write, .accepted))
    }

    /// An archived item this Mac moved to Recently Deleted, the move taken and accepted.
    private func binnedFromArchive() async throws -> (MarfaLibrary, FakeItemSource, UndoManager) {
        let (library, source) = try await loaded()
        try await show(F.n1, .archived, in: library, source)
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        try #require(source.writes == [.transition(F.n1, .trashed)])
        try await accept(F.n1, .trashed, in: library, source)
        source.clearWrites()
        return (library, source, undo)
    }

    @Test func anUndoLeavesAnItemWhoseStateChangedSinceAlone() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        try await accept(F.n1, .trashed, in: library, source)
        // Another device restores the item and archives it.
        try await show(F.n1, .archived, in: library, source)
        source.clearWrites()

        undo.undo()
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == BatchSkips.sentence(.changedSince, count: 1))
        #expect(library.item(F.n1)?.state == .archived)

        // The Undo made nothing, so its Redo says so in its own words.
        undo.redo()
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == String(localized: "That change wasn’t made, so there is nothing to redo here."))
    }

    @Test func anUndoOfBinningAnArchivedItemLeavesItArchived() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        // The server takes an item out of the bin only to active, and the archive waits for that answer.
        #expect(source.writes == [.transition(F.n1, .active)])
        try await accept(F.n1, .active, in: library, source)
        #expect(await eventually { source.writes == [.transition(F.n1, .active), .transition(F.n1, .archived)] })
        try await accept(F.n1, .archived, in: library, source)
        #expect(library.item(F.n1)?.state == .archived)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func anUndoWhoseRestoreIsRefusedSendsNothingMore() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        let restore = try #require(source.submitted.last)
        #expect(restore.write == .transition(F.n1, .active))
        source.send(.answered(restore.id, .refused(SyncProblem(code: "item_not_found", message: "The server doesn’t hold this item."))))
        #expect(await eventually { library.notices.waiting.last?.title == String(localized: "Can’t Recover") })
        #expect(source.writes == [.transition(F.n1, .active)])
        #expect(library.item(F.n1)?.state == .trashed)

        // Redo has nothing to put back, since the Undo made nothing.
        undo.redo()
        #expect(source.writes == [.transition(F.n1, .active)])
        #expect(library.notices.waiting.last?.message == String(localized: "That change wasn’t made, so there is nothing to redo here."))
    }

    @Test func aRedoAfterThatMovesTheItemToTheBinAgain() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        try await accept(F.n1, .active, in: library, source)
        try #require(await eventually { source.writes.count == 2 })
        try await accept(F.n1, .archived, in: library, source)
        source.clearWrites()

        undo.redo()
        #expect(source.writes == [.transition(F.n1, .trashed)])
    }
}
