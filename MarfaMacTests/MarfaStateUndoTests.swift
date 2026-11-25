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
        try #require(await eventually { library.stateJudging[write] == nil })
    }

    /// An archived item this Mac moved to Recently Deleted, the move taken and accepted.
    private func binnedFromArchive() async throws -> (MarfaLibrary, FakeItemSource, UndoManager) {
        let (library, source) = try await loaded()
        try await show(F.n1, .archived, in: library, source)
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        try #require(source.writes == [.transition(F.n1, .trashed, from: .archived)])
        try await accept(F.n1, .trashed, in: library, source)
        source.clearWrites()
        return (library, source, undo)
    }

    /// The engine skips the last write, as it does one whose item the copy no longer shows as the step left it.
    private func skip(_ reason: BatchSkips.Reason, _ source: FakeItemSource) throws {
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(MarfaEngine.skipped(reason).problem)))
    }

    @Test func aRedoAfterAnotherDeviceRecoveredTheItemLeavesIt() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        try await accept(F.n1, .trashed, in: library, source)
        source.clearWrites()

        undo.undo()
        #expect(source.writes == [.restore(F.n1)])
        // Another device recovered the item before the restore was queued.
        try await show(F.n1, .active, in: library, source)
        try skip(.changedSince, source)
        #expect(await eventually { library.notices.waiting.last?.message == BatchSkips.sentence(.changedSince, count: 1) })

        undo.redo()
        #expect(source.writes == [.restore(F.n1)], "the redo leaves the item where the other device put it")
        #expect(library.notices.waiting.last?.message == String(localized: "That change wasn’t made, so there is nothing to redo here."))
    }

    @Test func aRedoPressedBeforeTheUndoIsJudgedLeavesAnItemAnotherDeviceRecovered() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        try await accept(F.n1, .trashed, in: library, source)
        source.clearWrites()
        // Another device recovers the item, and the copy syncs it.
        try await show(F.n1, .active, in: library, source)

        undo.undo()
        undo.redo()
        #expect(source.writes == [.restore(F.n1)], "the Redo waits for the engine to judge the Undo")
        #expect(library.notices.waiting.last?.message == MarfaLibrary.earlierNotAnswered)
        try skip(.changedSince, source)
        #expect(await eventually { library.stateJudging.isEmpty })
        #expect(source.writes == [.restore(F.n1)])
        #expect(library.item(F.n1)?.state == .active)
    }

    @Test func anUndoWhoseRestoreIsSkippedArchivesNothing() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        try await show(F.n1, .active, in: library, source)
        try skip(.changedSince, source)
        // Lets the library take the answer, which would send the archive at once if it were taken as made.
        try await Task.sleep(for: .milliseconds(200))
        #expect(source.writes == [.restore(F.n1)])
        undo.redo()
        #expect(source.writes == [.restore(F.n1)])
    }

    @Test func aRestoreWithdrawnAfterACanceledSwitchLeavesNothingToRedo() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        let restore = try #require(source.submitted.last)
        // A change of library begins and is canceled.
        library.dropWaitingArchives()
        #expect(library.notices.waiting.last?.message == Self.comesBackActive(1))
        source.send(.answered(restore.id, .blocked(.conflictUnresolved, nil)))
        source.send(.answered(restore.id, .refused(SyncProblem(code: MarfaEngine.withdrawnCode))))
        try #require(await eventually { library.stateAnswers.isEmpty })
        undo.redo()
        #expect(source.writes == [.restore(F.n1)])
    }

    @Test func skipsOfOneCommandAreToldOnceWithTheirCount() async throws {
        let (library, source) = try await loaded()
        library.archive([F.n1, F.p1], beneath: false, undoManager: nil)
        let writes = source.submitted
        try #require(writes.count == 2)
        for write in writes { source.send(.answered(write.id, .refused(MarfaEngine.skipped(.changedSince).problem))) }
        #expect(await eventually { library.notices.told == 1 })
        #expect(library.notices.waiting.map(\.message) == [BatchSkips.sentence(.changedSince, count: 2)])
        #expect(library.notices.waiting.first?.title == ItemMove.archive.failing)
    }

    @Test func anUndoOfBinningAnArchivedItemLeavesItArchived() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        // The server takes an item out of the bin only to active, and the archive waits for that answer.
        #expect(source.writes == [.restore(F.n1)])
        try await accept(F.n1, .active, in: library, source)
        #expect(await eventually { source.writes == [.restore(F.n1), .transition(F.n1, .archived, from: .active)] })
        try await accept(F.n1, .archived, in: library, source)
        #expect(library.item(F.n1)?.state == .archived)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func anUndoWhoseRestoreIsRefusedSendsNothingMore() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        let restore = try #require(source.submitted.last)
        #expect(restore.write == .restore(F.n1))
        source.send(.answered(restore.id, .refused(SyncProblem(code: "item_not_found", message: "The server doesn’t hold this item."))))
        #expect(await eventually { library.notices.waiting.last?.title == String(localized: "Can’t Recover") })
        #expect(source.writes == [.restore(F.n1)])
        #expect(library.item(F.n1)?.state == .trashed)

        // Redo has nothing to put back, since the Undo made nothing.
        undo.redo()
        #expect(source.writes == [.restore(F.n1)])
        #expect(library.notices.waiting.last?.message == String(localized: "That change wasn’t made, so there is nothing to redo here."))
    }

    @Test func anUndoWhoseRestoreIsBlockedSaysTheItemComesBackActive() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        let restore = try #require(source.submitted.last)
        source.send(.answered(restore.id, .blocked(.failingAlone, nil)))
        #expect(await eventually { library.notices.waiting.last?.message == Self.comesBackActive(1) })
        #expect(source.writes == [.restore(F.n1)])

        // The restore is released and lands, so Redo moves the item back to the bin.
        try await show(F.n1, .active, in: library, source)
        undo.redo()
        #expect(source.writes == [.restore(F.n1), .transition(F.n1, .trashed, from: .active)])
    }

    @Test func restoresBlockedTogetherAreToldInOneNoticeWithTheirCount() async throws {
        let (library, source) = try await loaded()
        try await show(F.n1, .archived, in: library, source)
        try await show(F.n2, .archived, in: library, source)
        let undo = UndoManager()
        library.delete([F.n1, F.n2], undoManager: undo)
        let bins = source.submitted
        try #require(bins.count == 2)
        try await show(F.n1, .trashed, in: library, source)
        try await show(F.n2, .trashed, in: library, source)
        for bin in bins {
            source.send(.taken(bin.id))
            source.send(.answered(bin.id, .accepted))
        }
        try #require(await eventually { library.stateJudging.isEmpty })
        source.clearWrites()

        undo.undo()
        let restores = source.submitted
        try #require(restores.count == 2)
        // A block of the whole queue answers every write in it.
        for restore in restores { source.send(.answered(restore.id, .blocked(.instanceChanged, nil))) }
        #expect(await eventually { library.notices.waiting.last?.message == Self.comesBackActive(2) })
        #expect(library.notices.waiting.count { $0.title == String(localized: "Couldn’t Finish Undo") } == 1)
        #expect(source.writes.count == 2)
    }

    @Test func closingTheLibraryBeforeTheRestoreIsAnsweredSaysTheItemComesBackActive() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        await library.finish()
        #expect(library.notices.waiting.last?.message == Self.comesBackActive(1))

        // Told that the item comes back active, so no archive follows a restore answered after that.
        try await accept(F.n1, .active, in: library, source)
        // Lets the library take the answer, which would send the archive at once.
        try await Task.sleep(for: .milliseconds(200))
        #expect(source.writes == [.restore(F.n1)])
        undo.redo()
        #expect(source.writes == [.restore(F.n1), .transition(F.n1, .trashed, from: .active)])
    }

    @Test func anArchiveGivenBackAfterTheRestoreIsToldAndNotPutBack() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        try await accept(F.n1, .active, in: library, source)
        let archive = try #require(await eventually { source.writes.count == 2 } ? source.submitted.last : nil)
        source.send(.answered(archive.id, .refused(SyncProblem(code: MarfaEngine.heldChangedCode, message: MarfaEngine.heldChanged, notQueued: true))))
        #expect(await eventually { library.notices.waiting.last?.title == String(localized: "Recovered but Not Archived") })
        #expect(library.notices.told == 1)
        #expect(!undo.canUndo, "the restore was made, so the Undo is not put back")

        undo.redo()
        #expect(source.writes.last == .transition(F.n1, .trashed, from: .active))
    }

    private static func comesBackActive(_ count: Int) -> String {
        String(localized: "\(count) items will come back active, not archived, if they are recovered.")
    }

    @Test func aRedoAfterThatMovesTheItemToTheBinAgain() async throws {
        let (library, source, undo) = try await binnedFromArchive()
        undo.undo()
        try await accept(F.n1, .active, in: library, source)
        try #require(await eventually { source.writes.count == 2 })
        try await accept(F.n1, .archived, in: library, source)
        source.clearWrites()

        undo.redo()
        #expect(source.writes == [.transition(F.n1, .trashed, from: .archived)])
    }
}
