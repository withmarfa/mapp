import Foundation
import Testing
@testable import MAPP

struct NoteLibraryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(name: "Work")
    let home = Folder(name: "Home")

    func makeLibrary() -> (NoteLibrary, inbox: Note, filed: Note, pinned: Note, deleted: Note) {
        let inbox = Note(body: "# Inbox note", created: start)
        let filed = Note(body: "# Filed note", created: start, folderID: work.id)
        let pinned = Note(body: "# Pinned note", created: start, folderID: home.id, isPinned: true)
        let deleted = Note(body: "# Deleted note", created: start, folderID: work.id, deleted: start)
        let library = NoteLibrary(notes: [inbox, filed, pinned, deleted], folders: [work, home], now: { start + 60 })
        return (library, inbox, filed, pinned, deleted)
    }

    func undoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    func undoably(_ manager: UndoManager, _ action: () -> Void) {
        manager.beginUndoGrouping()
        action()
        manager.endUndoGrouping()
    }

    // MARK: Reading

    @Test func eachSidebarItemShowsItsNotes() {
        let (library, inbox, filed, pinned, deleted) = makeLibrary()
        #expect(library.notes(in: .inbox) == [inbox])
        #expect(library.notes(in: .allNotes) == [inbox, filed, pinned])
        #expect(library.notes(in: .pinned) == [pinned])
        #expect(library.notes(in: .folder(work.id)) == [filed])
        #expect(library.notes(in: .recentlyDeleted) == [deleted])
        #expect(library.count(in: .allNotes) == 3)
    }

    @Test func searchCoversEveryLiveNoteIgnoringCaseAndAccents() {
        let (library, _, filed, _, _) = makeLibrary()
        library.updateBody(of: filed.id, to: "# Filed note\n\nA proper ragù")
        #expect(library.notes(matching: "RAGU").map(\.id) == [filed.id])
        #expect(library.notes(matching: "note").count == 3)
        #expect(library.notes(matching: "Deleted").isEmpty)
        #expect(library.notes(matching: "   ").isEmpty)
    }

    @Test func sidebarItemsAreNamed() {
        let (library, _, _, _, _) = makeLibrary()
        #expect(library.name(of: .inbox) == "Inbox")
        #expect(library.name(of: .folder(home.id)) == "Home")
        #expect(library.name(of: .recentlyDeleted) == "Recently Deleted")
    }

    // MARK: Notes

    @Test(arguments: [SidebarItem.inbox, .allNotes, .recentlyDeleted])
    func newNotesOutsideAFolderLandInTheInbox(item: SidebarItem) {
        let (library, _, _, _, _) = makeLibrary()
        let note = library.newNote(in: item)
        #expect(library.notes(in: .inbox).contains(note))
        #expect(note.created == start + 60)
    }

    @Test func newNotesShowWhereTheyWereMade() {
        let (library, _, _, _, _) = makeLibrary()
        let inFolder = library.newNote(in: .folder(home.id))
        let fromPinned = library.newNote(in: .pinned)
        #expect(library.notes(in: .folder(home.id)).contains(inFolder))
        #expect(library.notes(in: .pinned).contains(fromPinned))
    }

    @Test func newNoteUndoesAndRedoes() {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        var note: Note?
        undoably(manager) { note = library.newNote(in: .inbox, undoManager: manager) }
        #expect(manager.undoActionName == "New Note")
        manager.undo()
        #expect(library.note(note!.id) == nil)
        manager.redo()
        #expect(library.note(note!.id) == note)
    }

    @Test func editingABodyUpdatesTheModifiedDateOnlyWhenItChanges() {
        let (library, inbox, _, _, _) = makeLibrary()
        library.updateBody(of: inbox.id, to: inbox.body)
        #expect(library.note(inbox.id)?.modified == start)
        library.updateBody(of: inbox.id, to: "# Inbox note, edited")
        #expect(library.note(inbox.id)?.modified == start + 60)
        #expect(library.note(inbox.id)?.title == "Inbox note, edited")
    }

    @Test func deletingMovesToRecentlyDeletedAndUndoes() {
        let (library, inbox, filed, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.delete([inbox.id, filed.id], undoManager: manager) }
        #expect(manager.undoActionName == "Delete Notes")
        #expect(library.notes(in: .recentlyDeleted).count == 3)
        #expect(library.notes(in: .allNotes).count == 1)
        manager.undo()
        #expect(library.note(inbox.id) == inbox)
        #expect(library.note(filed.id) == filed)
        manager.redo()
        #expect(library.note(inbox.id)?.isDeleted == true)
    }

    @Test func recoveringReturnsANoteToWhereItWasAndUndoes() {
        let (library, _, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.recover([deleted.id], undoManager: manager) }
        #expect(library.notes(in: .folder(work.id)).map(\.id).contains(deleted.id))
        #expect(manager.undoActionName == "Recover")
        manager.undo()
        #expect(library.note(deleted.id) == deleted)
        #expect(manager.redoActionName == "Recover")
    }

    @Test func undoingAMoveKeepsTextTypedSince() {
        let (library, inbox, _, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.move([inbox.id], to: work.id, undoManager: manager) }
        library.updateBody(of: inbox.id, to: "# Inbox note\n\nTyped after the move")
        manager.undo()
        #expect(library.note(inbox.id)?.folderID == nil)
        #expect(library.note(inbox.id)?.body == "# Inbox note\n\nTyped after the move")
    }

    @Test func deletingAgainKeepsTheFirstDeletedDate() {
        let (library, _, _, _, deleted) = makeLibrary()
        library.delete([deleted.id])
        #expect(library.note(deleted.id)?.deleted == start)
    }

    @Test func deletingPermanentlyRemovesAndUndoes() {
        let (library, _, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.deletePermanently([deleted.id], undoManager: manager) }
        #expect(library.note(deleted.id) == nil)
        #expect(manager.undoActionName == "Delete Note")
        manager.undo()
        #expect(library.note(deleted.id) == deleted)
    }

    @Test func movingFilesANoteRecoversItAndUndoes() {
        let (library, inbox, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.move([inbox.id, deleted.id], to: home.id, undoManager: manager) }
        #expect(library.notes(in: .folder(home.id)).count == 3)
        #expect(library.notes(in: .inbox).isEmpty)
        #expect(manager.undoActionName == "Move")
        manager.undo()
        #expect(library.note(inbox.id) == inbox)
        #expect(library.note(deleted.id) == deleted)
    }

    @Test func movingToNoFolderReturnsToTheInbox() {
        let (library, _, filed, _, _) = makeLibrary()
        library.move([filed.id], to: nil)
        #expect(library.notes(in: .inbox).map(\.id).contains(filed.id))
    }

    @Test func pinningAndUnpinningUndo() {
        let (library, inbox, _, pinned, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.setPinned([inbox.id], true, undoManager: manager) }
        #expect(manager.undoActionName == "Pin")
        undoably(manager) { library.setPinned([pinned.id], false, undoManager: manager) }
        #expect(manager.undoActionName == "Unpin")
        #expect(library.notes(in: .pinned).map(\.id) == [inbox.id])
        manager.undo()
        manager.undo()
        #expect(library.notes(in: .pinned) == [pinned])
    }

    // MARK: Folders

    @Test func newFoldersGetUniqueNamesAndUndo() {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        let first = library.newFolder()
        var second: Folder?
        undoably(manager) { second = library.newFolder(undoManager: manager) }
        #expect(first.name == "New Folder")
        #expect(second?.name == "New Folder 2")
        #expect(manager.undoActionName == "New Folder")
        manager.undo()
        #expect(library.folders.map(\.name) == ["Work", "Home", "New Folder"])
    }

    @Test func renamingTrimsIgnoresEmptyNamesAndUndoes() {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.rename(work.id, to: "  Office ", undoManager: manager) }
        #expect(library.folder(work.id)?.name == "Office")
        #expect(manager.undoActionName == "Rename Folder")
        library.rename(work.id, to: "   ")
        library.rename(work.id, to: "home")
        #expect(library.folder(work.id)?.name == "Office")
        manager.undo()
        #expect(library.folder(work.id)?.name == "Work")
        manager.redo()
        #expect(library.folder(work.id)?.name == "Office")
    }

    @Test func deletingAFolderDeletesItsNotesAndUndoesAsOneStep() {
        let (library, _, filed, _, deleted) = makeLibrary()
        let manager = undoManager()
        library.deleteFolder(work.id, undoManager: manager)
        #expect(library.folder(work.id) == nil)
        #expect(library.note(filed.id)?.isDeleted == true)
        #expect(library.note(deleted.id)?.deleted == start)
        #expect(manager.undoActionName == "Delete Folder")
        manager.undo()
        #expect(library.folders == [work, home])
        #expect(library.note(filed.id) == filed)
        #expect(library.note(deleted.id) == deleted)
        manager.redo()
        #expect(library.folder(work.id) == nil)
        #expect(library.note(filed.id)?.isDeleted == true)
    }

    @Test func reorderingFoldersUndoes() {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.moveFolders(from: [1], to: 0, undoManager: manager) }
        #expect(library.folders == [home, work])
        #expect(manager.undoActionName == "Move Folder")
        manager.undo()
        #expect(library.folders == [work, home])
    }

    @Test func actionsThatChangeNothingRegisterNoUndo() {
        let (library, inbox, filed, pinned, _) = makeLibrary()
        let manager = undoManager()
        let before = library.notes
        undoably(manager) { library.delete([UUID()], undoManager: manager) }
        undoably(manager) { library.setPinned([pinned.id], true, undoManager: manager) }
        undoably(manager) { library.recover([inbox.id], undoManager: manager) }
        undoably(manager) { library.move([filed.id], to: work.id, undoManager: manager) }
        #expect(library.notes == before)
        #expect(manager.undoActionName == "")
        undoably(manager) { library.delete([inbox.id], undoManager: manager) }
        #expect(manager.undoActionName == "Delete Note")
    }

    // MARK: Sample content

    @Test func sampleContentFillsEverySidebarItem() {
        let library = NoteLibrary.sample()
        #expect(library.folders.count == 4)
        for item in [SidebarItem.inbox, .allNotes, .pinned, .recentlyDeleted] + library.folders.map({ .folder($0.id) }) {
            #expect(library.count(in: item) > 0, "\(item) is empty")
        }
        #expect(library.notes.contains { $0.body.contains("| --- |") })
        #expect(library.notes.contains { $0.body.contains("- [ ]") })
    }
}
