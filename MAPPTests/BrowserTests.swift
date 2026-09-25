import Foundation
import Testing
@testable import MAPP

struct BrowserTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(name: "Work")

    func makeLibrary() -> (NoteLibrary, older: Note, newer: Note, pinned: Note) {
        let older = Note(body: "# Older", created: start - 120)
        let newer = Note(body: "# Newer", created: start - 60)
        let pinned = Note(body: "# Pinned", created: start - 3600, folderID: work.id, isPinned: true)
        let library = NoteLibrary(notes: [older, newer, pinned], folders: [work], now: { start })
        return (library, older, newer, pinned)
    }

    // MARK: Keeping the selection in the list

    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func selectedNotesStillListedStaySelected() {
        #expect(Browser.selection([a, b], keptFrom: [a, b, c], in: [b, c]) == [b])
    }

    @Test func aSelectionThatLeavesTheListMovesToTheNoteAfterIt() {
        #expect(Browser.selection([b], keptFrom: [a, b, c], in: [a, c]) == [c])
        #expect(Browser.selection([b, c], keptFrom: [a, b, c, d], in: [a, d]) == [d])
    }

    @Test func withNothingAfterItTheSelectionMovesToTheNoteBefore() {
        #expect(Browser.selection([c], keptFrom: [a, b, c], in: [a, b]) == [b])
    }

    @Test func anEmptiedListLeavesNothingSelected() {
        #expect(Browser.selection([a], keptFrom: [a], in: []).isEmpty)
        #expect(Browser.selection([], keptFrom: [a], in: [a]).isEmpty)
    }

    // MARK: Showing and making

    @Test func showingAnItemClearsTheSearchAndSelectsItsTopRow() {
        let (library, _, newer, pinned) = makeLibrary()
        let browser = Browser()
        browser.searchText = "Older"
        browser.show(.allNotes, in: library, sort: .dateEdited)
        #expect(browser.searchText.isEmpty)
        #expect(browser.selection == [pinned.id])
        browser.show(.inbox, in: library, sort: .dateEdited)
        #expect(browser.selection == [newer.id])
    }

    @Test func aNewNoteFromRecentlyDeletedGoesToTheInboxAndStaysSelected() {
        let (library, _, _, _) = makeLibrary()
        let browser = Browser()
        browser.show(.recentlyDeleted, in: library, sort: .dateEdited)
        browser.searchText = "Pinned"
        browser.newNote(in: library, undoManager: nil)
        #expect(browser.item == .inbox)
        #expect(!browser.isSearching)
        #expect(browser.selectedNotes(in: library).map(\.body) == [""])
    }

    @Test func aWhitespaceSearchIsNoSearch() {
        let browser = Browser()
        browser.searchText = "  \n"
        #expect(!browser.isSearching)
    }

    @Test func aRemovedFolderGivesWayToAllNotes() {
        let (library, _, _, pinned) = makeLibrary()
        let browser = Browser()
        browser.newFolder(in: library, sort: .dateEdited, undoManager: nil)
        guard case .folder(let id) = browser.item else { return #expect(Bool(false)) }
        #expect(browser.renamingFolder == id)
        library.deleteFolder(id)
        browser.folderRemoved(in: library, sort: .dateEdited)
        #expect(browser.item == .allNotes)
        #expect(browser.renamingFolder == nil)
        #expect(browser.selection == [pinned.id])
    }

    @Test func pinnedNotesLeadOnlyWherePinsMeanSomething() {
        let (library, _, newer, _) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, sort: .dateEdited)
        #expect(browser.sections(in: library, sort: .dateEdited, now: start).first?.group == .pinned)
        browser.searchText = "e"
        #expect(browser.sections(in: library, sort: .dateEdited, now: start).first?.notes.first?.id == newer.id)
    }
}
