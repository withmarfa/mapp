import Foundation
import SwiftUI
import Testing
@testable import MarfaMac

/// Where a window can be, how a saved view finds its place, and what earlier copies kept, read once into the new places.
@MainActor
@Suite(.hangLimit)
struct PlacesTests {
    private static func choice(_ layout: ItemViewMode? = nil, sort: [PlaceDefault.SortKey] = []) -> PlaceDefault {
        var value = PlaceDefault()
        value.layout = layout
        value.sort = sort
        return value
    }

    typealias F = LibraryFixture

    // MARK: The home rule

    private static func home(_ query: LibraryViewQuery) -> Place {
        Place.home(of: query, catalogue: F.catalogue)
    }

    @Test func aSavedViewBelongsToTheOnePlaceItNarrowsTo() {
        #expect(Self.home(LibraryViewQuery(types: [F.task], filter: #"source eq "mail""#)) == .type(F.task))
        #expect(Self.home(LibraryViewQuery(types: [F.task, F.bug])) == .library, "two types are the Library's")
        #expect(Self.home(LibraryViewQuery(filter: #"edge[in-collection] eq "c1""#)) == .collection(ItemID("c1")))
        #expect(Self.home(LibraryViewQuery(tier: .feed, filter: #"source eq "mail""#)) == .source("mail"))
        #expect(Self.home(LibraryViewQuery(tier: .feed)) == .feed)
        #expect(Self.home(LibraryViewQuery(tier: .feed, filter: #"properties.status eq "done""#)) == .feed)
        #expect(Self.home(LibraryViewQuery(types: [F.task, F.bug], tier: .feed)) == .library, "types narrow it past the Feed")
        #expect(Self.home(LibraryViewQuery()) == .library)
    }

    // MARK: Reading what is stored

    @Test func aPlaceWordThisCopyDoesNotKnowIsSkippedWhereItIsRead() throws {
        for place in [Place.library, .feed, .type(F.task), .collection(ItemID("c1")), .source("mail"), .types, .collections, .sources, .archive] {
            #expect(Place(word: place.word) == place)
        }
        #expect(Place(word: "later") == nil)
        #expect(Place(word: "type:") == nil)
        let read = try JSONDecoder().decode([String: Place].self, from: Data(#"{"a":"feed"}"#.utf8))
        #expect(read == ["a": .feed])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Place.self, from: Data(#""later""#.utf8)) }
        // Kept where it is stored: a key this copy cannot read is left among the defaults.
        let defaults = ThrowawayDefaults.make("PlacesTests.unknownWord")
        defaults.set(try JSONEncoder().encode(["later": Self.choice(.board), "feed": Self.choice(.table)]), forKey: PlaceDefaults.key)
        PlaceDefaults.update(in: defaults) { $0.set(Self.choice(.timeline), for: .library) }
        let kept = try JSONDecoder().decode([String: PlaceDefault].self, from: try #require(defaults.data(forKey: PlaceDefaults.key)))
        #expect(kept["later"]?.layout == .board)
        #expect(PlaceDefaults.stored(in: defaults).keptPlaces.count == 2)
    }

    @Test func aViewChoiceThisCopyDoesNotKnowReadsAsThePlacesOwn() throws {
        #expect(ViewChoice(word: "favorites") == .favorites)
        #expect(ViewChoice(word: "saved:v1") == .saved(ItemID("v1")))
        #expect(ViewChoice(word: "later") == .own)
        #expect(ViewChoice(word: "saved:") == .own)
        #expect(try JSONDecoder().decode(ViewChoice.self, from: Data(#""pinned""#.utf8)) == .own)
        #expect(PlaceView(storageKey: "type:core.task|later") == .type(TypeID("core.task")))
        #expect(PlaceView(storageKey: PlaceView.favorites.storageKey) == .favorites)
        #expect(PlaceView(storageKey: "saved:v1") == .saved(ItemID("v1")))
    }

    // MARK: Earlier copies

    @Test func eachEarlierPlaceReadsAsTheOneThatStandsForItNow() {
        #expect(EarlierPlace.read(key: #"{"inbox":{}}"#) == .place(.feed))
        #expect(EarlierPlace.read(key: #"{"allNotes":{}}"#) == .place(.library))
        #expect(EarlierPlace.read(key: #"{"recents":{}}"#) == .place(.library))
        #expect(EarlierPlace.read(key: #"{"favorites":{}}"#) == .place(.favorites))
        #expect(EarlierPlace.read(key: #"{"favoriteItem":{"_0":"n1"}}"#) == .place(.library, selecting: ItemID("n1")))
        #expect(EarlierPlace.read(key: #"{"itemType":{"_0":"core.task"}}"#) == .place(.type(TypeID("core.task"))))
        #expect(EarlierPlace.read(key: #"{"view":{"_0":"v1"}}"#) == .place(.saved(ItemID("v1"))))
        #expect(EarlierPlace.read(key: #"{"files":{}}"#) == .files)
        #expect(EarlierPlace.read(key: "feed") == nil)
    }

    @Test func aTypesAndASavedViewsColumnsAndSortCarryOver() throws {
        let defaults = ThrowawayDefaults.make("PlacesTests.carried")
        let sort = Self.choice(sort: [PlaceDefault.SortKey(column: "title", reversed: true)])
        let earlier = [
            #"{"itemType":{"_0":"core.task"}}"#: sort,
            #"{"view":{"_0":"v1"}}"#: Self.choice(.board),
            #"{"recents":{}}"#: Self.choice(.timeline),
            #"{"files":{}}"#: Self.choice(.gallery),
        ]
        defaults.set(try JSONEncoder().encode(earlier), forKey: PlaceDefaults.key)
        let stored = PlaceDefaults.stored(in: defaults)
        #expect(stored.default(for: .type(TypeID("core.task"))) == sort)
        #expect(stored.default(for: .saved(ItemID("v1")))?.layout == .board)
        // Recents shares the Library with All Items, and Files is no place, so neither moves, and both stay stored.
        #expect(stored.default(for: .library) == nil)
        #expect(stored.places[#"{"recents":{}}"#] != nil && stored.places[#"{"files":{}}"#] != nil)

        let columns = TableColumnCustomization<ItemTableRow>()
        let widths = try JSONEncoder().encode([#"{"itemType":{"_0":"core.task"}}"#: columns, #"{"view":{"_0":"v1"}}"#: columns])
        // Each is found at its new key, so it can be cleared there.
        #expect(ItemTableColumnLayouts.removing(.type(TypeID("core.task")), in: widths) != widths)
        #expect(ItemTableColumnLayouts.removing(.saved(ItemID("v1")), in: widths) != widths)
        #expect(ItemTableColumnLayouts.removing(.library, in: widths) == widths)

        // A density kept for All Items is the Library's.
        defaults.set(try JSONEncoder().encode([#"{"allNotes":{}}"#: "compact"]), forKey: PlaceDensities.key)
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .compact)
    }

    @Test func filesIsToldOnceAndWhatWasKeptForItStaysReadable() throws {
        let defaults = ThrowawayDefaults.make("PlacesTests.files")
        let left = #"{"files":{}}"#
        defaults.set(left, forKey: StartWith.lastPlaceKey)
        let library = FakeItemLibrary(items: [])
        for _ in 0..<2 {
            let browser = Browser()
            browser.defaults = defaults
            browser.restore(from: nil, in: library, order: ItemOrder())
            #expect(browser.shown == .library)
        }
        #expect(library.notices.waiting.count == 1)
        #expect(defaults.string(forKey: StartWith.lastPlaceKey) == left, "an earlier copy still reads it")

        let window = Data(#"{"place":{"files":{}},"selection":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(Browser.Snapshot.self, from: window)
        #expect(snapshot.place == .library && snapshot.leftFiles)
    }

    // MARK: Counts

    private static let ticketOwn = ItemID("t-own"), taskHere = ItemID("t-task"), bugFed = ItemID("t-bug"), taskKept = ItemID("t-kept")

    private static func counted() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [
            F.item(ticketOwn, F.ticket, "Own", age: 1),
            F.item(taskHere, F.task, "Task", age: 2),
            F.item(bugFed, F.bug, "Bug", age: 3, tier: .feed),
            F.item(taskKept, F.task, "Archived", age: 4, state: .archived),
        ], catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    @Test func aTypeCountsItsKindsByTierFromTheIndex() async throws {
        let library = try await Self.counted()
        let ticket = Place.type(F.ticket)
        #expect(library.scopeCounts(in: ticket) == ScopeCounts(library: 2, feed: 1))
        #expect(library.count(in: ticket, scope: .all) == 3)
        #expect(library.count(in: ticket, scope: .feed) == 1)
        #expect(library.count(in: .type(F.task), scope: .all) == 1, "an archived item is not counted")
        #expect(library.count(in: Place.library, scope: .all) == 2, "the Library counts its tier whatever the From")
        #expect(library.count(in: Place.feed, scope: .all) == 1)
        #expect(library.items(in: ticket, scope: .all, archived: .hidden, includingKinds: false).map(\.id) == [Self.ticketOwn])
        #expect(library.items(in: ticket, scope: .library, archived: .only, includingKinds: true).map(\.id) == [Self.taskKept])
        #expect(Set(library.items(in: ticket, scope: .all, archived: .shown, includingKinds: true).map(\.id)).count == 4)
        #expect(ListScope.showsScopeControl(place: ticket, counts: library.scopeCounts(in: ticket)))
        #expect(!ListScope.showsScopeControl(place: .type(F.task), counts: library.scopeCounts(in: .type(F.task))))
        #expect(!ListScope.showsScopeControl(place: .library, counts: ScopeCounts(library: 2, feed: 1)))
    }
}
