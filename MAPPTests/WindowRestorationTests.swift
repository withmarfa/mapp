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

    @Test func aSelectionOfEverythingKeepsOnlyUpToTheLimit() {
        let notes = items(3_000)
        let browser = Browser()
        browser.selection = Set(notes.map(\.id))
        let kept = browser.snapshot().selection
        #expect(kept.count == Browser.restoredSelectionLimit)
        #expect(Set(kept).isSubset(of: browser.selection))
        #expect(kept == kept.sorted { $0.rawValue < $1.rawValue })
    }

    @Test func aRestoredWindowFromABoundedSelectionStillSelectsItsItems() {
        let notes = items(1_000)
        let library = FakeItemLibrary(items: notes)
        let saved = Browser()
        saved.show(.allNotes, in: library, order: NoteOrder())
        saved.selection = Set(notes.map(\.id))
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: NoteOrder())
        #expect(restored.selection.count == Browser.restoredSelectionLimit)
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
