import Foundation
import Testing
@testable import MarfaMac

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
        saved.show(.feed, in: library, order: ItemOrder())
        saved.selection = Set(notes.map(\.id))
        let restored = Browser()
        restored.restore(saved.snapshot(), in: library, order: ItemOrder())
        #expect(restored.selection.count == 1)
        #expect(restored.selection.isSubset(of: saved.selection))
    }
}

struct WindowBringBackTests {
    @Test func anUnencodableSnapshotKeepsTheStoredWindow() throws {
        let browser = Browser()
        browser.listMemory.scrollOffset = 420
        var stored: Data?
        browser.saveSnapshot { stored = $0 }
        let previous = try #require(stored)

        browser.listMemory.scrollOffset = .nan
        browser.saveSnapshot { stored = $0 }

        #expect(stored == previous)
    }

    @Test func aRestoredPositionSurvivesRestoringThePlaceAndLayoutItBelongsTo() throws {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.showing = .favorites
        saved.viewMode = .table
        saved.listMemory.scrollOffset = 420
        let data = try JSONEncoder().encode(saved.snapshot())
        let back = Browser()
        back.restore(from: data, in: library, order: ItemOrder())
        #expect(back.listMemory.scrollOffset == 420)
    }

    @Test func aWindowKeptBeforeTheseThingsWereKeptStillOpens() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        var snapshot = Browser.Snapshot(place: .library, selection: [newer.id])
        snapshot.opensItem = nil
        let data = try JSONEncoder().encode(snapshot)
        let back = Browser()
        back.restore(from: data, in: library, order: ItemOrder())
        #expect(back.selection == [newer.id])
        #expect(back.listMemory.scrollOffset == nil)
    }
}

struct FileWindowEditorTests {
    @Test func aFileWindowMakesNoEditor() {
        let slot = EditorSlot()
        var made = 0
        let editor = ItemWindow.pageEditor(for: .file, in: slot) {
            made += 1
            return EditorController(library: FakeItemLibrary())
        }
        #expect(editor == nil)
        #expect(made == 0)
        #expect(slot.made == nil)
    }

    @Test func anItemWindowMakesItsEditorOnce() {
        let slot = EditorSlot()
        var made = 0
        func make() -> EditorController {
            made += 1
            return EditorController(library: FakeItemLibrary())
        }
        let first = ItemWindow.pageEditor(for: .text, in: slot, make: make)
        let second = ItemWindow.pageEditor(for: .text, in: slot, make: make)
        #expect(first != nil && first === second)
        #expect(made == 1)
    }
}
