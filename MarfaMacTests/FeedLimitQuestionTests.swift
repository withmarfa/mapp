import Foundation
import Testing
@testable import MarfaMac

/// Move to Feed asks only where the Feed would bin an item at once: an active item past its type's window.
/// Every date is a fixed instant, so no result depends on the machine's time zone or language.
@MainActor
@Suite(.hangLimit) struct FeedLimitQuestionTests {
    typealias F = LibraryFixture

    static let now = Date(timeIntervalSince1970: 100_000_000)
    static let day = 86_400.0
    /// Notes keep their feed items; Tickets, and the Tasks and Bugs under them, keep them 30 days; Projects 7.
    static let windowed = Catalogue(
        itemTypes: F.catalogue.itemTypes.values.map { info in
            var info = info
            switch info.id {
            case F.ticket, F.task, F.bug: info.feedDays = 30
            case F.project: info.feedDays = 7
            default: info.feedDays = nil
            }
            return info
        }, edgeTypes: Array(F.catalogue.edgeTypes.values))

    private func library(_ items: [Item], catalogue: Catalogue = windowed) async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    /// An item of `type` that arrived `days` days before `now`, plus `seconds`.
    private func item(
        _ id: String, _ type: TypeID, daysOld days: Double, plus seconds: Double = 0, state: ItemState = .active, tier: Tier = .library
    ) -> Item {
        var item = F.item(ItemID(id), type, id, age: 0, state: state, tier: tier)
        item.created = Self.now.addingTimeInterval(-(days * Self.day + seconds))
        return item
    }

    @Test func asksForAnItemPastItsWindowAndNotForOneInsideIt() async throws {
        let library = try await library([
            item("old", F.task, daysOld: 31), item("inside", F.task, daysOld: 29), item("edge", F.task, daysOld: 30),
            item("justPast", F.task, daysOld: 30, plus: 1),
        ])
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("old")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("inside")], now: Self.now) == nil)
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("edge")], now: Self.now) == nil, "Marfa waits until more than the window has passed")
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("justPast")], now: Self.now)?.pastWindow == 1)
    }

    @Test func asksNothingWhereNothingWouldBeBinned() async throws {
        let library = try await library([
            item("noWindow", F.note, daysOld: 400), item("archived", F.task, daysOld: 90, state: .archived),
            item("inFeed", F.task, daysOld: 90, tier: .feed), item("collection", F.album, daysOld: 90),
            item("unknown", TypeID("no.such"), daysOld: 90),
        ])
        for id in ["noWindow", "archived", "inFeed", "collection", "unknown"] {
            #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID(id)], now: Self.now) == nil, "\(id)")
        }
    }

    @Test func aTypeTheCatalogueLacksIsNotAsked() async throws {
        let library = try await library([item("old", F.task, daysOld: 90)], catalogue: Catalogue())
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("old")], now: Self.now) == nil)
    }

    @Test func aSelectionCountsOnlyTheItemsPastTheirWindow() async throws {
        let library = try await library([
            item("a", F.task, daysOld: 40), item("b", F.bug, daysOld: 31), item("c", F.task, daysOld: 5),
            item("d", F.note, daysOld: 400), item("e", F.task, daysOld: 99, tier: .feed), item("f", F.task, daysOld: 99, state: .archived),
            item("p", F.project, daysOld: 8),
        ])
        let ids = Set(["a", "b", "c", "d", "e", "f"].map { ItemID($0) })
        #expect(library.feedLimitQuestion(.moveToFeed, for: ids, now: Self.now) == FeedLimitQuestion(pastWindow: 2, window: nil),
                "two types share no one window")
        #expect(library.feedLimitQuestion(.moveToFeed, for: ids.union([ItemID("p")]), now: Self.now)?.pastWindow == 3)
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("a"), ItemID("c"), ItemID("d")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
    }

    @Test func theWindowEndsOnlyWhereTheTypeHasOne() {
        let old = item("old", F.task, daysOld: 10)
        #expect(Self.windowed.feedExpiry(of: old) == old.created.addingTimeInterval(30 * Self.day))
        #expect(Self.windowed.feedExpiry(of: item("note", F.note, daysOld: 10)) == nil)
        #expect(Catalogue().feedExpiry(of: old) == nil)
    }

    @Test func anItemWhoseCreationIsUnknownHasNoWindowAndIsNotAsked() async throws {
        var unknown = item("unknown", F.task, daysOld: 0)
        unknown.created = .distantPast
        #expect(Self.windowed.feedExpiry(of: unknown) == nil)
        var archived = item("archived", F.task, daysOld: 0, state: .archived, tier: .feed)
        archived.created = .distantPast
        let library = try await library([unknown, archived])
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("unknown")], now: Self.now) == nil)
        #expect(library.feedLimitQuestion(.unarchive, for: [ItemID("archived")], now: Self.now) == nil)
        unknown.tier = .feed
        #expect(Self.windowed.leavesTheFeed(unknown, now: Self.now) == nil)
    }

    @Test func infoSaysNothingOfADateAlreadyPast() {
        var inFeed = item("feed", F.task, daysOld: 10, tier: .feed)
        #expect(Self.windowed.leavesTheFeed(inFeed, now: Self.now) == inFeed.created.addingTimeInterval(30 * Self.day))
        inFeed.created = Self.now.addingTimeInterval(-31 * Self.day)
        #expect(Self.windowed.leavesTheFeed(inFeed, now: Self.now) == nil, "the job is behind or off, or the item was restored")
        #expect(Self.windowed.leavesTheFeed(item("lib", F.task, daysOld: 10), now: Self.now) == nil, "not in the Feed")
        #expect(Self.windowed.leavesTheFeed(item("arc", F.task, daysOld: 10, state: .archived, tier: .feed), now: Self.now) == nil)
        #expect(Self.windowed.leavesTheFeed(item("note", F.note, daysOld: 10, tier: .feed), now: Self.now) == nil, "no window")
    }

    // MARK: Unarchive

    @Test func unarchiveAsksForAnArchivedFeedItemPastItsWindowOnly() async throws {
        let library = try await library([
            item("old", F.task, daysOld: 31, state: .archived, tier: .feed), item("inside", F.task, daysOld: 29, state: .archived, tier: .feed),
            item("edge", F.task, daysOld: 30, state: .archived, tier: .feed), item("inLibrary", F.task, daysOld: 90, state: .archived),
            item("active", F.task, daysOld: 90, tier: .feed), item("noWindow", F.note, daysOld: 400, state: .archived, tier: .feed),
        ])
        #expect(library.feedLimitQuestion(.unarchive, for: [ItemID("old")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
        for id in ["inside", "edge", "inLibrary", "active", "noWindow"] {
            #expect(library.feedLimitQuestion(.unarchive, for: [ItemID(id)], now: Self.now) == nil, "\(id)")
        }
        #expect(library.feedLimitQuestion(.moveToFeed, for: [ItemID("inLibrary")], now: Self.now) == nil, "Move to Feed leaves an archived item archived")
    }

    @Test func unarchiveCountsOnlyTheArchivedFeedItemsPastTheirWindow() async throws {
        let library = try await library([
            item("a", F.task, daysOld: 40, state: .archived, tier: .feed), item("b", F.bug, daysOld: 31, state: .archived, tier: .feed),
            item("c", F.task, daysOld: 5, state: .archived, tier: .feed), item("d", F.task, daysOld: 99, state: .archived),
            item("e", F.task, daysOld: 99, tier: .feed),
        ])
        let ids = Set(["a", "b", "c", "d", "e"].map(ItemID.init))
        #expect(library.feedLimitQuestion(.unarchive, for: ids, now: Self.now) == FeedLimitQuestion(pastWindow: 2, window: nil))
        #expect(library.feedLimitQuestion(.unarchive, for: [ItemID("a"), ItemID("c"), ItemID("d"), ItemID("e")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
    }

    @Test func unarchiveAsksBeforeItActs() async throws {
        let library = try await library([item("old", F.task, daysOld: 400, state: .archived, tier: .feed)])
        let details = DetailsPresentation()
        library.perform(.unarchive, on: [ItemID("old")], undoManager: nil, details: details)
        #expect(details.feedLimit?.move == .unarchive)
        #expect(details.feedLimit?.ids == [ItemID("old")])
        #expect(library.item(ItemID("old"))?.state == .archived, "nothing changes until the person goes on")
    }

    // MARK: Words

    @Test func theWordsSayWhatHappensAndCountTheItemsAtRisk() {
        let tasks = FeedLimitQuestion.Window(typePlural: "Tasks", days: 30)
        let gone = "within the hour."
        // One item: the board's form.
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 1, question: FeedLimitQuestion(pastWindow: 1, window: tasks))
            == "Tasks leave the Feed after 30 days, and this one is older. It would go to Recently Deleted \(gone)")
        #expect(MoveWords.feedMessage(.unarchive, selected: 1, question: FeedLimitQuestion(pastWindow: 1, window: tasks))
            == "Tasks leave the Feed after 30 days, and this one is older. Unarchived, it would go to Recently Deleted \(gone)")
        // Some of a selection.
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 5, question: FeedLimitQuestion(pastWindow: 1, window: tasks))
            == "Tasks leave the Feed after 30 days, and 1 of the 5 items is older. It would go to Recently Deleted \(gone)")
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 5, question: FeedLimitQuestion(pastWindow: 3, window: tasks))
            == "Tasks leave the Feed after 30 days, and 3 of the 5 items are older. They would go to Recently Deleted \(gone)")
        #expect(MoveWords.feedMessage(.unarchive, selected: 5, question: FeedLimitQuestion(pastWindow: 5, window: tasks))
            == "Tasks leave the Feed after 30 days, and all 5 are older. Unarchived, they would go to Recently Deleted \(gone)")
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 2, question: FeedLimitQuestion(pastWindow: 2, window: tasks))
            == "Tasks leave the Feed after 30 days, and both are older. They would go to Recently Deleted \(gone)")
        // Types with no one window.
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 4, question: FeedLimitQuestion(pastWindow: 2, window: nil))
            == "The Feed lets items go after a while, and 2 of the 4 items are older. They would go to Recently Deleted \(gone)")
        #expect(MoveWords.feedMessage(.moveToFeed, selected: 1, question: FeedLimitQuestion(pastWindow: 1, window: nil))
            == "The Feed lets items go after a while, and this one is older. It would go to Recently Deleted \(gone)")
    }

    @Test func theTitleNamesTheMove() {
        #expect(MoveWords.feedTitle(.moveToFeed, selected: 1, title: "Call Ruth") == "Move “Call Ruth” to the Feed?")
        #expect(MoveWords.feedTitle(.unarchive, selected: 1, title: "Call Ruth") == "Unarchive “Call Ruth”?")
        #expect(MoveWords.feedTitle(.unarchive, selected: 3, title: nil) == "Unarchive 3 items?")
        #expect(MoveWords.feedTitle(.moveToFeed, selected: 3, title: nil) == "Move 3 items to the Feed?")
    }
}
