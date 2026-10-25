import Foundation
import Testing
@testable import MAPP

struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func recentlyDeletedRestoresAsAnOrdinaryWorkspace() {
        let note = FakeItemLibrary.note("Deleted text", modified: date, state: .trashed)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.restore(.init(place: .recentlyDeleted, selection: [note.id], viewMode: .gallery), in: library, order: NoteOrder())
        #expect(browser.item == .recentlyDeleted)
        #expect(browser.viewMode == .gallery)
        #expect(browser.selection == [note.id])
        #expect(!browser.showsSettings)
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
        browser.show(.sources, in: library, order: NoteOrder())
        #expect(browser.showsSidebarIndex)
        #expect(browser.selection.isEmpty)
    }

    @Test func aFavoriteShortcutSelectsTheActualItemInsteadOfTheFirstFavorite() {
        let first = FakeItemLibrary.note("First favorite", modified: date, isFavorite: true)
        let second = FakeItemLibrary.note("Second favorite", modified: date - 100, isFavorite: true)
        let library = FakeItemLibrary(items: [first, second], now: date)
        let browser = Browser()
        browser.searchText = "First"
        browser.show(.favoriteItem(second.id), in: library, order: NoteOrder())
        #expect(browser.item == .favoriteItem(second.id))
        #expect(browser.selection == [second.id])
        #expect(browser.items(in: library).map(\.id) == [second.id])
        #expect(browser.searchText.isEmpty)
        #expect(library.name(of: browser.item) == "Second favorite")
        #expect(browser.sections(in: library, order: NoteOrder(), now: date).first?.group != .favorites)
    }

    @Test func aShortcutToAnItemNoLongerFavoriteFallsBackToTheRemainingFavorites() {
        let first = FakeItemLibrary.note("First favorite", modified: date, isFavorite: true)
        let second = FakeItemLibrary.note("Second favorite", modified: date - 100, isFavorite: true)
        let library = FakeItemLibrary(items: [first, second], now: date)
        let browser = Browser()
        browser.show(.favoriteItem(first.id), in: library, order: NoteOrder())
        library.setFavorite([first.id], false, undoManager: nil)
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection == [second.id])
        #expect(library.items(in: .favoriteItem(first.id)).isEmpty)
    }

    @Test func aDeletedFavoriteShortcutLeavesAnEmptyFavoritesCollection() {
        let favorite = FakeItemLibrary.note("Only favorite", modified: date, isFavorite: true)
        let library = FakeItemLibrary(items: [favorite], now: date)
        let browser = Browser()
        browser.show(.favoriteItem(favorite.id), in: library, order: NoteOrder())
        library.delete([favorite.id], undoManager: nil)
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
        #expect(library.items(in: .favoriteItem(favorite.id)).isEmpty)
    }

    @Test func aSnapshotSavedBeforeFavoritesFailsToDecodeSoTheWindowOpensAtItsDefault() {
        let saved = Data(#"{"sidebarItem":{"pinned":{}},"selection":[]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }

    @Test func restoringAShortcutToAnItemNoLongerFavoriteReturnsToFavorites() {
        let note = FakeItemLibrary.note("Former favorite", modified: date)
        let library = FakeItemLibrary(items: [note], now: date)
        let browser = Browser()
        browser.restore(.init(place: .favoriteItem(note.id), selection: [note.id]), in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
    }

    @Test func aProjectFavoriteAndItsProjectCollectionHaveDistinctDestinations() throws {
        let library = FakeItemLibrary(now: date)
        let project = try #require(library.createItem(typeID: "test.project", title: "Field research", body: "", parentID: nil, in: .allNotes, undoManager: nil).flatMap { library.item($0) })
        let child = try #require(library.createItem(typeID: "core.task", title: "Read the findings", body: "", parentID: project.id, in: .allNotes, undoManager: nil).flatMap { library.item($0) })
        library.setFavorite([project.id], true, undoManager: nil)
        #expect(SidebarItem.collection(project.id) != .favoriteItem(project.id))
        #expect(library.items(in: .collection(project.id)).map(\.id) == [child.id])
        #expect(library.items(in: .favoriteItem(project.id)).map(\.id) == [project.id])
        #expect(library.items(in: .itemType("test.project")).map(\.id) == [project.id])
        #expect(library.name(of: .itemType("test.project")) == "Project")
    }
}
