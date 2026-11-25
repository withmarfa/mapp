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
        #expect(library.feedLimitQuestion(for: [ItemID("old")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
        #expect(library.feedLimitQuestion(for: [ItemID("inside")], now: Self.now) == nil)
        #expect(library.feedLimitQuestion(for: [ItemID("edge")], now: Self.now) == nil, "Marfa waits until more than the window has passed")
        #expect(library.feedLimitQuestion(for: [ItemID("justPast")], now: Self.now)?.pastWindow == 1)
    }

    @Test func asksNothingWhereNothingWouldBeBinned() async throws {
        let library = try await library([
            item("noWindow", F.note, daysOld: 400), item("archived", F.task, daysOld: 90, state: .archived),
            item("inFeed", F.task, daysOld: 90, tier: .feed), item("collection", F.album, daysOld: 90),
            item("unknown", TypeID("no.such"), daysOld: 90),
        ])
        for id in ["noWindow", "archived", "inFeed", "collection", "unknown"] {
            #expect(library.feedLimitQuestion(for: [ItemID(id)], now: Self.now) == nil, "\(id)")
        }
    }

    @Test func aTypeTheCatalogueLacksIsNotAsked() async throws {
        let library = try await library([item("old", F.task, daysOld: 90)], catalogue: Catalogue())
        #expect(library.feedLimitQuestion(for: [ItemID("old")], now: Self.now) == nil)
    }

    @Test func aSelectionCountsOnlyTheItemsPastTheirWindow() async throws {
        let library = try await library([
            item("a", F.task, daysOld: 40), item("b", F.bug, daysOld: 31), item("c", F.task, daysOld: 5),
            item("d", F.note, daysOld: 400), item("e", F.task, daysOld: 99, tier: .feed), item("f", F.task, daysOld: 99, state: .archived),
            item("p", F.project, daysOld: 8),
        ])
        let ids = Set(["a", "b", "c", "d", "e", "f"].map { ItemID($0) })
        #expect(library.feedLimitQuestion(for: ids, now: Self.now) == FeedLimitQuestion(pastWindow: 2, window: nil),
                "two types share no one window")
        #expect(library.feedLimitQuestion(for: ids.union([ItemID("p")]), now: Self.now)?.pastWindow == 3)
        #expect(library.feedLimitQuestion(for: [ItemID("a"), ItemID("c"), ItemID("d")], now: Self.now)
            == FeedLimitQuestion(pastWindow: 1, window: .init(typePlural: "Tasks", days: 30)))
    }

    @Test func theWindowEndsOnlyWhereTheTypeHasOne() {
        let old = item("old", F.task, daysOld: 10)
        #expect(Self.windowed.feedExpiry(of: old) == old.created.addingTimeInterval(30 * Self.day))
        #expect(Self.windowed.feedExpiry(of: item("note", F.note, daysOld: 10)) == nil)
        #expect(Catalogue().feedExpiry(of: old) == nil)
    }
}
