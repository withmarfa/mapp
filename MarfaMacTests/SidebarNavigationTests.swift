import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit)
struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aSnapshotWithAnyOtherUnreadablePlaceFailsToDecode() {
        let saved = Data(#"{"place":{"pinned":{}},"selection":[],"opensItem":true,"scrollOffset":10}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }

    @Test func aStoredSidebarLayoutNamingRecentlyDeletedStillReadsAndPlans() throws {
        #expect(SidebarPlace(key: "recentlyDeleted") == nil)
        let json = #"{"hidden":["recentlyDeleted","inbox"],"order":["recentlyDeleted","all"],"collapsed":[]}"#
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(json.utf8))
        let plan = SidebarPlan(FakeItemLibrary(items: []), layout: layout)
        #expect(!plan.isShown(.inbox))
        #expect(plan.destinations.contains(.all))
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

    @Test func aSnapshotWithNoPlaceFailsToDecodeSoTheWindowOpensAtItsDefault() {
        let saved = Data(#"{"sidebarItem":{"pinned":{}},"selection":[]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
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
