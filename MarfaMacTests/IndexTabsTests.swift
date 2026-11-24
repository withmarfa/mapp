import Foundation
import Testing
@testable import MarfaMac

/// What each tab of an index page lists, how a table's header sorts it, and what choosing a container does when it goes.
@MainActor
@Suite(.hangLimit) struct IndexTabsTests {
    private func source(_ code: String, count: Int = 1, latest: Date? = nil) -> IndexRow {
        IndexRow(place: .source(code), title: code, icon: .symbol("x"), types: "", count: count, latest: latest, breakdown: [])
    }

    private func collection(_ title: String, tier: Tier, count: Int = 1) -> IndexRow {
        IndexRow(
            place: .collection(ItemID(title)), title: title, icon: .symbol("x"), types: "", count: count, latest: nil, breakdown: [],
            tier: tier)
    }

    // MARK: Deleting a collection

    @Test func deletingACollectionKeepsItsMembersAndOffersUndo() async throws {
        let (library, source) = try await MarfaCollectionsTests().loaded()
        let holiday = MarfaCollectionsTests.holiday
        let members = library.items(in: .collection(holiday)).map(\.id)
        #expect(members.count == 3)
        let toasts = ToastPresenter()
        let undo = StepCountingUndoManager()
        // A test has no run loop to close an event's group, so the delete gets a group of its own.
        undo.groupsByEvent = false
        Browser.delete([holiday], in: library, undoManager: undo, toasts: toasts, naming: "Holiday")

        #expect(source.writes == [.transition(holiday, .trashed)], "the collection is written, and no member")
        #expect(toasts.current?.message == "Moved “Holiday” to Recently Deleted")
        #expect(toasts.current?.undo != nil)
        for id in members {
            let member = try #require(library.item(id))
            #expect(member.state == .active)
            #expect(member.collectionIDs.contains(holiday), "a member keeps its place in the collection that is in Recently Deleted")
        }

        source.clearWrites()
        toasts.undo()
        #expect(source.writes == [.transition(holiday, .active)], "Undo brings back the collection alone")
    }

    @Test func deletingACollectionThatIsAlreadyGoneShowsNoToast() async throws {
        let (library, source) = try await MarfaCollectionsTests().loaded()
        let toasts = ToastPresenter()
        // The collection is gone already: nothing moves, so nothing is claimed.
        Browser.delete([ItemID("vanished")], in: library, undoManager: StepCountingUndoManager(), toasts: toasts, naming: "Vanished")
        #expect(toasts.current == nil)
        #expect(source.writes.isEmpty)
    }
}
