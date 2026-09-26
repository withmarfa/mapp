import Foundation
import Testing
@testable import MAPP

struct NoteLibraryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(name: "Work")
    let home = Folder(name: "Home")

    let store = RecordingStore()

    func makeLibrary() -> (NoteLibrary, inbox: Note, filed: Note, pinned: Note, deleted: Note) {
        let inbox = Note(body: "# Inbox note", created: start)
        let filed = Note(body: "# Filed note", path: "Work/Filed note.md", created: start, folderID: work.id)
        let pinned = Note(body: "# Pinned note", path: "Home/Pinned note.md", created: start, folderID: home.id, isPinned: true)
        let deleted = Note(body: "# Deleted note", path: "Work/Deleted note.md", created: start, folderID: work.id, deleted: start)
        let library = NoteLibrary(
            notes: [inbox, filed, pinned, deleted], folders: [work, home], store: store, now: { start + 60 }
        )
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
        #expect(library.note(inbox.id)?.title == "Inbox note", "a written note is titled by its file, as Marfa reads it")
        #expect(store.changes == [.write(path: "Inbox note.md", text: "# Inbox note, edited")])
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
        #expect(store.changes == [.restore(id: deleted.binID!, path: "Work/Deleted note.md")])
        #expect(manager.undoActionName == "Recover")
        manager.undo()
        #expect(library.note(deleted.id)?.isDeleted == true)
        #expect(library.note(deleted.id)?.folderID == work.id)
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

    @Test func deletingPermanentlyErasesForGoodWithoutUndo() {
        let (library, inbox, _, _, deleted) = makeLibrary()
        library.notesToPurge = [deleted.id]
        library.deletePermanently([deleted.id, inbox.id])
        #expect(library.note(deleted.id) == nil)
        #expect(library.note(inbox.id) != nil, "a note not in Recently Deleted is not erased")
        #expect(library.notesToPurge.isEmpty)
        #expect(store.changes == [.purge(id: deleted.binID!)])
    }

    @Test func movingFilesANoteRecoversItAndUndoes() {
        let (library, inbox, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.move([inbox.id, deleted.id], to: home.id, undoManager: manager) }
        #expect(library.notes(in: .folder(home.id)).count == 3)
        #expect(library.notes(in: .inbox).isEmpty)
        #expect(library.note(deleted.id)?.path == "Home/Deleted note.md")
        #expect(manager.undoActionName == "Move")
        manager.undo()
        #expect(library.note(inbox.id) == inbox)
        #expect(library.note(deleted.id)?.isDeleted == true)
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
        undoably(manager) { library.moveFolders([home.id], before: work.id, undoManager: manager) }
        #expect(library.folders == [home, work])
        #expect(manager.undoActionName == "Move Folder")
        manager.undo()
        #expect(library.folders == [work, home])
        library.moveFolders([work.id], before: nil)
        #expect(library.folders == [home, work])
    }

    @Test func newFolderNamesAvoidTakenNamesWhateverTheirCase() {
        let library = NoteLibrary(folders: [Folder(name: "new folder")])
        #expect(library.newFolder().name == "New Folder 2")
    }

    @Test func aFolderThatIsGoneTakesNoNotes() {
        let (library, inbox, _, _, _) = makeLibrary()
        let gone = UUID()
        library.move([inbox.id], to: gone)
        #expect(library.note(inbox.id)?.folderID == nil)
        #expect(library.newNote(in: .folder(gone)).folderID == nil)
    }

    @Test func pinningLeavesDeletedNotesAlone() {
        let (library, _, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.setPinned([deleted.id], true, undoManager: manager) }
        #expect(library.note(deleted.id)?.isPinned == false)
        #expect(manager.undoActionName == "")
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

    // MARK: Files

    @Test func deletingAndRecoveringMoveTheFileInAndOutOfTheTrash() throws {
        let (library, inbox, _, _, _) = makeLibrary()
        library.delete([inbox.id])
        let binID = try #require(library.note(inbox.id)?.binID)
        library.recover([inbox.id])
        #expect(store.changes == [
            .trash(path: "Inbox note.md", id: binID, date: start + 60),
            .restore(id: binID, path: "Inbox note.md"),
        ])
    }

    @Test func movingANoteMovesItsFileIntoTheFolder() {
        let (library, inbox, filed, _, _) = makeLibrary()
        library.move([inbox.id], to: home.id)
        library.move([filed.id], to: nil)
        #expect(store.changes == [
            .move(from: "Inbox note.md", to: "Home/Inbox note.md"),
            .move(from: "Work/Filed note.md", to: "Filed note.md"),
        ])
        #expect(library.note(inbox.id)?.path == "Home/Inbox note.md")
    }

    @Test func aNameTakenInTheFolderIsNumbered() {
        let (library, inbox, _, _, _) = makeLibrary()
        let other = Note(body: "# Inbox note", path: "Home/Inbox note.md", created: start, folderID: home.id)
        let crowded = NoteLibrary(notes: library.notes + [other], folders: [work, home], store: store)
        crowded.move([inbox.id], to: home.id)
        #expect(crowded.note(inbox.id)?.path == "Home/Inbox note 2.md")
    }

    @Test func pinningWritesThePropertyIntoTheFile() {
        let (library, inbox, _, _, _) = makeLibrary()
        library.setPinned([inbox.id], true)
        #expect(store.changes == [.write(path: "Inbox note.md", text: "---\npinned: true\n---\n# Inbox note")])
        library.setPinned([inbox.id], false)
        #expect(store.changes.last == .write(path: "Inbox note.md", text: "# Inbox note"))
    }

    @Test func aNewNoteGetsItsFileOnceItsFirstLineIsFinished() {
        let (library, _, _, _, _) = makeLibrary()
        let note = library.newNote(in: .folder(work.id))
        library.updateBody(of: note.id, to: "Groceries\n")
        #expect(store.changes.isEmpty, "a single line may still be being typed")
        library.updateBody(of: note.id, to: "Groceries\n\nMilk\n")
        #expect(store.changes == [.create(path: "Work/Groceries.md", text: "Groceries\n\nMilk\n")])
        #expect(library.note(note.id)?.title == "Groceries")
        library.updateBody(of: note.id, to: "Groceries\n\nMilk, eggs\n")
        #expect(store.changes.last == .write(path: "Work/Groceries.md", text: "Groceries\n\nMilk, eggs\n"))
    }

    @Test func leavingANewNoteWritesWhatItHasOrLetsAnEmptyOneGo() {
        let (library, _, _, _, _) = makeLibrary()
        let empty = library.newNote(in: .inbox)
        library.leave(empty.id)
        #expect(library.note(empty.id) == nil)
        let short = library.newNote(in: .pinned)
        library.updateBody(of: short.id, to: "Call the plumber\n")
        library.leave(short.id)
        #expect(store.changes == [
            .create(path: "Call the plumber.md", text: "---\npinned: true\n---\nCall the plumber\n"),
        ])
    }

    @Test func undoingANewNoteAlreadyWrittenMovesItToRecentlyDeleted() {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        var note: Note?
        undoably(manager) { note = library.newNote(in: .inbox, undoManager: manager) }
        library.updateBody(of: note!.id, to: "Kept\n\nText\n")
        manager.undo()
        #expect(library.note(note!.id)?.isDeleted == true)
    }

    @Test func renamingANoteMovesItsFileAndUndoes() {
        let (library, _, filed, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.renameNote(filed.id, to: " Office / plan ", undoManager: manager) }
        #expect(library.note(filed.id)?.path == "Work/Office - plan.md")
        #expect(library.note(filed.id)?.title == "Office - plan")
        #expect(manager.undoActionName == "Rename Note")
        manager.undo()
        #expect(library.note(filed.id)?.path == "Work/Filed note.md")
        #expect(store.changes == [
            .move(from: "Work/Filed note.md", to: "Work/Office - plan.md"),
            .move(from: "Work/Office - plan.md", to: "Work/Filed note.md"),
        ])
    }

    @Test func renamingANoteWithATitlePropertyChangesThatToo() {
        let titled = Note(path: "Old.md", text: "---\ntitle: Old\nmarfa_id: 7\n---\nBody\n", created: start)
        let library = NoteLibrary(notes: [titled], store: store)
        library.renameNote(titled.id, to: "New")
        #expect(library.note(titled.id)?.title == "New")
        #expect(store.changes.last == .write(path: "New.md", text: "---\ntitle: New\nmarfa_id: 7\n---\nBody\n"))
    }

    @Test func aNoteCannotTakeANameAnotherNoteInItsFolderHas() {
        let (library, inbox, _, _, _) = makeLibrary()
        let other = Note(body: "Other", created: start)
        let crowded = NoteLibrary(notes: library.notes + [other], store: store)
        #expect(crowded.isNoteNameTaken("inbox NOTE", for: other.id))
        #expect(!crowded.isNoteNameTaken("Filed note", for: other.id), "that name is in another folder")
        crowded.renameNote(other.id, to: "Inbox note")
        #expect(crowded.note(other.id)?.path == "Other.md")
        _ = inbox
    }

    @Test func foldersAreDirectories() {
        let (library, _, _, _, _) = makeLibrary()
        let folder = library.newFolder()
        library.rename(work.id, to: "Office")
        library.deleteFolder(folder.id)
        #expect(store.changes == [
            .createFolder(path: "New Folder"),
            .moveFolder(from: "Work", to: "Office"),
            .removeFolder(path: "New Folder"),
        ])
        #expect(library.notes.compactMap(\.path).contains("Office/Filed note.md"))
    }

    @Test func theAttachmentsFolderNameIsTaken() {
        let (library, _, _, _, _) = makeLibrary()
        #expect(library.isFolderNameTaken("attachments"))
    }

    @Test func undoingARenameBringsBackTheTitleAsItWas() {
        let titled = Note(path: "meeting.md", text: "---\ntitle: Weekly Meeting\n---\nBody\n", created: start)
        let library = NoteLibrary(notes: [titled], store: store)
        let manager = undoManager()
        undoably(manager) { library.renameNote(titled.id, to: "Standup", undoManager: manager) }
        #expect(library.note(titled.id)?.title == "Standup")
        manager.undo()
        #expect(library.note(titled.id)?.path == "meeting.md")
        #expect(library.note(titled.id)?.title == "Weekly Meeting")
    }

    @Test func aRenameKeepsTheNoteInItsOwnDirectory() {
        let deep = Note(body: "Deep", path: "Work/Project/Deep.md", created: start, folderID: work.id)
        let library = NoteLibrary(notes: [deep], folders: [work], store: store)
        library.renameNote(deep.id, to: "Deeper")
        #expect(library.note(deep.id)?.path == "Work/Project/Deeper.md")
    }

    @Test func aNoteRecoveredAfterItsFolderWentComesBackToTheInbox() {
        let (library, _, filed, _, _) = makeLibrary()
        library.deleteFolder(work.id)
        library.recover([filed.id])
        #expect(library.note(filed.id)?.folderID == nil)
        #expect(library.note(filed.id)?.path == "Filed note.md")
        #expect(library.notes(in: .inbox).map(\.id).contains(filed.id))
    }

    @Test func aNewFolderNeverSharesAnotherFoldersIdentity() {
        let (library, _, _, _, _) = makeLibrary()
        let first = library.newFolder()
        library.rename(first.id, to: "Ideas")
        let second = library.newFolder()
        #expect(first.id != second.id)
        #expect(library.folders.map(\.name) == ["Work", "Home", "Ideas", "New Folder"])
    }

    @Test func longFirstLinesMakeNamesAnyFileSystemTakes() {
        let name = NoteText.fileName(for: String(repeating: "議事録", count: 60))
        #expect(name.utf8.count <= 200)
        #expect(NoteLibrary.fileSafe(String(repeating: "é", count: 300)).utf8.count <= 200)
    }

    @Test func attachedFilesAreLinkedFromWhereTheNoteIs() {
        let (library, inbox, filed, _, deleted) = makeLibrary()
        let image = Data("png".utf8)
        #expect(library.attach([("Photo 1.png", image)], to: inbox.id).map(\.link) == ["Attachments/Photo%201.png"])
        #expect(library.attach([("a(b).png", image)], to: filed.id).map(\.link) == ["../Attachments/a%28b%29.png"])
        #expect(library.attach([("x.png", image)], to: deleted.id).isEmpty, "a deleted note takes nothing")
        #expect(store.changes == [
            .attach(path: "Attachments/Photo 1.png", data: image),
            .attach(path: "Attachments/a(b).png", data: image),
        ])
    }

    @Test func attachmentNamesKeepTheirExtension() {
        #expect(NoteLibrary.attachmentName(String(repeating: "議", count: 120) + ".png").hasSuffix(".png"))
        #expect(NoteLibrary.attachmentName(".png") == "Image.png")
        #expect(NoteLibrary.attachmentName("a/b:c.jpeg") == "a-b-c.jpeg")
    }

    @Test func movingANoteRewritesItsAttachmentLinks() {
        let note = Note(body: "Photo\n\n![p](Attachments/p.png)\n", created: start)
        let library = NoteLibrary(notes: [note], folders: [work], store: store)
        library.move([note.id], to: work.id)
        #expect(library.note(note.id)?.body == "Photo\n\n![p](../Attachments/p.png)\n")
        #expect(store.changes.last == .write(path: "Work/Photo.md", text: "Photo\n\n![p](../Attachments/p.png)\n"))
    }

    // MARK: Sample content

    @Test func sampleContentFillsEverySidebarItem() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        try SampleLibrary.write(to: root.url, bin: bin.url)
        let library = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        await library.load()
        #expect(library.folders.count == 4)
        for item in [SidebarItem.inbox, .allNotes, .pinned, .recentlyDeleted] + library.folders.map({ .folder($0.id) }) {
            #expect(library.count(in: item) > 0, "\(item) is empty")
        }
        #expect(library.notes.contains { $0.body.contains("| --- |") })
        #expect(library.notes.contains { $0.body.contains("- [ ]") })
    }
}
