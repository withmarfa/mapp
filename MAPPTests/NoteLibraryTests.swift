import Foundation
import Testing
@testable import MAPP

struct NoteLibraryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(name: "Work")
    let home = Folder(name: "Home")

    let store = RecordingStore()

    func makeLibrary() -> (NoteLibrary, inbox: Note, filed: Note, favorite: Note, deleted: Note) {
        let inbox = Note(body: "# Inbox note", created: start)
        let filed = Note(body: "# Filed note", path: "Work/Filed note.md", created: start, folderID: work.id)
        let favorite = Note(body: "# Favorite note", path: "Home/Favorite note.md", created: start, folderID: home.id, isFavorite: true)
        let deleted = Note(body: "# Deleted note", path: "Work/Deleted note.md", created: start, folderID: work.id, deleted: start)
        let library = NoteLibrary(
            notes: [inbox, filed, favorite, deleted], folders: [work, home], store: store, now: { start + 60 }
        )
        return (library, inbox, filed, favorite, deleted)
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
        let (library, inbox, filed, favorite, deleted) = makeLibrary()
        #expect(library.items(in: .inbox).map(\.id) == [inbox.id])
        #expect(library.items(in: .allNotes).map(\.id) == [inbox.id, filed.id, favorite.id])
        #expect(library.items(in: .favorites).map(\.id) == [favorite.id])
        #expect(library.items(in: .folder(work.id)).map(\.id) == [filed.id])
        #expect(library.items(in: .recentlyDeleted).map(\.id) == [deleted.id])
        #expect(library.count(in: .allNotes) == 3)
    }

    @Test func searchCoversEveryLiveNoteIgnoringCaseAndAccents() {
        let (library, _, filed, _, _) = makeLibrary()
        library.updateBody(of: filed.id, to: "# Filed note\n\nA proper ragù")
        #expect(library.items(matching: "RAGU").map(\.id) == [filed.id])
        #expect(library.items(matching: "note").count == 3)
        #expect(library.items(matching: "Deleted").isEmpty)
        #expect(library.items(matching: "   ").isEmpty)
    }

    @Test func sidebarItemsAreNamed() {
        let (library, _, _, _, _) = makeLibrary()
        #expect(library.name(of: .inbox) == "Inbox")
        #expect(library.name(of: .folder(home.id)) == "Home")
        #expect(library.name(of: .recentlyDeleted) == "Recently Deleted")
    }

    // MARK: Notes

    @Test func aNewItemIsWrittenAtOnceUnderItsTitleInTheFolderItWasMadeIn() throws {
        let (library, _, _, _, _) = makeLibrary()
        let note = try #require(library.createItem(typeID: "core.note", title: "Groceries", body: "Milk\n", in: .folder(home.id)).flatMap { library.note($0) })
        #expect(note.folderID == home.id)
        #expect(note.path == "Home/Groceries.md")
        #expect(note.created == start + 60)
        #expect(library.items(in: .folder(home.id)).contains { $0.id == note.id })
        #expect(library.note(note.id)?.title == "Groceries")
        #expect(store.changes.last == .create(path: "Home/Groceries.md", text: library.note(note.id)!.file.text, id: note.id))
    }

    @Test func aNewItemMadeOutsideAFolderGoesToItsTypesFolder() throws {
        let (library, _, _, _, _) = makeLibrary()
        let note = try #require(library.createItem(typeID: "core.note", title: "Loose", in: .allNotes).flatMap { library.note($0) })
        #expect(note.path == "Notes/Loose.md")
        #expect(library.folder(note.folderID!)?.name == "Notes")
        #expect(store.changes.contains(.createFolder(path: "Notes", id: try #require(note.folderID))))
        let gone = try #require(library.createItem(typeID: "core.note", title: "Also loose", in: .folder(.mint())).flatMap { library.note($0) })
        #expect(gone.path == "Notes/Also loose.md", "a folder that is gone takes nothing")
        #expect(gone.folderID == note.folderID)
    }

    @Test func aNewItemUndoesToRecentlyDeletedAndRedoes() throws {
        let (library, _, _, _, _) = makeLibrary()
        let manager = undoManager()
        var note: Note?
        undoably(manager) { note = library.createItem(typeID: "core.note", title: "Fresh", undoManager: manager).flatMap { library.note($0) } }
        let id = try #require(note?.id)
        #expect(manager.undoActionName == "New Item")
        manager.undo()
        #expect(library.note(id)?.isDeleted == true)
        manager.redo()
        #expect(library.note(id)?.isDeleted == false)
    }

    @Test func editingABodyUpdatesTheModifiedDateOnlyWhenItChanges() {
        let (library, inbox, _, _, _) = makeLibrary()
        library.updateBody(of: inbox.id, to: inbox.body)
        #expect(library.note(inbox.id)?.modified == start)
        library.updateBody(of: inbox.id, to: "# Inbox note, edited")
        #expect(library.note(inbox.id)?.modified == start + 60)
        #expect(library.note(inbox.id)?.title == "Inbox note, edited", "a note named after its first line reads as the line is typed")
        #expect(library.note(inbox.id)?.path == "Inbox note.md", "its file takes the name once the note is left")
        #expect(store.changes == [.write(path: "Inbox note.md", text: "# Inbox note, edited")])
    }

    @Test func deletingMovesToRecentlyDeletedAndUndoes() {
        let (library, inbox, filed, _, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.delete([inbox.id, filed.id], undoManager: manager) }
        #expect(manager.undoActionName == "Delete Notes")
        #expect(library.items(in: .recentlyDeleted).count == 3)
        #expect(library.items(in: .allNotes).count == 1)
        manager.undo()
        #expect(library.note(inbox.id)?.holdsTheSame(as: inbox) == true)
        #expect(library.note(filed.id)?.holdsTheSame(as: filed) == true)
        manager.redo()
        #expect(library.note(inbox.id)?.isDeleted == true)
    }

    @Test func recoveringReturnsANoteToWhereItWasAndUndoes() {
        let (library, _, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.recover([deleted.id], undoManager: manager) }
        #expect(library.items(in: .folder(work.id)).map(\.id).contains(deleted.id))
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
        #expect(library.items(in: .folder(home.id)).count == 3)
        #expect(library.items(in: .inbox).isEmpty)
        #expect(library.note(deleted.id)?.path == "Home/Deleted note.md")
        #expect(manager.undoActionName == "Move")
        manager.undo()
        #expect(library.note(inbox.id)?.holdsTheSame(as: inbox) == true)
        #expect(library.note(deleted.id)?.isDeleted == true)
    }

    @Test func movingToNoFolderReturnsToTheInbox() {
        let (library, _, filed, _, _) = makeLibrary()
        library.move([filed.id], to: nil)
        #expect(library.items(in: .inbox).map(\.id).contains(filed.id))
    }

    @Test func addingAndRemovingFavoritesUndo() {
        let (library, inbox, _, favorite, _) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.setFavorite([inbox.id], true, undoManager: manager) }
        #expect(manager.undoActionName == "Add to Favorites")
        undoably(manager) { library.setFavorite([favorite.id], false, undoManager: manager) }
        #expect(manager.undoActionName == "Remove from Favorites")
        #expect(library.items(in: .favorites).map(\.id) == [inbox.id])
        manager.undo()
        manager.undo()
        #expect(library.items(in: .favorites).map(\.id) == [favorite.id])
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
        #expect(library.note(filed.id)?.holdsTheSame(as: filed) == true)
        #expect(library.note(deleted.id)?.holdsTheSame(as: deleted) == true)
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
        let gone = ItemID.mint()
        library.move([inbox.id], to: gone)
        #expect(library.note(inbox.id)?.folderID == nil)
    }

    @Test func favoritingLeavesDeletedNotesAlone() {
        let (library, _, _, _, deleted) = makeLibrary()
        let manager = undoManager()
        undoably(manager) { library.setFavorite([deleted.id], true, undoManager: manager) }
        #expect(library.note(deleted.id)?.isFavorite == false)
        #expect(manager.undoActionName == "")
    }

    @Test func actionsThatChangeNothingRegisterNoUndo() {
        let (library, inbox, filed, favorite, _) = makeLibrary()
        let manager = undoManager()
        let before = library.notes
        undoably(manager) { library.delete([.mint()], undoManager: manager) }
        undoably(manager) { library.setFavorite([favorite.id], true, undoManager: manager) }
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

    @Test func favoritingWritesTheTagIntoTheFile() {
        let (library, inbox, _, _, _) = makeLibrary()
        library.setFavorite([inbox.id], true)
        #expect(store.changes == [.write(path: "Inbox note.md", text: "---\ntags: [favorite]\n---\n# Inbox note")])
        library.setFavorite([inbox.id], false)
        #expect(store.changes.last == .write(path: "Inbox note.md", text: "# Inbox note"))
    }

    @Test func aTagsStringGainsTheTag() {
        let note = Note(path: "Odd.md", text: "---\ntags: one\n---\n# Odd", created: start)
        let library = NoteLibrary(notes: [note], store: store, now: { start })
        library.setFavorite([note.id], true)
        #expect(store.changes == [.write(path: "Odd.md", text: "---\ntags: one, favorite\n---\n# Odd")])
        #expect(library.note(note.id)?.isFavorite == true)
    }

    @Test func tagsThatCannotBeChangedSafelyAreLeftAndThePersonIsTold() {
        let unreadable = Note(path: "Numbers.md", text: "---\ntags: [1]\n---\n# Numbers", created: start)
        let folded = Note(path: "Folded.md", text: "---\ntags: >\n  one\n---\n# Folded", created: start)
        let library = NoteLibrary(notes: [unreadable, folded], store: store, now: { start })
        let manager = undoManager()
        undoably(manager) { library.setFavorite([unreadable.id], true, undoManager: manager) }
        #expect(store.changes.isEmpty)
        #expect(manager.undoActionName == "")
        #expect(library.failure?.title == "Can’t Add to Favorites")
        #expect(library.failure?.message.contains("Numbers") == true)
        library.failure = nil
        library.setFavorite([folded.id], true)
        #expect(library.failure?.message.contains("Folded") == true)
        library.failure = nil
        library.setFavorite([unreadable.id, folded.id], true)
        #expect(library.failure?.message.hasPrefix("Some notes") == true)
        #expect(store.changes.isEmpty)
        #expect(library.notes.map(\.file.text) == [unreadable.file.text, folded.file.text])
    }

    @Test func anUndoThatCannotChangeTheTagsSafelyTellsThePerson() {
        let note = Note(path: "Odd.md", text: "---\ntags: [a]\n---\n# Odd", created: start)
        let library = NoteLibrary(notes: [note], store: store, now: { start })
        let manager = undoManager()
        undoably(manager) { library.setFavorite([note.id], true, undoManager: manager) }
        let folded = Note(path: "Odd.md", text: "---\ntags: >\n  a, favorite\ntitle: x\n---\n# Odd", created: start)
        library.notes[0].file = folded.file
        store.changes.removeAll()
        manager.undo()
        #expect(store.changes.isEmpty)
        #expect(library.failure?.title == "Can’t Remove from Favorites")
        #expect(library.failure?.message.contains("Odd") == true)
    }

    /// Undo puts back the very bytes the file had, which turning the favorite back would not.
    @Test(arguments: [
        ("---\ntags:\n  - favorite\ntitle: x\n---\n# Note", false),
        ("---\ntags: [favorite, a]\n---\n# Note", false),
        ("---\ntags:\n  - favorite\n  # mine\ntitle: x\n---\n# Note", false),
        ("---\ntags: [a,]\n---\n# Note", true),
        ("---\n---\n# Note", true),
        ("\u{FEFF}---\r\ntags: a\r\n---\r\n# Note\r\n", true),
    ])
    func undoRestoresTheExactFile(text: String, adding: Bool) {
        let note = Note(path: "Note.md", text: text, created: start)
        let library = NoteLibrary(notes: [note], store: store, now: { start })
        let manager = undoManager()
        undoably(manager) { library.setFavorite([note.id], adding, undoManager: manager) }
        let changed = library.note(note.id)?.file.text
        #expect(changed != text)
        #expect(library.note(note.id)?.isFavorite == adding)
        manager.undo()
        #expect(library.note(note.id)?.file.text == text)
        #expect(store.changes.last == .write(path: "Note.md", text: text))
        manager.redo()
        #expect(library.note(note.id)?.file.text == changed)
        manager.undo()
        #expect(library.note(note.id)?.file.text == text)
    }

    @Test func undoAfterTheBodyChangedKeepsTheBody() {
        let note = Note(path: "Note.md", text: "---\n---\nOld body\n", created: start)
        let library = NoteLibrary(notes: [note], store: store, now: { start })
        let manager = undoManager()
        undoably(manager) { library.setFavorite([note.id], true, undoManager: manager) }
        library.updateBody(of: note.id, to: "New body\n")
        manager.undo()
        #expect(library.note(note.id)?.file.text == "---\n---\nNew body\n")
    }

    @Test func undoAfterAnotherFieldChangedTurnsOnlyTheFavoriteBack() {
        let note = Note(path: "Note.md", text: "---\ntags: [a]\n---\n# Note", created: start)
        let library = NoteLibrary(notes: [note], store: store, now: { start })
        let manager = undoManager()
        undoably(manager) { library.setFavorite([note.id], true, undoManager: manager) }
        var file = library.notes[0].file
        file.setProperty("status", "open")
        library.applyItemFiles([note.id: file], undoManager: nil, name: "Edit")
        manager.undo()
        #expect(library.note(note.id)?.file.text == "---\ntags: [a]\nstatus: open\n---\n# Note")
    }

    @Test func laterEditsToANewItemAreWrittenToItsFile() throws {
        let (library, _, _, _, _) = makeLibrary()
        let note = try #require(library.createItem(typeID: "core.note", title: "Groceries", body: "Milk\n", in: .folder(work.id)).flatMap { library.note($0) })
        library.updateBody(of: note.id, to: "Milk, eggs\n")
        #expect(store.changes.last == .write(path: "Work/Groceries.md", text: library.note(note.id)!.file.text))
        #expect(library.note(note.id)?.body == "Milk, eggs\n")
    }

    @Test func aNewItemKeepsItsTitleAndFileNameWhateverItsFirstLineBecomes() throws {
        let (library, _, _, _, _) = makeLibrary()
        let note = try #require(library.createItem(typeID: "core.note", title: "Groceries", body: "Milk\n", in: .folder(work.id)).flatMap { library.note($0) })
        library.updateBody(of: note.id, to: "Something else entirely\n")
        let changes = store.changes.count
        library.leave(note.id)
        #expect(library.note(note.id)?.path == "Work/Groceries.md")
        #expect(library.note(note.id)?.title == "Groceries")
        #expect(store.changes.count == changes, "leaving a note whose name is its own writes nothing")
    }

    @Test func aNoteLeftWithoutEditsIsNotTouched() {
        let (library, inbox, _, _, _) = makeLibrary()
        library.leave(inbox.id)
        library.finish()
        #expect(store.changes.isEmpty)
        #expect(library.note(inbox.id)?.holdsTheSame(as: inbox) == true)
    }

    @Test func aNoteNamedAfterItsFirstLineTakesTheNewLineOnceLeft() {
        let (library, _, filed, _, _) = makeLibrary()
        library.updateBody(of: filed.id, to: "# Filed notes\n\nMore\n")
        #expect(library.note(filed.id)?.title == "Filed notes", "the list reads the line as it is typed")
        #expect(library.note(filed.id)?.path == "Work/Filed note.md", "the file is renamed once, when the note is left")
        library.leave(filed.id)
        #expect(library.note(filed.id)?.path == "Work/Filed notes.md")
        #expect(store.changes.last == .move(from: "Work/Filed note.md", to: "Work/Filed notes.md"))
        library.leave(filed.id)
        #expect(store.changes.count == 2, "leaving again changes nothing")
    }

    @Test func aNoteAnEarlierVersionNamedWithACharacterReferenceTakesItsLinesNameOnceEdited() {
        let old = Note(body: "Plan&#x20;\n\nMore\n", path: "Plan&#x20;.md", created: start)
        let library = NoteLibrary(notes: [old], folders: [], store: store, now: { start + 60 })
        #expect(library.note(old.id)?.title == "Plan", "the list reads the line")
        library.leave(old.id)
        #expect(store.changes.isEmpty, "a note opened and left alone is not renamed")
        library.updateBody(of: old.id, to: "Plan&#x20;\n\nMore, and more\n")
        library.leave(old.id)
        #expect(library.note(old.id)?.path == "Plan.md")
        #expect(store.changes.last == .move(from: "Plan&#x20;.md", to: "Plan.md"))
    }

    @Test func aNameGivenByHandThatResemblesAnEarlierVersionsIsKept() {
        let (library, _, filed, _, _) = makeLibrary()
        library.updateBody(of: filed.id, to: "# Q&A\n")
        library.leave(filed.id)
        library.renameNote(filed.id, to: "Q&amp;A")
        library.updateBody(of: filed.id, to: "# Q&A\n\nMore\n")
        library.leave(filed.id)
        #expect(library.note(filed.id)?.path == "Work/Q&amp;A.md", "the person's name stands")
    }

    @Test func aNoteNamedByHandKeepsItsNameWhateverItsFirstLineSays() {
        let (library, _, filed, _, _) = makeLibrary()
        library.renameNote(filed.id, to: "Office")
        library.updateBody(of: filed.id, to: "# Something else\n")
        library.leave(filed.id)
        #expect(library.note(filed.id)?.path == "Work/Office.md")
        #expect(library.note(filed.id)?.title == "Office")
        library.renameNote(filed.id, to: "Something else")
        library.updateBody(of: filed.id, to: "# Something new\n")
        library.leave(filed.id)
        #expect(library.note(filed.id)?.path == "Work/Something new.md", "named after the line again, it follows it again")
    }

    @Test func aFirstLineTakesANumberWhenAnotherNoteHasItsName() {
        let (library, inbox, _, _, _) = makeLibrary()
        let other = Note(body: "Other", created: start)
        let crowded = NoteLibrary(notes: library.notes + [other], store: store)
        crowded.updateBody(of: inbox.id, to: "Other\n")
        crowded.leave(inbox.id)
        #expect(crowded.note(inbox.id)?.path == "Other 2.md")
        crowded.updateBody(of: inbox.id, to: "Another\n")
        crowded.leave(inbox.id)
        #expect(crowded.note(inbox.id)?.path == "Another.md", "a numbered name still follows its line")
    }

    @Test func aFirstLineANameCannotHoldIsKeptWholeAsTheTitle() {
        let (library, inbox, _, _, _) = makeLibrary()
        let note = inbox
        library.updateBody(of: note.id, to: "R\\&D: plan\n\nBudget\n")
        library.leave(note.id)
        #expect(library.note(note.id)?.path == "R&D- plan.md")
        #expect(library.note(note.id)?.file.title == "R&D: plan")
        #expect(library.note(note.id)?.title == "R&D: plan")
        #expect(library.note(note.id)?.preview == "Budget")
    }

    @Test func aNoteKeepsFollowingItsLineWhicheverOutsideChangeArrivesFirst() {
        var renamedFirst = Note(path: "Plan.md", text: "Plan\n", created: start)
        renamedFirst.path = "Plan B.md"
        renamedFirst.reviewNaming()
        renamedFirst.file = NoteFile(text: "Plan B\n")
        renamedFirst.reviewNaming()
        #expect(renamedFirst.namedLine == "Plan B")

        var rewrittenFirst = Note(path: "Plan.md", text: "Plan\n", created: start)
        rewrittenFirst.file = NoteFile(text: "Plan B\n")
        rewrittenFirst.reviewNaming()
        #expect(rewrittenFirst.namedLine == "Plan", "it still carries the name of the line it follows")
        rewrittenFirst.path = "Plan B.md"
        rewrittenFirst.reviewNaming()
        #expect(rewrittenFirst.namedLine == "Plan B")

        rewrittenFirst.file = NoteFile(text: "---\ntitle: Roadmap\n---\nPlan B\n")
        rewrittenFirst.reviewNaming()
        #expect(rewrittenFirst.namedLine == nil, "a title given elsewhere is the note's own")
        #expect(rewrittenFirst.title == "Roadmap")
    }

    @Test func aNoteWithNoWordsYetStillFollowsItsLineOnceItHasOne() {
        let (library, inbox, _, _, _) = makeLibrary()
        let note = inbox
        library.updateBody(of: note.id, to: "```\n")
        library.leave(note.id)
        #expect(library.note(note.id)?.path == "New Note.md")
        library.updateBody(of: note.id, to: "Snippets\n\n```\n")
        library.leave(note.id)
        #expect(library.note(note.id)?.path == "Snippets.md")
    }

    @Test func openingWindowsLeavesEachNoteSoItsNameHasFollowedItsLine() {
        let (library, inbox, filed, _, _) = makeLibrary()
        library.updateBody(of: inbox.id, to: "Renamed\n")
        #expect(library.idsForWindows([inbox.id, filed.id, .mint()]) == [inbox.id, filed.id], "an item that is not there opens nothing")
        #expect(library.note(inbox.id)?.path == "Renamed.md")
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
            .createFolder(path: "New Folder", id: folder.id),
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
        #expect(library.items(in: .inbox).map(\.id).contains(filed.id))
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
        #expect(NoteText.fileSafe(String(repeating: "é", count: 300)).utf8.count <= 200)
    }

    @Test func attachedFilesAreLinkedFromWhereTheNoteIs() async throws {
        let (library, inbox, filed, _, deleted) = makeLibrary()
        let image = Data("png".utf8)
        #expect(try await library.attach([("Photo 1.png", image)], to: inbox.id).map(\.link) == ["Attachments/Photo%201.png"])
        #expect(try await library.attach([("a(b).png", image)], to: filed.id).map(\.link) == ["../Attachments/a%28b%29.png"])
        #expect(try await library.attach([("x.png", image)], to: deleted.id).isEmpty, "a deleted note takes nothing")
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
        for item in [SidebarItem.inbox, .allNotes, .favorites, .recentlyDeleted] + library.folders.map({ .folder($0.id) }) {
            #expect(library.count(in: item) > 0, "\(item) is empty")
        }
        #expect(library.notes.contains { $0.body.contains("| --- |") })
        #expect(library.notes.contains { $0.body.contains("- [ ]") })
    }
}
