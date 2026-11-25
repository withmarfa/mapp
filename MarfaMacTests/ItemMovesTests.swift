import Foundation
import Testing
@testable import MarfaMac

/// Keep, Move to Feed, Archive and Unarchive: what each moves, and that an Undo moves back only what it changed.
/// Alpha holds Epic task, which holds Bug one; Bug one is archived already and holds an item in the bin.
@MainActor
@Suite(.hangLimit) struct ItemMovesTests {
    typealias F = LibraryFixture

    static let binned = ItemID("binned")

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let items = F.items.map { item in
            var item = item
            if item.id == F.t1 { item.state = .archived }
            return item
        } + [F.item(Self.binned, F.note, "Binned child", age: 10, state: .trashed, edges: [F.child("c9", Self.binned, of: F.t1)])]
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// The copy shows each item as `change` leaves it, as another device's change or the engine's read of a write does.
    private func show(_ ids: [ItemID], in library: MarfaLibrary, _ source: FakeItemSource, _ change: (inout Item) -> Void) async throws {
        let items = try ids.map { id in
            var item = try #require(library.item(id))
            change(&item)
            return item
        }
        source.send(.upserted(items))
        let expected = Dictionary(uniqueKeysWithValues: items.map { ($0.id, ($0.state, $0.tier)) })
        try #require(await eventually { expected.allSatisfy { library.item($0.key)?.state == $0.value.0 && library.item($0.key)?.tier == $0.value.1 } })
    }

    /// Every write so far is in the copy and accepted.
    private func acceptAll(_ source: FakeItemSource) {
        for write in source.submitted {
            source.send(.taken(write.id))
            source.send(.answered(write.id, .accepted))
        }
        source.clearWrites()
    }

    @Test func archiveTakesWhatIsActiveBeneathAndItsUndoMovesBackOnlyWhatItChanged() async throws {
        let (library, source) = try await loaded()
        let plan = library.archivePlan([F.p1])
        #expect(plan.archiving == [F.p1])
        #expect(plan.beneath == [F.e1], "Bug one is archived already, and the item in the bin is left there")

        let undo = UndoManager()
        let outcome = library.archive([F.p1], beneath: true, undoManager: undo)
        #expect(outcome == CommandOutcome(changed: 2, onlyItem: nil, skips: BatchSkips()))
        #expect(Set(source.writes) == [.transition(F.p1, .archived, from: .active), .transition(F.e1, .archived, from: .active)])
        try await show([F.p1, F.e1], in: library, source) { $0.state = .archived }
        acceptAll(source)

        // Another device moves Epic task to Recently Deleted.
        try await show([F.e1], in: library, source) { $0.state = .trashed }
        undo.undo()
        #expect(Set(source.writes) == [.transition(F.p1, .active, from: .archived), .transition(F.e1, .active, from: .archived)])
        // The engine queues the one the copy shows archived and skips the one in the bin.
        let epic = try #require(source.submitted.first { $0.write == .transition(F.e1, .active, from: .archived) })
        let alpha = try #require(source.submitted.first { $0.write == .transition(F.p1, .active, from: .archived) })
        source.send(.answered(epic.id, .refused(MarfaEngine.skipped(.inBin).problem)))
        source.send(.taken(alpha.id))
        #expect(await eventually { library.notices.waiting.last?.message == BatchSkips.sentence(.inBin, count: 1) })
        #expect(library.notices.told == 1)
    }

    @Test func keepOnAnArchivedFeedItemChangesOnlyItsTierAndItsUndoMovesItBack() async throws {
        let (library, source) = try await loaded()
        try await show([F.n2], in: library, source) { $0.state = .archived }
        let item = try #require(library.item(F.n2))
        let undo = UndoManager()
        let outcome = library.setTier([F.n2, F.n1], to: .library, undoManager: undo)
        #expect(outcome.onlyItem == F.n2 && outcome.skips.isEmpty, "an item in the Library already needs nothing")
        #expect(library.movedMessage(.keep, outcome) == "Kept “Feed note” in the Library")
        #expect(source.writes == [.retier(F.n2, .library, base: item.version)])
        try await show([F.n2], in: library, source) { $0.tier = .library }
        acceptAll(source)
        #expect(library.item(F.n2)?.state == .archived)

        undo.undo()
        #expect(source.writes == [.retier(F.n2, .feed, base: item.version)])
        #expect(undo.undoActionName.isEmpty && undo.redoActionName == ItemMove.keep.name)
    }

    /// Keeps Feed note, whose write the copy shows, and answers it each of `outcomes` in turn.
    private func keep(answering outcomes: [WriteOutcome]) async throws -> (MarfaLibrary, FakeItemSource, UndoManager) {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setTier([F.n2], to: .library, undoManager: undo)
        let write = try #require(source.submitted.last)
        try await show([F.n2], in: library, source) { $0.tier = .library }
        source.send(.taken(write.id))
        for outcome in outcomes { source.send(.answered(write.id, outcome)) }
        try #require(await eventually { library.tierWrites.isEmpty })
        source.clearWrites()
        return (library, source, undo)
    }

    @Test func aKeepMergedOverAnotherDevicesKeepIsNotThisMacsToUndo() async throws {
        let (library, source, undo) = try await keep(answering: [.merged(fields: [MarfaMapping.tierField])])
        undo.undo()
        #expect(source.writes.isEmpty, "the other device's Keep stands")
        withExtendedLifetime(library) {}
    }

    @Test func aKeepBlockedThenWithdrawnLeavesNothingToUndo() async throws {
        let (library, source, undo) = try await keep(answering: [
            .blocked(.conflictUnresolved, nil), .refused(SyncProblem(code: MarfaEngine.withdrawnCode)),
        ])
        undo.undo()
        #expect(source.writes.isEmpty)
        withExtendedLifetime(library) {}
    }

    @Test func undoAndRedoLeaveATierAnotherDeviceSetAlone() async throws {
        let (library, source, undo) = try await keep(answering: [.accepted])
        // Another device moves Feed note back to the Feed, and the engine skips the Undo's write.
        try await show([F.n2], in: library, source) { $0.tier = .feed }
        undo.undo()
        let write = try #require(source.submitted.last)
        source.send(.answered(write.id, .refused(MarfaEngine.skipped(.changedSince).problem)))
        #expect(await eventually { library.notices.waiting.last?.message == BatchSkips.sentence(.changedSince, count: 1) })
        source.clearWrites()
        undo.redo()
        #expect(source.writes.isEmpty, "the redo leaves the item in the Feed where the other device put it")
    }

    @Test func anUndoPressedWhileTheKeepIsUnansweredWaitsAndLeavesAnotherDevicesKeep() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setTier([F.n2], to: .library, undoManager: undo)
        let keep = try #require(source.submitted.last)
        try await show([F.n2], in: library, source) { $0.tier = .library }
        source.send(.taken(keep.id))
        source.clearWrites()

        undo.undo()
        #expect(source.writes.isEmpty, "only the server's answer says whose Keep stands")
        #expect(library.notices.waiting.last?.message.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        #expect(await eventually { undo.canUndo }, "the Undo goes back on its stack")

        // The Keep meets another device's Keep and is merged over it.
        source.send(.answered(keep.id, .merged(fields: [MarfaMapping.tierField])))
        try #require(await eventually { library.tierWrites.isEmpty })
        undo.undo()
        #expect(source.writes.isEmpty, "the other device's Keep stands")
        #expect(library.notices.waiting.last?.message == String(localized: "That change wasn’t made, so there is nothing to undo here."))
    }

    @Test func aMixedSelectionOffersBothTiersAndACollectionStaysInTheLibrary() async throws {
        let (library, _) = try await loaded()
        #expect(library.selectionCommands([F.n1, F.n2, F.t1]) == [.keep, .moveToFeed, .archive, .unarchive])
        #expect(library.selectionCommands([F.n2]) == [.keep, .archive])
        #expect(library.selectionCommands([F.n3]).isEmpty, "an item in the bin offers none")

        let (collections, _) = try await MarfaCollectionsTests().loaded()
        let holiday = MarfaCollectionsTests.holiday
        #expect(collections.selectionCommands([holiday]) == [.archive])
        var stays = BatchSkips()
        stays.skip(.staysInLibrary)
        #expect(collections.tierPlan([holiday, F.n1], to: .feed) == ([F.n1], stays))
    }
}
