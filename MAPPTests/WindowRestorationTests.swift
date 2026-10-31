import Foundation
import Testing
@testable import MAPP

struct WindowRestorationTests {
    private func items(_ count: Int) -> [Item] {
        (0..<count).map { FakeItemLibrary.note("Note \($0)", modified: .now) }
    }

    @Test func aSmallSelectionIsKeptWhole() {
        let notes = items(5)
        let browser = Browser()
        browser.selection = Set(notes.map(\.id))
        #expect(Set(browser.snapshot().selection) == browser.selection)
    }

    @Test func aSelectionAtTheLimitIsKeptWhole() {
        let notes = items(Browser.restoredSelectionLimit)
        let browser = Browser()
        browser.selection = Set(notes.map(\.id))
        let kept = browser.snapshot().selection
        #expect(Set(kept) == browser.selection)
        #expect(kept == kept.sorted { $0.rawValue < $1.rawValue })
    }

    @Test func aSelectionPastTheLimitIsKeptAsNone() {
        let browser = Browser()
        browser.selection = Set(items(3_000).map(\.id))
        #expect(browser.snapshot().selection.isEmpty)
    }

    @Test func aRestoredWindowFromASelectionPastTheLimitOpensAtItsFirstRows() {
        let notes = items(1_000)
        let library = FakeItemLibrary(items: notes)
        let saved = Browser()
        saved.show(.allNotes, in: library, order: NoteOrder())
        saved.selection = Set(notes.map(\.id))
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: NoteOrder())
        #expect(restored.selection.count == 1)
        #expect(restored.selection.isSubset(of: saved.selection))
    }
}

struct WindowBringBackTests {
    private func restored(_ saved: Browser, in library: FakeItemLibrary) throws -> Browser {
        let data = try JSONEncoder().encode(saved.snapshot())
        let restored = Browser()
        restored.restore(from: data, in: library, order: NoteOrder())
        return restored
    }

    @Test func anItemOpenFromTheGalleryComesBackOpen() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.viewMode = .gallery
        saved.selection = [newer.id]
        saved.openCollectionSelection()
        #expect(!saved.showsCollection)
        let back = try restored(saved, in: library)
        #expect(!back.showsCollection, "the item is open, not the grid behind it")
        #expect(back.selection == [newer.id])
    }

    @Test func aGridThatWasShowingComesBackShowingItself() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.viewMode = .table
        saved.selection = [newer.id]
        #expect(try restored(saved, in: library).showsCollection)
    }

    @Test func anOpenItemThatIsGoneIsNotOpened() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.viewMode = .gallery
        saved.selection = [newer.id]
        saved.openCollectionSelection()
        library.items.removeAll { $0.id == newer.id }
        #expect(try restored(saved, in: library).showsCollection, "another item is chosen in its stead")
    }

    @Test func theScrollPositionIsKeptAndTheListShownIsToldToScroll() throws {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.listMemory.scrollOffset = 640
        let data = try JSONEncoder().encode(saved.snapshot())
        let back = Browser()
        var rearmed = 0
        back.listMemory.rearm = { rearmed += 1 }
        back.restore(from: data, in: library, order: NoteOrder())
        #expect(back.listMemory.scrollOffset == 640)
        #expect(rearmed == 1)
    }

    @Test func theScrollPositionIsForgottenWhenThePlaceOrTheLayoutChanges() {
        let browser = Browser()
        browser.listMemory.scrollOffset = 300
        browser.sidebarItem = .allNotes
        browser.viewMode = .list
        #expect(browser.listMemory.scrollOffset == 300, "setting what is already set keeps the position")
        browser.sidebarItem = .favorites
        #expect(browser.listMemory.scrollOffset == nil)
        browser.listMemory.scrollOffset = 300
        browser.viewMode = .table
        #expect(browser.listMemory.scrollOffset == nil)
    }

    @Test func aRestoredPositionSurvivesRestoringThePlaceAndLayoutItBelongsTo() throws {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.sidebarItem = .favorites
        saved.viewMode = .table
        saved.listMemory.scrollOffset = 420
        let data = try JSONEncoder().encode(saved.snapshot())
        let back = Browser()
        back.restore(from: data, in: library, order: NoteOrder())
        #expect(back.listMemory.scrollOffset == 420)
    }

    @Test func aWindowKeptBeforeTheseThingsWereKeptStillOpens() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        var snapshot = Browser.Snapshot(place: .allNotes, selection: [newer.id])
        snapshot.opensItem = nil
        let data = try JSONEncoder().encode(snapshot)
        let back = Browser()
        back.restore(from: data, in: library, order: NoteOrder())
        #expect(back.selection == [newer.id])
        #expect(back.listMemory.scrollOffset == nil)
    }
}

struct FileWindowEditorTests {
    @Test func aFileWindowMakesNoEditor() {
        let slot = EditorSlot()
        var made = 0
        let editor = NoteWindow.pageEditor(for: .file, in: slot) {
            made += 1
            return EditorController(library: FakeItemLibrary())
        }
        #expect(editor == nil)
        #expect(made == 0)
        #expect(slot.made == nil)
    }

    @Test func aNoteWindowMakesItsEditorOnce() {
        let slot = EditorSlot()
        var made = 0
        func make() -> EditorController {
            made += 1
            return EditorController(library: FakeItemLibrary())
        }
        let first = NoteWindow.pageEditor(for: .text, in: slot, make: make)
        let second = NoteWindow.pageEditor(for: .text, in: slot, make: make)
        #expect(first != nil && first === second)
        #expect(made == 1)
    }
}
