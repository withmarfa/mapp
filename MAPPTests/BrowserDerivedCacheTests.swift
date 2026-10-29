import Foundation
import Testing
@testable import MAPP

/// What the window works out from a place's items is kept until something it depends on changes, and a hit lists no
/// items (`Browser.sections`, `tableContent`, `availableViewModes`), so a click costs nothing it has done before.
@MainActor
struct BrowserDerivedCacheTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func library() -> FakeItemLibrary {
        FakeItemLibrary(items: (1...5).map { FakeItemLibrary.note("Note \($0)", modified: date) }, now: date)
    }

    @Test func theSectionsOfAnUnchangedPlaceListNothingTheSecondTime() {
        let library = library()
        let browser = Browser()
        let first = browser.sections(in: library, order: NoteOrder(), now: date)
        let reads = library.placeReads
        let second = browser.sections(in: library, order: NoteOrder(), now: date)
        #expect(library.placeReads == reads)
        #expect(second.map { $0.items.map(\.id) } == first.map { $0.items.map(\.id) })
    }

    @Test func anEditToAnItemMakesTheSectionsAgain() {
        let library = library()
        let browser = Browser()
        _ = browser.sections(in: library, order: NoteOrder(), now: date)
        library.items[0].title = "Renamed"
        let titles = browser.sections(in: library, order: NoteOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(titles.contains("Renamed"))
    }

    @Test func theTableOfAnUnchangedPlaceIsTheSameAndListsNothing() {
        let library = library()
        let browser = Browser()
        let first = browser.tableContent(in: library)
        let reads = library.placeReads
        #expect(browser.tableContent(in: library) === first)
        #expect(library.placeReads == reads)
    }

    @Test func aSearchKeepsKeyingOnWhatItFinds() {
        let library = library()
        let browser = Browser()
        browser.searchText = "Note 1"
        let one = browser.sections(in: library, order: NoteOrder(), now: date).flatMap { $0.items.map(\.title) }
        browser.searchText = "Note 2"
        let two = browser.sections(in: library, order: NoteOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(one == ["Note 1"])
        #expect(two == ["Note 2"])
    }

    @Test func aSavedViewKeepsKeyingOnTheItemsItListsWhichArriveWithoutAChangeToTheLibrary() {
        let library = library()
        let view = LibraryView(id: .mint(), title: "Some")
        library.views = [view]
        let browser = Browser()
        browser.show(.view(view.id), in: library, order: NoteOrder())
        #expect(browser.sections(in: library, order: NoteOrder(), now: date).isEmpty)
        library.viewMembers[view.id] = [library.items[0].id]
        let titles = browser.sections(in: library, order: NoteOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(titles == ["Note 1"])
    }

    @Test func theLayoutsOfAPlaceAreKeptUntilTheLibraryChangesWhatItHolds() {
        let library = library()
        let browser = Browser()
        let first = browser.availableViewModes(in: library)
        let reads = library.placeReads
        #expect(browser.availableViewModes(in: library) == first)
        #expect(library.placeReads == reads)
        library.items.append(FakeItemLibrary.note("Another", modified: date))
        _ = browser.availableViewModes(in: library)
        #expect(library.placeReads > reads)
    }
}

/// Where the window goes when the place it shows is gone, worked out without moving it, so a view can watch the
/// answer (`Browser.placeFallback`) instead of a list of the library's items.
@MainActor
struct PlaceFallbackTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aPlaceThatStandsHasNoFallback() {
        let note = FakeItemLibrary.note("Note", modified: date, isFavorite: true)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        #expect(browser.placeFallback(in: library) == nil)
        browser.sidebarItem = .itemType("core.note")
        #expect(browser.placeFallback(in: library) == nil)
        browser.sidebarItem = .favoriteItem(note.id)
        #expect(browser.placeFallback(in: library) == nil)
    }

    @Test func aTypeWithNoItemsLeftFallsBackToAllItems() {
        let note = FakeItemLibrary.note("Note", modified: date)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.sidebarItem = .itemType("core.note")
        library.items = []
        #expect(browser.placeFallback(in: library) == .allNotes)
        #expect(browser.sidebarItem == .itemType("core.note"))
    }

    @Test func aCollectionNoLongerActiveFallsBackToAllItems() {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection], now: date)
        let browser = Browser()
        browser.sidebarItem = .collection(collection.id)
        #expect(browser.placeFallback(in: library) == nil)
        library.items[0].state = .trashed
        #expect(browser.placeFallback(in: library) == .allNotes)
    }

    @Test func aFavoriteThatIsNoLongerOneFallsBackToFavorites() {
        let note = FakeItemLibrary.note("Note", modified: date, isFavorite: true)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.sidebarItem = .favoriteItem(note.id)
        library.items[0].tags = []
        #expect(browser.placeFallback(in: library) == .favorites)
    }

    @Test func aDeletedViewFallsBackToAllItems() {
        let library = FakeItemLibrary(items: [], now: date)
        let view = LibraryView(id: .mint(), title: "Some")
        library.views = [view]
        let browser = Browser()
        browser.sidebarItem = .view(view.id)
        #expect(browser.placeFallback(in: library) == nil)
        library.views = []
        #expect(browser.placeFallback(in: library) == .allNotes)
    }

    @Test func nothingFallsBackBeforeTheLibraryIsRead() {
        let library = FakeItemLibrary(items: [], now: date)
        library.isLoaded = false
        let browser = Browser()
        browser.sidebarItem = .itemType("core.note")
        #expect(browser.placeFallback(in: library) == nil)
    }

    @Test func aWatcherIsToldWhenALibraryChangeRemovesThePlace() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let browser = Browser()
        browser.sidebarItem = .itemType(LibraryFixture.entity.rawValue)
        let told = Told()
        withObservationTracking { _ = browser.placeFallback(in: library) } onChange: { told.set() }
        #expect(!told.isSet)
        source.send(.removed([LibraryFixture.en1]))
        try #require(await eventually { library.isGone(LibraryFixture.en1) })
        #expect(told.isSet)
        #expect(browser.placeFallback(in: library) == .allNotes)
    }

    @Test func movingOnFromAGonePlaceShowsAllItems() {
        let library = FakeItemLibrary(items: [], now: date)
        let browser = Browser()
        browser.sidebarItem = .itemType("core.note")
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
    }
}

private nonisolated final class Told: @unchecked Sendable {
    private(set) var isSet = false
    func set() { isSet = true }
}
