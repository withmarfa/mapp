import Foundation
import Testing
@testable import MarfaMac

/// Keep, Move to Feed, Archive and Unarchive: what each moves, and that an Undo moves back only what it changed.
/// Alpha holds Epic task, which holds Bug one; Bug one is archived already and holds an item in the bin.
@MainActor
@Suite(.hangLimit) struct ItemMovesTests {
    typealias F = LibraryFixture

    static let binned = ItemID("binned")

    private func loaded(adding extra: [Item] = []) async throws -> (MarfaLibrary, FakeItemSource) {
        let items = F.items.map { item in
            var item = item
            if item.id == F.t1 { item.state = .archived }
            return item
        } + [F.item(Self.binned, F.note, "Binned child", age: 10, state: .trashed, edges: [F.child("c9", Self.binned, of: F.t1)])] + extra
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

    @Test func archiveCountsOnlyWhatIsBeneathTheItemsItWillArchive() async throws {
        let under = ItemID("under")
        let (library, _) = try await loaded(adding: [F.item(under, F.note, "Under the archived", age: 10, edges: [F.child("c8", under, of: F.t1)])])
        let plan = library.archivePlan([F.t1, F.n1])
        #expect(plan.archiving == [F.n1])
        #expect(plan.beneath.isEmpty, "an item that is archived already adds nothing beneath it")
    }

    @Test func archiveTakesWhatIsActiveBeneathAndItsUndoMovesBackOnlyWhatItChanged() async throws {
        let (library, source) = try await loaded()
        let plan = library.archivePlan([F.p1])
        #expect(plan.archiving == [F.p1])
        #expect(plan.beneath == [F.e1], "Bug one is archived already, and the item in the bin is left there")

        let undo = UndoManager()
        library.archive([F.p1], beneath: true, undoManager: undo)
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
        var outcome: CommandOutcome?
        library.setTier([F.n2, F.n1], to: .library, undoManager: undo) { outcome = $0 }
        #expect(source.writes == [.retier(F.n2, .library, base: item.version)])
        try await show([F.n2], in: library, source) { $0.tier = .library }
        acceptAll(source)
        // The Undo waits for the server's answer to the Keep, so the library takes it first.
        try #require(await eventually { library.tierWrites.isEmpty })
        let moved = try #require(outcome)
        #expect(moved.onlyItem == F.n2 && moved.skips.isEmpty, "an item in the Library already needs nothing")
        #expect(library.movedMessage(.keep, moved) == "Kept “Feed note” in the Library")
        #expect(library.item(F.n2)?.state == .archived)

        undo.undo()
        #expect(source.writes == [.retier(F.n2, .feed, base: item.version)])
        #expect(undo.undoActionName.isEmpty && undo.redoActionName == ItemMove.keep.name)
    }

    @Test func whatAMoveSaysItMovedIsWhatTheCopyQueued() async throws {
        let (library, source) = try await loaded()
        var outcome: CommandOutcome?
        library.archive([F.p1], beneath: true, undoManager: nil) { outcome = $0 }
        #expect(outcome == nil, "the engine has judged nothing yet")
        let epic = try #require(source.submitted.first { $0.write == .transition(F.e1, .archived, from: .active) })
        let alpha = try #require(source.submitted.first { $0.write == .transition(F.p1, .archived, from: .active) })
        // Another device moved Epic task to Recently Deleted before the engine queued its write.
        source.send(.answered(epic.id, .refused(MarfaEngine.skipped(.inBin).problem)))
        source.send(.taken(alpha.id))
        var skips = BatchSkips()
        skips.skip(.inBin)
        #expect(await eventually { outcome == CommandOutcome(changed: 1, onlyItem: F.p1, skips: skips) })
    }

    @Test func infoMovingALibraryItemToTheFeedIsOneStepAndItsUndoMovesItBack() async throws {
        let (library, source) = try await loaded()
        let item = try #require(library.item(F.n1))
        let undo = UndoManager()
        library.setTier([F.n1], to: .feed, undoManager: undo)
        #expect(source.writes == [.retier(F.n1, .feed, base: item.version)])
        try await show([F.n1], in: library, source) { $0.tier = .feed }
        acceptAll(source)
        try #require(await eventually { library.tierWrites.isEmpty })
        #expect(undo.undoActionName == ItemMove.moveToFeed.name)

        undo.undo()
        #expect(source.writes == [.retier(F.n1, .library, base: item.version)])
        #expect(!undo.canUndo, "one move is one step")
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

    @Test func aMenuListsTheTierMovesThenArchiveAndUnarchiveOnlyWhereNothingCanBeArchived() async throws {
        let (library, _) = try await loaded()
        #expect(ItemMove.inMenu(library.selectionCommands([F.n1, F.n2])) == [.keep, .moveToFeed, .archive])
        #expect(ItemMove.inMenu(library.selectionCommands([F.n2, F.t1])) == [.keep, .moveToFeed, .archive], "a mixed selection archives")
        let onlyArchived = ItemMove.inMenu(library.selectionCommands([F.t1]))
        #expect(onlyArchived.last == .unarchive && !onlyArchived.contains(.archive))
        #expect(ItemMove.inMenu(library.selectionCommands([F.n3])).isEmpty, "an item in the bin offers none")
    }

    /// What a window's manager does between events: this one opens no group of its own, so a move's group is its step.
    private static func manager() -> StepCountingUndoManager {
        let manager = StepCountingUndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test func aMoveSaysWhatItQueuedAndTheToastsUndoIsItsStep() async throws {
        let (library, source) = try await loaded()
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.move(.archive, [F.p1], in: library, undoManager: undo, toasts: toasts)
        #expect(toasts.current == nil, "the engine has judged nothing yet")
        let alpha = try #require(source.submitted.first { $0.write == .transition(F.p1, .archived, from: .active) })
        source.send(.taken(alpha.id))
        try #require(await eventually { toasts.current != nil })
        #expect(toasts.current?.message == "Archived “Alpha”")
        #expect(toasts.current?.undo != nil)

        source.clearWrites()
        try await show([F.p1], in: library, source) { $0.state = .archived }
        toasts.undo()
        toasts.undo()
        #expect(source.writes == [.transition(F.p1, .active, from: .archived)], "one undo, once")
        #expect(toasts.current == nil)
    }

    @Test func aMoveThatChangesNothingShowsNoToast() async throws {
        let (library, _) = try await loaded()
        let toasts = ToastPresenter()
        Browser.move(.unarchive, [F.p1], in: library, undoManager: Self.manager(), toasts: toasts)
        try await Task.sleep(for: .milliseconds(50))
        #expect(toasts.current == nil, "an active item needs nothing")
    }

    @Test func aMoveThatAsksFirstChangesNothingUntilAnswered() {
        let library = FakeItemLibrary(items: F.items)
        let details = DetailsPresentation()
        library.perform(.archive, on: [F.p1], undoManager: nil, details: details)
        #expect(details.archiving?.beneath == 2 && details.archiving?.ids == [F.p1])
        #expect(library.item(F.p1)?.state == .active && library.item(F.e1)?.state == .active)

        library.feedLimit = FeedLimitQuestion(pastWindow: 1)
        library.perform(.moveToFeed, on: [F.p1], undoManager: nil, details: details)
        #expect(details.feedLimit?.question == FeedLimitQuestion(pastWindow: 1))
        #expect(library.item(F.p1)?.tier == .library)

        library.feedLimit = nil
        library.perform(.moveToFeed, on: [F.p1], undoManager: nil, details: details)
        #expect(library.item(F.p1)?.tier == .feed, "with no question to ask, it moves")
    }
}
