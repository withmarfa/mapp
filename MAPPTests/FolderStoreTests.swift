import Foundation
import Testing
@testable import MAPP

@MainActor
struct FolderStoreTests {
    let root: TemporaryFolder
    let bin: TemporaryFolder
    let store: FolderStore

    init() throws {
        root = try TemporaryFolder()
        bin = try TemporaryFolder()
        store = FolderStore(root: root.url, bin: bin.url)
    }

    @Test func notesAreTheMarkdownFilesAndFoldersTheDirectoriesAtTheTop() throws {
        try root.write("One", to: "One.md")
        try root.write("Two", to: "Work/Two.md")
        try root.write("Deep", to: "Work/Project/Deep.md")
        try root.write("Not a note", to: "Work/notes.txt")
        try root.write("Hidden", to: ".marfa/state.md")
        try root.write("Hidden", to: "Work/.drafts/draft.md")
        try root.write("Picture", to: "Attachments/readme.md")
        try FileManager.default.createDirectory(at: root.url.appending(path: "Empty"), withIntermediateDirectories: true)
        let library = try store.load()
        #expect(Set(library.folders) == ["Work", "Empty"])
        #expect(Set(library.notes.map(\.path)) == ["One.md", "Work/Two.md", "Work/Project/Deep.md"])
        #expect(library.notes.first { $0.path == "One.md" }?.text == "One")
    }

    @Test func aWriteReplacesTheFileWholeAndKeepsItsCreationDate() throws {
        try root.write("Old", to: "Note.md")
        let created = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: root.url.appending(path: "Note.md").path)
        store.perform(.write(path: "Note.md", text: "New"))
        store.drain()
        #expect(root.read("Note.md") == "New")
        let attributes = try FileManager.default.attributesOfItem(atPath: root.url.appending(path: "Note.md").path)
        #expect(attributes[.creationDate] as? Date == created)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path) == ["Note.md"], "no scratch file is left")
    }

    @Test func aCreateNeverWritesOverAFileAndSaysWhereItWent() async throws {
        try root.write("Someone else's", to: "Note.md")
        var moved: (String, String)?
        store.relocated = { from, to in moved = (from, to) }
        store.perform(.create(path: "Note.md", text: "Mine"))
        store.drain()
        #expect(root.read("Note.md") == "Someone else's")
        #expect(root.read("Note 2.md") == "Mine")
        await Task.yield()
        #expect(moved?.0 == "Note.md")
        #expect(moved?.1 == "Note 2.md")
    }

    @Test func changesQueuedForATakenPathReachTheFileMadeInstead() throws {
        try root.write("Someone else's", to: "Ideas.md")
        store.perform(.create(path: "Ideas.md", text: "Mine"))
        store.perform(.write(path: "Ideas.md", text: "Mine, edited"))
        store.perform(.trash(path: "Ideas.md", id: UUID(), date: .now))
        store.drain()
        #expect(root.read("Ideas.md") == "Someone else's")
        #expect(!root.exists("Ideas 2.md"))
        #expect(try store.load().trash.first?.note.text == "Mine, edited")
    }

    @Test func onceTheLibraryKnowsOfARelocationTheOldPathIsItsOwnAgain() throws {
        try root.write("Someone else's", to: "Ideas.md")
        store.perform(.create(path: "Ideas.md", text: "Mine"))
        store.drain()
        store.acknowledgeRelocation(of: "Ideas.md")
        store.perform(.write(path: "Ideas 2.md", text: "Mine, edited"))
        store.perform(.write(path: "Ideas.md", text: "Theirs, edited in MAPP"))
        store.drain()
        #expect(root.read("Ideas 2.md") == "Mine, edited")
        #expect(root.read("Ideas.md") == "Theirs, edited in MAPP")
    }

    @Test func aNoteRenamedOnlyInCaseKeepsItsFile() throws {
        try root.write("Text", to: "note.md")
        store.perform(.move(from: "note.md", to: "Note.md"))
        store.drain()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path) == ["Note.md"])
    }

    @Test func aChangeThatFailsIsReported() async throws {
        var failure: String?
        store.failed = { path, _ in failure = path }
        store.perform(.write(path: String(repeating: "x", count: 300) + ".md", text: "Too long a name"))
        store.drain()
        await Task.yield()
        #expect(failure?.hasSuffix(".md") == true)
    }

    @Test func trashingTakesTheNoteOutOfTheFolderAndRestoringPutsItBack() throws {
        try root.write("Text", to: "Work/Note.md")
        let id = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000)
        store.perform(.trash(path: "Work/Note.md", id: id, date: date))
        store.drain()
        #expect(!root.exists("Work/Note.md"))
        let trash = try store.load().trash
        #expect(trash.map(\.id) == [id])
        #expect(trash.first?.note.path == "Work/Note.md")
        #expect(trash.first?.note.text == "Text")
        #expect(trash.first?.trashed == date)

        store.perform(.restore(id: id, path: "Work/Note.md"))
        store.drain()
        #expect(root.read("Work/Note.md") == "Text")
        #expect(try store.load().trash.isEmpty)
    }

    @Test func purgingErasesTheTrashedNote() throws {
        try root.write("Old", to: "Old.md")
        try root.write("Recent", to: "Recent.md")
        let old = UUID()
        let recent = UUID()
        store.perform(.trash(path: "Old.md", id: old, date: Date(timeIntervalSince1970: 0)))
        store.perform(.trash(path: "Recent.md", id: recent, date: .now))
        store.perform(.purgeTrash(before: Date(timeIntervalSince1970: 10)))
        store.drain()
        #expect(try store.load().trash.map(\.id) == [recent])
        store.perform(.purge(id: recent))
        store.drain()
        #expect(try store.load().trash.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.url.path) == ["Trash.json"])
    }

    @Test func aFolderIsRemovedOnlyWhenNothingIsLeftInIt() throws {
        try root.write("Kept", to: "Kept/photo.png")
        try root.write("", to: "Hidden/.git/HEAD")
        try root.write("", to: "Empty/.DS_Store")
        try FileManager.default.createDirectory(at: root.url.appending(path: "Empty/Sub"), withIntermediateDirectories: true)
        for folder in ["Kept", "Hidden", "Empty"] { store.perform(.removeFolder(path: folder)) }
        store.drain()
        #expect(root.exists("Kept/photo.png"))
        #expect(root.exists("Hidden/.git/HEAD"), "a hidden file is someone's")
        #expect(!root.exists("Empty"))
    }

    @Test func attachmentsGoInTheirFolderUnderNamesNothingElseHas() throws {
        try root.write("Taken", to: "Attachments/Photo.png")
        let first = store.freeAttachmentPath(named: "Photo.png")
        let second = store.freeAttachmentPath(named: "Photo.png")
        #expect(first == "Attachments/Photo 2.png")
        #expect(second == "Attachments/Photo 3.png", "a name handed out is not handed out again before it is written")
        #expect(store.freeAttachmentPath(named: "PHOTO 2.png") == "Attachments/PHOTO 2 2.png", "names differing in case are one file")
        store.perform(.attach(path: first, data: Data("image".utf8)))
        store.drain()
        #expect(root.read(first) == "image")
        #expect(try store.load().notes.isEmpty, "an attachment is not a note")
        #expect(try store.load().folders.isEmpty, "the attachments folder is not a note folder")
    }

    @Test func movesAndFolderRenamesMoveTheFiles() throws {
        try root.write("Text", to: "Note.md")
        store.perform(.createFolder(path: "Work"))
        store.perform(.move(from: "Note.md", to: "Work/Note.md"))
        store.perform(.moveFolder(from: "Work", to: "Office"))
        store.drain()
        #expect(root.read("Office/Note.md") == "Text")
        #expect(!root.exists("Work"))
    }
}
