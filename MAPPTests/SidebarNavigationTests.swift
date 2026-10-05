import Foundation
import Testing
@testable import MAPP

struct SidebarNavigationTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aPinnedShortcutSelectsTheActualItemInsteadOfTheFirstPin() {
        let first = Note(body: "# First pin", created: date, isPinned: true)
        let second = Note(body: "# Second pin", created: date - 100, isPinned: true)
        let library = NoteLibrary(notes: [first, second], now: { date })
        let browser = Browser()
        browser.searchText = "First"
        browser.show(.pinnedItem(second.id), in: library, order: NoteOrder())
        #expect(browser.item == .pinnedItem(second.id))
        #expect(browser.selection == [second.id])
        #expect(browser.notes(in: library).map(\.id) == [second.id])
        #expect(browser.searchText.isEmpty)
        #expect(library.name(of: browser.item) == "Second pin")
        #expect(browser.sections(in: library, order: NoteOrder(), now: date).first?.group != .pinned)
    }

    @Test func anUnpinnedShortcutFallsBackToTheRemainingPins() {
        let first = Note(body: "# First pin", created: date, isPinned: true)
        let second = Note(body: "# Second pin", created: date - 100, isPinned: true)
        let library = NoteLibrary(notes: [first, second], now: { date })
        let browser = Browser()
        browser.show(.pinnedItem(first.id), in: library, order: NoteOrder())
        library.setPinned([first.id], false)
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .pinned)
        #expect(browser.selection == [second.id])
        #expect(library.notes(in: .pinnedItem(first.id)).isEmpty)
    }

    @Test func aDeletedPinnedShortcutLeavesAnEmptyPinnedCollection() {
        let pin = Note(body: "# Only pin", created: date, isPinned: true)
        let library = NoteLibrary(notes: [pin], now: { date })
        let browser = Browser()
        browser.show(.pinnedItem(pin.id), in: library, order: NoteOrder())
        library.delete([pin.id])
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .pinned)
        #expect(browser.selection.isEmpty)
        #expect(library.notes(in: .pinnedItem(pin.id)).isEmpty)
    }

    @Test func aPinnedShortcutRestoresByFilePathAcrossItemIdentities() throws {
        let pin = Note(body: "# Pin", path: "Notes/Pin.md", created: date, isPinned: true)
        let library = NoteLibrary(notes: [pin], now: { date })
        let browser = Browser()
        browser.show(.pinnedItem(pin.id), in: library, order: NoteOrder())
        let data = try JSONEncoder().encode(browser.snapshot(in: library))
        let snapshot = try JSONDecoder().decode(Browser.Snapshot.self, from: data)
        let reloaded = Note(body: "# Pin", path: "Notes/Pin.md", created: date, isPinned: true)
        let restoredLibrary = NoteLibrary(notes: [reloaded], now: { date })
        let restored = Browser()
        restored.restore(snapshot, in: restoredLibrary, order: NoteOrder())
        #expect(restored.item == .pinnedItem(reloaded.id))
        #expect(restored.selection == [reloaded.id])
        #expect(snapshot.sidebarItem == .pinnedItem("Notes/Pin.md"))
    }

    @Test func restoringAnUnpinnedShortcutReturnsToThePinnedCollection() {
        let note = Note(body: "# Former pin", path: "Notes/Former pin.md", created: date)
        let library = NoteLibrary(notes: [note], now: { date })
        let browser = Browser()
        browser.restore(.init(sidebarItem: .pinnedItem("Notes/Former pin.md"), selection: ["Notes/Former pin.md"]), in: library, order: NoteOrder())
        #expect(browser.item == .pinned)
        #expect(browser.selection.isEmpty)
    }

    @Test func aProjectPinAndItsProjectCollectionHaveDistinctDestinations() throws {
        let library = NoteLibrary(notes: [], now: { date })
        let project = try #require(library.createItem(typeID: "aic.project", title: "Field research"))
        let child = try #require(library.createItem(typeID: "aic.ticket.task", title: "Read the findings", parentID: project.id))
        library.setPinned([project.id], true)
        #expect(SidebarItem.project(project.id) != .pinnedItem(project.id))
        #expect(Set(library.notes(in: .project(project.id)).map(\.id)) == [project.id, child.id])
        #expect(library.notes(in: .pinnedItem(project.id)).map(\.id) == [project.id])
        #expect(library.notes(in: .itemType("aic.project")).map(\.id) == [project.id])
        #expect(library.name(of: .itemType("aic.project")) == "Projects")
    }

    @Test func shortcutAndProjectTitlesUseTheSharedItemProjection() {
        let project = Note(path: "Projects/Folded.md", text: "---\ntype: aic.project\ntitle: >-\n  Folded\n  project\npinned: true\n---\nProject content.\n", created: date)
        let library = NoteLibrary(notes: [project], now: { date })
        #expect(library.item(project.id)?.title == "Folded project")
        #expect(library.name(of: .pinnedItem(project.id)) == "Folded project")
        #expect(library.name(of: .project(project.id)) == "Folded project")
    }
}
