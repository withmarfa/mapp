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
        #expect(Set(library.folders.map(\.name)) == ["Work", "Empty"])
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

    @Test func unreadableUTF8IsSkippedAndAByteOrderMarkIsKept() throws {
        try root.write("\u{FEFF}Body\n", to: "Kept.md")
        try Data([0xFF]).write(to: root.url.appending(path: "Unreadable.md"))
        let loaded = try store.load()
        #expect(loaded.notes.map(\.path) == ["Kept.md"])
        #expect(loaded.notes.first?.text == "\u{FEFF}Body\n")
    }

    @Test func aCreateNeverWritesOverAFileAndSaysWhereItWent() async throws {
        try root.write("Someone else's", to: "Note.md")
        var moved: (String, String)?
        store.relocated = { from, to in moved = (from, to) }
        store.perform(.create(path: "Note.md", text: "Mine", id: .mint()))
        store.drain()
        #expect(root.read("Note.md") == "Someone else's")
        #expect(root.read("Note 2.md") == "Mine")
        // The store tells the library on the main actor, after the change.
        for _ in 0..<100 where moved == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(moved?.0 == "Note.md")
        #expect(moved?.1 == "Note 2.md")
    }

    @Test func changesQueuedForATakenPathReachTheFileMadeInstead() throws {
        try root.write("Someone else's", to: "Ideas.md")
        store.perform(.create(path: "Ideas.md", text: "Mine", id: .mint()))
        store.perform(.write(path: "Ideas.md", text: "Mine, edited"))
        store.perform(.trash(path: "Ideas.md", id: UUID(), date: .now))
        store.drain()
        #expect(root.read("Ideas.md") == "Someone else's")
        #expect(!root.exists("Ideas 2.md"))
        #expect(try store.load().trash.first?.note.text == "Mine, edited")
    }

    @Test func onceTheLibraryKnowsOfARelocationTheOldPathIsItsOwnAgain() throws {
        try root.write("Someone else's", to: "Ideas.md")
        store.perform(.create(path: "Ideas.md", text: "Mine", id: .mint()))
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

    @Test func changesQueuedBehindAFailedMoveReachTheFileWhereItStayed() async throws {
        try root.write("Milk", to: "Groceries.md")
        let file = root.url.appending(path: "Groceries.md").path
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file) }
        // A locked file cannot be renamed.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file)
        var moved: (String, String)?
        store.relocated = { from, to in moved = (from, to) }
        store.perform(.move(from: "Groceries.md", to: "Shopping.md"))
        store.drain()
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file)
        store.perform(.write(path: "Shopping.md", text: "Milk, eggs"))
        store.drain()
        #expect(root.read("Groceries.md") == "Milk, eggs")
        #expect(!root.exists("Shopping.md"), "no second note is made under the new name")
        for _ in 0..<100 where moved == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(moved?.0 == "Shopping.md")
        #expect(moved?.1 == "Groceries.md")
    }

    @Test func aChangeThatFailsIsReported() async throws {
        var failure: String?
        store.failed = { path, _ in failure = path }
        store.perform(.write(path: String(repeating: "x", count: 300) + ".md", text: "Too long a name"))
        store.drain()
        for _ in 0..<100 where failure == nil { try await Task.sleep(for: .milliseconds(10)) }
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
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: bin.url.path)) == ["Trash.json", "Identities.json"])
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
        store.perform(.createFolder(path: "Work", id: .mint()))
        store.perform(.move(from: "Note.md", to: "Work/Note.md"))
        store.perform(.moveFolder(from: "Work", to: "Office"))
        store.drain()
        #expect(root.read("Office/Note.md") == "Text")
        #expect(!root.exists("Work"))
    }

    @Test func aTrashListThatCannotBeReadIsSetAsideAndMadeAgainFromTheBin() throws {
        try root.write("# Groceries\n\nMilk\n", to: "Work/Groceries.md")
        store.perform(.trash(path: "Work/Groceries.md", id: UUID(), date: .now))
        store.drain()
        try Data("not a list".utf8).write(to: bin.url.appending(path: "Trash.json"))
        let trash = try store.load().trash
        #expect(trash.count == 1)
        #expect(trash.first?.note.path == "Groceries.md", "where it was is lost, so it comes back at the top")
        #expect(trash.first?.note.text == "# Groceries\n\nMilk\n")
        let names = try FileManager.default.contentsOfDirectory(atPath: bin.url.path)
        #expect(names.contains { $0.hasPrefix("Trash ") && $0.hasSuffix(".json") }, "the unreadable list is kept aside")
        store.perform(.trash(path: "Work/Other.md", id: UUID(), date: .now))
        store.drain()
        #expect(try store.load().trash.count == 1, "a later change keeps what was found")
    }

    @Test func aNotesFolderThatHasGoneIsNeverMadeAgain() async throws {
        var failure: String?
        store.failed = { path, _ in failure = path }
        try FileManager.default.removeItem(at: root.url)
        store.perform(.create(path: "Work/Note.md", text: "Text", id: .mint()))
        store.drain()
        #expect(!FileManager.default.fileExists(atPath: root.url.path))
        for _ in 0..<100 where failure == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(failure == "Work/Note.md")
    }
}
