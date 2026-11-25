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
        // Only a condition every item must meet places the view, and only the collection's own edge is membership.
        #expect(Self.home(LibraryViewQuery(filter: #"backref[in-collection] eq "c1""#)) == .library)
        #expect(Self.home(LibraryViewQuery(filter: #"edge[in-collection] eq "c1" OR properties.status eq "done""#)) == .library)
        #expect(Self.home(LibraryViewQuery(filter: #"source eq "mail" OR source eq "web""#)) == .library)
        #expect(Self.home(LibraryViewQuery(filter: #"edge[in-collection] eq "c1" AND source eq "mail""#)) == .library)
        #expect(Self.home(LibraryViewQuery(tier: .feed, filter: #"source eq "mail" OR properties.status eq "done""#)) == .library)
        #expect(Self.home(LibraryViewQuery(filter: #"edge[in-collection] eq "c1" AND properties.status eq "done""#)) == .collection(ItemID("c1")))
        // A saved view at another home is another place shown, and the same view kept.
        let moved = PlaceView(.type(F.task), .saved(ItemID("v1")))
        #expect(moved != .saved(ItemID("v1")) && moved.isSame(.saved(ItemID("v1"))))
        var memory: PlaceMemory<Int> = [.saved(ItemID("v1")): 1]
        #expect(memory[moved] == 1)
        memory[moved] = 2
        #expect(memory[.saved(ItemID("v1"))] == 2)
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

    @Test func whatEarlierCopiesKeptIsCopiedOnceAndNeverRemoved() throws {
        let defaults = ThrowawayDefaults.make("PlacesTests.carried")
        let sort = Self.choice(sort: [PlaceDefault.SortKey(column: "title", reversed: true)])
        let earlier = [
            #"{"itemType":{"_0":"core.task"}}"#: sort,
            #"{"view":{"_0":"v1"}}"#: Self.choice(.board),
            #"{"allNotes":{}}"#: Self.choice(.table),
            #"{"recents":{}}"#: Self.choice(.timeline, sort: [PlaceDefault.SortKey(column: "updated", reversed: true)]),
            #"{"files":{}}"#: Self.choice(.gallery),
        ]
        defaults.set(try JSONEncoder().encode(earlier), forKey: PlaceDefaults.key)
        let columns = try JSONEncoder().encode([#"{"itemType":{"_0":"core.task"}}"#: TableColumnCustomization<ItemTableRow>()])
        defaults.set(columns, forKey: ItemTableColumnLayouts.key)
        defaults.set(try JSONEncoder().encode([#"{"recents":{}}"#: "compact"]), forKey: PlaceDensities.key)
        IndexPreferences.set(.feed, for: .items, in: defaults)
        EarlierPlace.readIn(in: defaults)
        // The Items page's From Apps tab would open the Library on an empty tab.
        #expect(IndexPreferences.tab(for: .items, in: defaults) == .all)

        let stored = PlaceDefaults.stored(in: defaults)
        #expect(stored.default(for: .type(TypeID("core.task"))) == sort)
        #expect(stored.default(for: .saved(ItemID("v1")))?.layout == .board)
        // All Items' choices are the Library's, and Recents fills what they leave.
        #expect(stored.default(for: .library) == Self.choice(.table, sort: [PlaceDefault.SortKey(column: "updated", reversed: true)]))
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .compact)
        let carriedColumns = try #require(defaults.data(forKey: ItemTableColumnLayouts.key))
        #expect(ItemTableColumnLayouts.removing(.type(TypeID("core.task")), in: carriedColumns) != carriedColumns)
        // Every earlier entry stays for the copies that read it, through a later write too.
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: .library) }
        let kept = try JSONDecoder().decode([String: PlaceDefault].self, from: try #require(defaults.data(forKey: PlaceDefaults.key)))
        #expect(Set(earlier.keys).isSubset(of: kept.keys))
        #expect(kept["library"] == nil)
        // A place the person cleared stays clear.
        EarlierPlace.readIn(in: defaults)
        #expect(PlaceDefaults.stored(in: defaults).default(for: .library) == nil)
    }

    @Test func filesIsToldOnceAndWhatWasKeptForItStaysReadable() throws {
        let defaults = ThrowawayDefaults.make("PlacesTests.files")
        let left = #"{"files":{}}"#
        defaults.set(left, forKey: StartWith.earlierLastPlaceKey)
        let library = FakeItemLibrary(items: [])
        for _ in 0..<2 {
            let browser = Browser()
            browser.defaults = defaults
            browser.restore(from: nil, in: library, order: ItemOrder())
            #expect(browser.shown == .library)
        }
        #expect(library.notices.waiting.count == 1)
        #expect(defaults.string(forKey: StartWith.earlierLastPlaceKey) == left, "an earlier copy still reads it")

        let window = Data(#"{"place":{"files":{}},"selection":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(Browser.Snapshot.self, from: window)
        #expect(snapshot.place == .library && snapshot.leftFiles)
    }

    @Test func anEarlierWindowKeepsItsPositionWhereOnePlaceStandsForIt() throws {
        func read(_ place: String) throws -> Browser.Snapshot {
            let text = #"{"place":"# + place + #","selection":["n1"],"viewMode":"table","opensItem":true,"scrollOffset":420}"#
            return try JSONDecoder().decode(Browser.Snapshot.self, from: Data(text.utf8))
        }
        let type = try read(#"{"itemType":{"_0":"core.task"}}"#)
        #expect(type.place == .type(TypeID("core.task")) && type.opensItem == true && type.scrollOffset == 420)
        #expect(try read(#"{"allNotes":{}}"#).scrollOffset == 420)
        // Recents listed the Library in another order, and one favorite another list.
        #expect(try read(#"{"recents":{}}"#).scrollOffset == nil)
        #expect(try read(#"{"favoriteItem":{"_0":"n1"}}"#).opensItem == nil)
    }

    @Test func anEarlierWindowOpensItsItemAndFindsAFavoriteWhereItIsListed() throws {
        let kept = FakeItemLibrary.note("Kept", modified: .now)
        let fed = FakeItemLibrary.note("Fed", modified: .now, tier: .feed, isFavorite: true)
        let library = FakeItemLibrary(items: [kept, fed])
        func restored(_ text: String?, start: (place: PlaceView, selecting: ItemID?)? = nil) -> Browser {
            let browser = Browser()
            browser.defaults = ThrowawayDefaults.make("PlacesTests.restore")
            browser.restore(from: text.map { Data($0.utf8) }, in: library, order: ItemOrder(), start: start)
            return browser
        }
        let items = restored(#"{"place":{"allNotes":{}},"selection":["\#(kept.id.rawValue)"],"viewMode":"table","opensItem":true}"#)
        #expect(items.shown == .library && items.selection == [kept.id] && items.isCollectionItemPresented)
        let favorite = restored(#"{"place":{"favoriteItem":{"_0":"\#(fed.id.rawValue)"}},"selection":[]}"#)
        #expect(favorite.shown == .feed && favorite.selection == [fed.id])
        let started = restored(nil, start: (.library, fed.id))
        #expect(started.shown == .feed && started.selection == [fed.id])
    }

    @Test func theFavoritesRowCountsWhatItsFromLists() throws {
        let library = FakeItemLibrary(items: [
            FakeItemLibrary.note("Kept", modified: .now, isFavorite: true),
            FakeItemLibrary.note("Fed", modified: .now, tier: .feed, isFavorite: true),
        ])
        #expect(library.count(in: .favorites, favoritesScope: PlaceDefaults.favoritesScope(in: nil)) == 1)
        let defaults = ThrowawayDefaults.make("PlacesTests.favoritesCount")
        PlaceDefaults.update(in: defaults) { $0.set({ var all = PlaceDefault(); all.scope = .all; return all }(), for: .favorites) }
        let scope = PlaceDefaults.favoritesScope(in: defaults.data(forKey: PlaceDefaults.key))
        #expect(library.count(in: .favorites, favoritesScope: scope) == 2)
    }

    @Test func aPlaceALaterCopyWroteIsWrittenBackAsItWas() throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now), FakeItemLibrary.note("Two", modified: .now)])
        let written = #"{"place":{"place":"later:1","view":"own"},"selection":[]}"#
        let browser = Browser()
        browser.defaults = ThrowawayDefaults.make("PlacesTests.later")
        browser.restore(from: Data(written.utf8), in: library, order: ItemOrder(), start: (.feed, nil))
        #expect(browser.shown == .feed, "it opens where a new window would")
        browser.selection = Set(library.items.map(\.id))
        #expect(browser.snapshot().laterPlace == ["place": "later:1", "view": "own"])
        let back = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(browser.snapshot())) as? [String: Any])
        #expect(back["place"] as? [String: String] == ["place": "later:1", "view": "own"])
        // A view word this copy does not know is kept the same way.
        let view = try JSONDecoder().decode(Browser.Snapshot.self, from: Data(#"{"place":{"place":"feed","view":"pinned"},"selection":[]}"#.utf8))
        #expect(view.place == .feed && view.laterPlace?["view"] == "pinned")
        // Once the person moves, the window is where they are, coming back too.
        browser.showing = .library
        #expect(browser.snapshot().laterPlace == nil)
        browser.showing = .feed
        #expect(browser.snapshot().laterPlace == nil)
        // An order of views keeps a word it does not know.
        var orders = ViewOrders(["library": ["pinned", "own"]])
        #expect(orders.order(in: .library) == [.own])
        orders.set([.favorites, .own], in: .library)
        #expect(orders.places["library"] == ["pinned", "favorites", "own"])
    }

    @Test func startWithIsReadInToKeysOfItsOwnAndKeepsAFavoritesItem() throws {
        let defaults = ThrowawayDefaults.make("PlacesTests.startWith")
        defaults.set(#"{"itemType":{"_0":"core.task"}}"#, forKey: StartWith.earlierKey)
        defaults.set(#"{"favoriteItem":{"_0":"n1"}}"#, forKey: StartWith.earlierLastPlaceKey)
        EarlierPlace.readIn(in: defaults)
        #expect(StartWith.stored(in: defaults) == .place(.type(TypeID("core.task"))))
        #expect(StartWith.leftOff.start(in: defaults)?.selecting == ItemID("n1"))
        StartWith.remember(.feed, in: defaults)
        #expect(defaults.string(forKey: StartWith.earlierKey) == #"{"itemType":{"_0":"core.task"}}"#)
        #expect(defaults.string(forKey: StartWith.earlierLastPlaceKey) == #"{"favoriteItem":{"_0":"n1"}}"#)
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
