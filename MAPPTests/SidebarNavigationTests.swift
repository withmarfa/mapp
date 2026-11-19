import Foundation
import Testing
@testable import MAPP

@Suite(.hangLimit)
struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aWindowKeptOnRecentlyDeletedRestoresOnItems() throws {
        // Recently Deleted was a place of the sidebar once; a window saved then names it, and the rest of the window is kept.
        let json = #"{"place":{"recentlyDeleted":{}},"selection":["note-1"],"viewMode":"gallery"}"#
        let snapshot = try JSONDecoder().decode(Browser.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.place == .allItems)
        let note = FakeItemLibrary.note("Text", modified: date, id: ItemID("note-1"))
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.restore(snapshot, in: library, order: ItemOrder())
        #expect(browser.item == .allItems)
        #expect(browser.viewMode == .gallery)
        #expect(browser.selection == [note.id])
        #expect(!browser.showsSettings)
    }

    @Test func aStoredSidebarLayoutNamingRecentlyDeletedStillReadsAndPlans() throws {
        #expect(SidebarPlace(key: "recentlyDeleted") == nil)
        let json = #"{"hidden":["recentlyDeleted","inbox"],"order":["recentlyDeleted","all"],"collapsed":[]}"#
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(json.utf8))
        let plan = SidebarPlan(FakeItemLibrary(items: []), layout: layout)
        #expect(!plan.isShown(.inbox))
        #expect(plan.destinations.contains(.all))
    }

    @Test func sourceIndexesPreserveExactNamesAndExcludeDeletedItems() async throws {
        var first = FakeItemLibrary.note("First", modified: date)
        first.source = "reader"
        var second = FakeItemLibrary.note("Second", modified: date)
        second.source = "Reader"
        var deleted = FakeItemLibrary.note("Deleted", modified: date, state: .trashed)
        deleted.source = "reader"
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [first, second, deleted], catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        #expect(Set(library.sourceCounts.map(\.name)) == ["reader", "Reader"])
        #expect(library.sourceCounts.allSatisfy { $0.count == 1 })
        #expect(library.items(in: .source("reader")).map(\.id) == [first.id])
        #expect(library.count(in: .source("reader")) == 1)
        let browser = Browser()
        browser.show(.sources, in: library, order: ItemOrder())
        #expect(browser.showsSidebarIndex)
        #expect(browser.selection.isEmpty)
    }

    @Test func aFavoriteShortcutSelectsTheActualItemInsteadOfTheFirstFavorite() {
        let first = FakeItemLibrary.note("First favorite", modified: date, isFavorite: true)
        let second = FakeItemLibrary.note("Second favorite", modified: date - 100, isFavorite: true)
        let library = FakeItemLibrary(items: [first, second], now: date)
        let browser = Browser()
        browser.searchText = "First"
        browser.show(.favoriteItem(second.id), in: library, order: ItemOrder())
        #expect(browser.item == .favoriteItem(second.id))
        #expect(browser.selection == [second.id])
        #expect(browser.items(in: library).map(\.id) == [second.id])
        #expect(browser.searchText.isEmpty)
        #expect(library.name(of: browser.item) == "Second favorite")
        #expect(browser.sections(in: library, order: ItemOrder(), now: date).first?.group != .favorites)
    }

    @Test func aShortcutToAnItemNoLongerFavoriteFallsBackToTheRemainingFavorites() {
        let first = FakeItemLibrary.note("First favorite", modified: date, isFavorite: true)
        let second = FakeItemLibrary.note("Second favorite", modified: date - 100, isFavorite: true)
        let library = FakeItemLibrary(items: [first, second], now: date)
        let browser = Browser()
        browser.show(.favoriteItem(first.id), in: library, order: ItemOrder())
        library.setFavorite([first.id], false, undoManager: nil)
        browser.placeRemoved(in: library, order: ItemOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection == [second.id])
        #expect(library.items(in: .favoriteItem(first.id)).isEmpty)
    }

    @Test func aDeletedFavoriteShortcutLeavesAnEmptyFavoritesCollection() {
        let favorite = FakeItemLibrary.note("Only favorite", modified: date, isFavorite: true)
        let library = FakeItemLibrary(items: [favorite], now: date)
        let browser = Browser()
        browser.show(.favoriteItem(favorite.id), in: library, order: ItemOrder())
        library.delete([favorite.id], undoManager: nil)
        browser.placeRemoved(in: library, order: ItemOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
        #expect(library.items(in: .favoriteItem(favorite.id)).isEmpty)
    }

    @Test func aSnapshotWithNoPlaceFailsToDecodeSoTheWindowOpensAtItsDefault() {
        let saved = Data(#"{"sidebarItem":{"pinned":{}},"selection":[]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }

    @Test func restoringAShortcutToAnItemNoLongerFavoriteReturnsToFavorites() {
        let note = FakeItemLibrary.note("Former favorite", modified: date)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.restore(.init(place: .favoriteItem(note.id), selection: [note.id]), in: library, order: ItemOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
    }

    @Test func aFavoriteCollectionAndTheCollectionHaveDistinctDestinations() throws {
        let library = FakeItemLibrary(now: date)
        let collection = try #require(library.createItem(typeID: FakeItemLibrary.collectionType.rawValue, title: "Field research", body: "", parentID: nil, in: .allItems, undoManager: nil).flatMap { library.item($0) })
        let member = try #require(library.createItem(typeID: "core.task", title: "Read the findings", body: "", parentID: nil, in: .allItems, undoManager: nil))
        #expect(library.addToCollection([member], collection.id, undoManager: nil))
        library.setFavorite([collection.id], true, undoManager: nil)
        #expect(SidebarItem.collection(collection.id) != .favoriteItem(collection.id))
        #expect(library.items(in: .collection(collection.id)).map(\.id) == [member])
        #expect(library.items(in: .favoriteItem(collection.id)).map(\.id) == [collection.id])
        #expect(library.items(in: .itemType(FakeItemLibrary.collectionType.rawValue)).map(\.id) == [collection.id])
        #expect(library.name(of: .itemType(FakeItemLibrary.collectionType.rawValue)) == "Collection")
    }
}
