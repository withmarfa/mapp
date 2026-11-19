import Foundation
import Testing
@testable import MAPP

/// A window's toast: what shows, when it leaves, and that Undo acts once. Time is a clock the test moves by hand.
@MainActor
@Suite(.hangLimit) struct ToastTests {
    private let clock = ManualClock()
    private let presenter: ToastPresenter

    init() { presenter = ToastPresenter(duration: .seconds(5), clock: clock) }

    /// Waits for the timer to be asleep on the clock, so advancing time reaches it.
    private func timerIsRunning() async -> Bool { await eventually { clock.sleeping == 1 } }

    @Test func aToastShowsWithItsMessage() {
        presenter.show("Moved to Recently Deleted", symbol: "trash")
        #expect(presenter.current?.message == "Moved to Recently Deleted")
        #expect(presenter.current?.symbol == "trash")
        #expect(presenter.current?.undo == nil)
    }

    @Test func aSecondToastReplacesTheFirstAndTheFirstsTimeNoLongerCounts() async {
        presenter.show("First")
        #expect(await timerIsRunning())
        clock.advance(by: .seconds(4))
        presenter.show("Second")
        #expect(presenter.current?.message == "Second")
        #expect(await timerIsRunning())
        clock.advance(by: .seconds(4))
        #expect(presenter.current?.message == "Second", "four seconds into the second toast, the first's time has passed")
        clock.advance(by: .seconds(1))
        #expect(await eventually { presenter.current == nil })
    }

    @Test func aToastLeavesOnItsOwnAfterItsTime() async {
        presenter.show("Moved")
        #expect(await timerIsRunning())
        clock.advance(by: .seconds(4))
        #expect(presenter.current != nil)
        clock.advance(by: .seconds(1))
        #expect(await eventually { presenter.current == nil })
    }

    @Test func aToastDoesNotLeaveWhileThePointerIsOverItAndStartsAgainWhenItLeaves() async {
        presenter.show("Moved")
        #expect(await timerIsRunning())
        presenter.hold(true)
        #expect(await eventually { clock.sleeping == 0 })
        clock.advance(by: .seconds(60))
        #expect(presenter.current?.message == "Moved")

        presenter.hold(false)
        #expect(await timerIsRunning())
        clock.advance(by: .seconds(4))
        #expect(presenter.current != nil, "the full time starts again")
        clock.advance(by: .seconds(1))
        #expect(await eventually { presenter.current == nil })
    }

    @Test func aToastThatExpiresAsThePointerArrivesStays() async {
        presenter.show("Moved")
        #expect(await timerIsRunning())
        presenter.hold(true)
        clock.advance(by: .seconds(5))
        #expect(presenter.current?.message == "Moved")
    }

    @Test func undoRunsTheActionOnceAndTakesTheToastAway() async {
        var undone = 0
        presenter.show("Moved", undo: { undone += 1 })
        presenter.undo()
        presenter.undo()
        #expect(undone == 1)
        #expect(presenter.current == nil)
        #expect(await eventually { clock.sleeping == 0 }, "the timer is cancelled with the toast")
    }

    @Test func undoAfterTheToastExpiredDoesNothing() async {
        var undone = 0
        presenter.show("Moved", undo: { undone += 1 })
        #expect(await timerIsRunning())
        clock.advance(by: .seconds(5))
        #expect(await eventually { presenter.current == nil })
        presenter.undo()
        #expect(undone == 0)
    }

    @Test func aToastWithNoUndoOffersNoneAndUndoDoesNotRemoveIt() {
        presenter.show("Copied")
        presenter.undo()
        #expect(presenter.current?.message == "Copied")
    }

    @Test func aReplacedToastsUndoIsNotRunByTheNewOne() {
        var first = 0, second = 0
        presenter.show("First", undo: { first += 1 })
        presenter.show("Second", undo: { second += 1 })
        presenter.undo()
        #expect(first == 0)
        #expect(second == 1)
    }

    @Test func eachWindowHasItsOwnPresenter() {
        let one = DetailsPresentation(), other = DetailsPresentation()
        one.toasts.show("Moved")
        #expect(one.toasts.current?.message == "Moved")
        #expect(other.toasts.current == nil)
    }

    @Test func theStandardTimeIsFiveSeconds() {
        #expect(ToastPresenter.standardDuration == .seconds(5))
    }
}

/// Deleting items shows the toast, and its Undo is the step the delete registered.
@MainActor
@Suite(.hangLimit) struct ToastDeleteTests {
    private func loaded(_ items: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for item in items { source.setBody("Text of \(item.id.rawValue)", of: item.id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: TypeChangeFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private static func note(_ id: String) -> Item {
        let date = Date(timeIntervalSince1970: 1_000_000)
        return Item(
            id: ItemID(id), type: TypeChangeFixture.note, title: id, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(id))], version: ItemVersion(1), created: date, modified: date)
    }

    @Test func movingOneItemToTheBinShowsTheToastAndItsUndoRecoversTheItemOnce() async throws {
        let (library, source) = try await loaded([Self.note("a"), Self.note("b")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        #expect(toasts.current?.message == "Moved to Recently Deleted")
        #expect(toasts.current?.undo != nil)

        source.clearWrites()
        toasts.undo()
        toasts.undo()
        #expect(source.writes == [.transition(ItemID("a"), .active)], "one undo, once")
        #expect(!undo.canUndo)
        #expect(toasts.current == nil)
    }

    @Test func movingSeveralItemsSaysHowMany() async throws {
        let (library, _) = try await loaded([Self.note("a"), Self.note("b"), Self.note("c")])
        let toasts = ToastPresenter()
        Browser.moveToRecentlyDeleted([ItemID("a"), ItemID("b")], in: library, undoManager: Self.manager(), toasts: toasts)
        #expect(toasts.current?.message == "Moved 2 items to Recently Deleted")
    }

    @Test func anotherChangeAfterTheDeleteTakesTheToastAway() async throws {
        let (library, source) = try await loaded([Self.note("a"), Self.note("b")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        undo.beginUndoGrouping()
        library.setFavorite([ItemID("b")], true, undoManager: undo)
        undo.endUndoGrouping()
        #expect(toasts.current == nil, "a later step ends the claim, so Undo is never offered for the wrong step")
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.isEmpty)
    }

    @Test func deletingAThenBThenUndoingBWithEditUndoLeavesAInTheBin() async throws {
        let (library, source) = try await loaded([Self.note("a"), Self.note("b")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        Browser.delete([ItemID("b")], in: library, undoManager: undo, toasts: toasts)
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.transition(ItemID("b"), .active)])
        #expect(toasts.current == nil)
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.isEmpty, "A stays deleted")
    }

    @Test func undoingThenRedoingTheDeleteTakesTheToastsUndoAway() async throws {
        let (library, source) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        undo.undo()
        #expect(toasts.current == nil)
        undo.redo()
        #expect(toasts.current == nil, "the redo is a step of the same name, and the toast does not take it for its own")
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.isEmpty)
        #expect(undo.canUndo, "the redone delete is still the person's to undo with Edit > Undo")
    }

    /// What a window's manager does between events: it closes its group at the end of each run loop pass, which a
    /// unit test cannot wait for. This one opens no group of its own, so the move's own group is the step, closed.
    private static func manager() -> StepCountingUndoManager {
        let manager = StepCountingUndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test func theUndoUndoesTheDeleteOnceItsGroupIsClosed() async throws {
        let (library, source) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        #expect(undo.groupingLevel == 0)
        #expect(toasts.current?.undo != nil)
        source.clearWrites()
        toasts.undo()
        #expect(source.writes == [.transition(ItemID("a"), .active)])
        #expect(!undo.canUndo)
    }

    @Test func anUndoPressedWhileTheDeletesGroupIsStillOpenDoesNothing() async throws {
        let (library, source) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        let undo = StepCountingUndoManager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        #expect(undo.groupingLevel == 1, "the manager's own group for this pass of the run loop is still open")
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.isEmpty, "an open group may hold more than the delete")
        #expect(undo.canUndo)
    }

    @Test func aDeleteSharingSomeoneElsesOpenGroupOffersNoUndo() async throws {
        let (library, source) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        #expect(toasts.current?.message == "Moved to Recently Deleted")
        #expect(toasts.current?.undo == nil, "undoing would take back the other steps in the group too")
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.isEmpty)
    }

    @Test func aSecondDeleteGetsItsOwnUndoAndTheFirstsToastIsGone() async throws {
        let (library, source) = try await loaded([Self.note("a"), Self.note("b")])
        let toasts = ToastPresenter()
        let undo = Self.manager()
        Browser.delete([ItemID("a")], in: library, undoManager: undo, toasts: toasts)
        Browser.delete([ItemID("b")], in: library, undoManager: undo, toasts: toasts)
        #expect(toasts.current?.undo != nil, "the second delete's step is the latest, though the first's claim ended")
        source.clearWrites()
        toasts.undo()
        #expect(source.writes == [.transition(ItemID("b"), .active)])
    }

    @Test func oneNamedItemNamesItInTheToast() async throws {
        var named = Self.note("a")
        named.name = "Kitchen quotes"
        let (library, _) = try await loaded([named, Self.note("b")])
        let toasts = ToastPresenter()
        Browser.moveToRecentlyDeleted([ItemID("a")], in: library, undoManager: Self.manager(), toasts: toasts)
        #expect(toasts.current?.message == "Moved “Kitchen quotes” to Recently Deleted")
        Browser.moveToRecentlyDeleted([ItemID("b")], in: library, undoManager: Self.manager(), toasts: toasts)
        #expect(toasts.current?.message == "Moved to Recently Deleted", "an item with no name keeps the plain wording")
    }

    @Test func nothingMovedShowsNoToast() async throws {
        let (library, _) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        Browser.moveToRecentlyDeleted([ItemID("ghost")], in: library, undoManager: Self.manager(), toasts: toasts)
        #expect(toasts.current == nil)
    }

    @Test func aWindowWithNoUndoManagerOffersNoUndo() async throws {
        let (library, _) = try await loaded([Self.note("a")])
        let toasts = ToastPresenter()
        Browser.delete([ItemID("a")], in: library, undoManager: nil, toasts: toasts)
        #expect(toasts.current?.message == "Moved to Recently Deleted")
        #expect(toasts.current?.undo == nil)
    }
}
