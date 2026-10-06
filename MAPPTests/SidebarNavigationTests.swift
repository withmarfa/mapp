import Foundation
import Testing
@testable import MAPP

struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aFavoriteShortcutSelectsTheActualItemInsteadOfTheFirstFavorite() {
        let first = Note(body: "# First favorite", created: date, isFavorite: true)
        let second = Note(body: "# Second favorite", created: date - 100, isFavorite: true)
        let library = NoteLibrary(notes: [first, second], now: { date })
        let browser = Browser()
        browser.searchText = "First"
        browser.show(.favoriteItem(second.id), in: library, order: NoteOrder())
        #expect(browser.item == .favoriteItem(second.id))
        #expect(browser.selection == [second.id])
        #expect(browser.notes(in: library).map(\.id) == [second.id])
        #expect(browser.searchText.isEmpty)
        #expect(library.name(of: browser.item) == "Second favorite")
        #expect(browser.sections(in: library, order: NoteOrder(), now: date).first?.group != .favorites)
    }

    @Test func aShortcutToAnItemNoLongerFavoriteFallsBackToTheRemainingFavorites() {
        let first = Note(body: "# First favorite", created: date, isFavorite: true)
        let second = Note(body: "# Second favorite", created: date - 100, isFavorite: true)
        let library = NoteLibrary(notes: [first, second], now: { date })
        let browser = Browser()
        browser.show(.favoriteItem(first.id), in: library, order: NoteOrder())
        library.setFavorite([first.id], false)
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection == [second.id])
        #expect(library.notes(in: .favoriteItem(first.id)).isEmpty)
    }

    @Test func aDeletedFavoriteShortcutLeavesAnEmptyFavoritesCollection() {
        let favorite = Note(body: "# Only favorite", created: date, isFavorite: true)
        let library = NoteLibrary(notes: [favorite], now: { date })
        let browser = Browser()
        browser.show(.favoriteItem(favorite.id), in: library, order: NoteOrder())
        library.delete([favorite.id])
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
        #expect(library.notes(in: .favoriteItem(favorite.id)).isEmpty)
    }

    @Test func aFavoriteShortcutRestoresByFilePathAcrossItemIdentities() throws {
        let favorite = Note(body: "# Favorite", path: "Notes/Favorite.md", created: date, isFavorite: true)
        let library = NoteLibrary(notes: [favorite], now: { date })
        let browser = Browser()
        browser.show(.favoriteItem(favorite.id), in: library, order: NoteOrder())
        let data = try JSONEncoder().encode(browser.snapshot(in: library))
        let snapshot = try JSONDecoder().decode(Browser.Snapshot.self, from: data)
        let reloaded = Note(body: "# Favorite", path: "Notes/Favorite.md", created: date, isFavorite: true)
        let restoredLibrary = NoteLibrary(notes: [reloaded], now: { date })
        let restored = Browser()
        restored.restore(snapshot, in: restoredLibrary, order: NoteOrder())
        #expect(restored.item == .favoriteItem(reloaded.id))
        #expect(restored.selection == [reloaded.id])
        #expect(snapshot.sidebarItem == .favoriteItem("Notes/Favorite.md"))
    }

    @Test func aSnapshotSavedBeforeFavoritesFailsToDecodeSoTheWindowOpensAtItsDefault() {
        let saved = Data(#"{"sidebarItem":{"pinned":{}},"selection":[]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Browser.Snapshot.self, from: saved) }
    }

    @Test func restoringAShortcutToAnItemNoLongerFavoriteReturnsToFavorites() {
        let note = Note(body: "# Former favorite", path: "Notes/Former favorite.md", created: date)
        let library = NoteLibrary(notes: [note], now: { date })
        let browser = Browser()
        browser.restore(.init(sidebarItem: .favoriteItem("Notes/Former favorite.md"), selection: ["Notes/Former favorite.md"]), in: library, order: NoteOrder())
        #expect(browser.item == .favorites)
        #expect(browser.selection.isEmpty)
    }

    @Test func aProjectFavoriteAndItsProjectCollectionHaveDistinctDestinations() throws {
        let library = NoteLibrary(notes: [], now: { date })
        let project = try #require(library.createItem(typeID: "aic.project", title: "Field research"))
        let child = try #require(library.createItem(typeID: "aic.ticket.task", title: "Read the findings", parentID: project.id))
        library.setFavorite([project.id], true)
        #expect(SidebarItem.project(project.id) != .favoriteItem(project.id))
        #expect(Set(library.notes(in: .project(project.id)).map(\.id)) == [project.id, child.id])
        #expect(library.notes(in: .favoriteItem(project.id)).map(\.id) == [project.id])
        #expect(library.notes(in: .itemType("aic.project")).map(\.id) == [project.id])
        #expect(library.name(of: .itemType("aic.project")) == "Projects")
    }

    @Test func shortcutAndProjectTitlesUseTheSharedItemProjection() {
        let project = Note(path: "Projects/Folded.md", text: "---\ntype: aic.project\ntitle: >-\n  Folded\n  project\ntags: [favorite]\n---\nProject content.\n", created: date)
        let library = NoteLibrary(notes: [project], now: { date })
        #expect(library.item(project.id)?.title == "Folded project")
        #expect(library.name(of: .favoriteItem(project.id)) == "Folded project")
        #expect(library.name(of: .project(project.id)) == "Folded project")
    }
}
