import Foundation
import Synchronization
import Testing
@testable import MarfaMac

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
        Set(source.writes.compactMap { if case .transition(let id, .trashed, _) = $0 { id } else { nil } })
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
        #expect(DeletionWords.moveMessage(alsoTaking: 3) == "3 more items linked to them may also move to Recently Deleted.")
        #expect(DeletionWords.moveMessage(alsoTaking: 1) == "1 more item linked to them may also move to Recently Deleted.")
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

    @Test func aPreviewThatNeverAnswersAsksTheQuestionWithinTheDeadlineWithoutACount() async throws {
        let items = ids(3)
        let (library, source) = try await loaded(items)
        source.moreTaken.withLock { $0 = 4 }
        source.holdsPreviews.withLock { $0 = true }
        let details = DetailsPresentation()
        let selection = Set(items.map(\.id))
        await details.askToMove(selection, of: selection, in: library, undoManager: nil, within: .milliseconds(100))
        #expect(details.deletion?.ids == selection)
        #expect(details.deletion?.alsoTaking == nil)
        #expect(DetailsPresentation.previewDeadline == .milliseconds(1500))
    }

    @Test func aLateAnswerForAnEarlierDeleteNeverReopensIt() async throws {
        let items = ids(4)
        let (library, source) = try await loaded(items)
        source.moreTaken.withLock { $0 = 2 }
        let details = DetailsPresentation()
        let first = Set(items[0...1].map(\.id)), second = Set(items[2...3].map(\.id))
        source.holdsPreviews.withLock { $0 = true }
        let slow = Task { await details.askToMove(first, of: first, in: library, undoManager: nil, within: .seconds(60)) }
        try #require(await eventually { source.previewsAsked.withLock { $0.count } == 1 })
        source.holdsPreviews.withLock { $0 = false }
        await details.askToMove(second, of: second, in: library, undoManager: nil, within: .seconds(60))
        #expect(details.deletion?.ids == second)
        #expect(details.deletion?.alsoTaking == 2)
        details.deletion = nil
        source.releasePreviews()
        await slow.value
        #expect(details.deletion == nil, "the earlier question's late answer shows nothing")
    }

    @Test func theServerIsAskedByTheSizeOfTheWholeSelectionNotOfWhatMoves() async throws {
        let items = ids(21)
        let (library, source) = try await loaded(items)
        source.moreTaken.withLock { $0 = 1 }
        let details = DetailsPresentation()
        let all = Set(items.map(\.id)), moving = Set(items[0...1].map(\.id))
        await details.askToMove(moving, of: all, in: library, undoManager: nil)
        #expect(source.previewsAsked.withLock { $0 }.isEmpty, "21 chosen is never read, even where only 2 move")
        #expect(details.deletion?.alsoTaking == nil)

        let twenty = Set(items[0...19].map(\.id))
        await details.askToMove(moving, of: twenty, in: library, undoManager: nil)
        #expect(source.previewsAsked.withLock { $0.map(Set.init) } == [moving], "the ids that move are sent")
        #expect(details.deletion?.alsoTaking == 1)
    }
}
