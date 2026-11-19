import Foundation
import Synchronization
import Testing
@testable import MAPP

/// The question before moving several items to Recently Deleted may say how many more items go with them, read from
/// the server; the move itself is always one queued delete for each selected item.
@MainActor
@Suite(.hangLimit) struct MoveToBinQuestionTests {
    private static func note(_ id: String, state: ItemState = .active) -> Item {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var item = Item(
            id: ItemID(id), type: TypeChangeFixture.note, title: id, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(id))], version: ItemVersion(1), created: date, modified: date)
        item.state = state
        return item
    }

    private func loaded(_ items: [Item], online: Bool = true) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for item in items { source.setBody("Text of \(item.id.rawValue)", of: item.id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: TypeChangeFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        if online {
            source.state.set(.online)
            try #require(await eventually { library.reachesServer })
        } else {
            source.state.set(.offline(reason: nil))
            try #require(await eventually { !library.reachesServer })
        }
        return (library, source)
    }

    private func ids(_ count: Int) -> [Item] { (1...count).map { Self.note("n\($0)") } }

    private func deletes(_ source: FakeItemSource) -> Set<ItemID> {
        Set(source.writes.compactMap { if case .transition(let id, .trashed) = $0 { id } else { nil } })
    }

    @Test(arguments: [2, 7, 20])
    func onlineTheQuestionNamesWhatTheServerSaysGoesWithThem(count: Int) async throws {
        let items = ids(count)
        let (library, source) = try await loaded(items)
        source.moreTaken.withLock { $0 = 3 }
        let selection = Set(items.map(\.id))
        #expect(await library.moreItemsTaken(with: selection) == 3)
        #expect(source.previewsAsked.withLock { $0.map(Set.init) } == [selection], "one read, naming exactly the selection")
        #expect(source.writes.isEmpty, "reading changes nothing")
        let message = DeletionWords.moveMessage(alsoTaking: 3)
        #expect(message.hasPrefix("Moving them also moves at least 3 more items that go with them."))
        #expect(message.hasSuffix("You can bring everything back from Recently Deleted."))
        #expect(DeletionWords.moveMessage(alsoTaking: 1).hasPrefix("Moving them also moves at least 1 more item that goes with them."))
    }

    @Test func aPreviewThatNamesNothingMoreSaysNothingMore() async throws {
        let items = ids(2)
        let (library, source) = try await loaded(items)
        source.moreTaken.withLock { $0 = 0 }
        #expect(await library.moreItemsTaken(with: Set(items.map(\.id))) == 0)
        #expect(DeletionWords.moveMessage(alsoTaking: 0) == "You can bring them back from Recently Deleted.")
    }

    @Test func offlineOverTwentyOrAFailedPreviewGivesNoCountAndNoPackageText() async throws {
        let few = ids(3)
        let (offline, offlineSource) = try await loaded(few, online: false)
        offlineSource.moreTaken.withLock { $0 = 5 }
        #expect(await offline.moreItemsTaken(with: Set(few.map(\.id))) == nil)
        #expect(offlineSource.previewsAsked.withLock { $0 }.isEmpty, "offline never asks the server")

        let many = ids(21)
        let (big, bigSource) = try await loaded(many)
        bigSource.moreTaken.withLock { $0 = 5 }
        #expect(await big.moreItemsTaken(with: Set(many.map(\.id))) == nil)
        #expect(bigSource.previewsAsked.withLock { $0 }.isEmpty, "more than 20 is never read")

        let (failing, failingSource) = try await loaded(few)
        failingSource.moreTaken.withLock { $0 = nil }
        #expect(await failing.moreItemsTaken(with: Set(few.map(\.id))) == nil)
        #expect(DeletionWords.moveMessage(alsoTaking: nil) == "You can bring them back from Recently Deleted.")
        #expect(failing.notices.told == 0, "a failed preview tells nothing")
    }

    @Test(arguments: [
        (2, true, 4 as Int?), (3, true, nil), (3, false, 4), (21, true, 4),
    ])
    func theMoveIsAlwaysAQueuedDeleteOfExactlyTheSelectedItems(count: Int, online: Bool, taking: Int?) async throws {
        let items = ids(count) + [Self.note("other")]
        let (library, source) = try await loaded(items, online: online)
        source.moreTaken.withLock { $0 = taking }
        let selection = Set(items.dropLast().map(\.id))
        _ = await library.moreItemsTaken(with: selection)
        source.clearWrites()
        Browser.moveToRecentlyDeleted(selection, in: library, undoManager: nil, toasts: nil)
        #expect(deletes(source) == selection)
        #expect(source.writes.count == count, "one queued delete for each item, nothing else")
    }

    @Test func undoingTheDeleteOfAnArchivedItemRestoresThenArchivesItAgain() async throws {
        let (library, source) = try await loaded([Self.note("a", state: .archived), Self.note("b")])
        let undo = StepCountingUndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        library.delete([ItemID("a"), ItemID("b")], undoManager: undo)
        undo.endUndoGrouping()
        #expect(source.writes.contains(.transition(ItemID("a"), .trashed)))

        source.clearWrites()
        undo.undo()
        let a = source.writes.filter { if case .transition(ItemID("a"), _) = $0 { true } else { false } }
        #expect(a == [.transition(ItemID("a"), .active), .transition(ItemID("a"), .archived)], "the server leaves the bin only to active")
        let b = source.writes.filter { if case .transition(ItemID("b"), _) = $0 { true } else { false } }
        #expect(b == [.transition(ItemID("b"), .active)])
    }
}
