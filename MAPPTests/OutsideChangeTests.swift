import Foundation
import Testing
@testable import MAPP

/// Another app, an agent or the Finder changing the notes folder while MAPP has it open.
@MainActor
struct OutsideChangeTests {
    let root: TemporaryFolder
    let bin: TemporaryFolder
    let library: NoteLibrary

    init() async throws {
        root = try TemporaryFolder()
        bin = try TemporaryFolder()
        try root.write("# Plan\n\nFirst draft\n", to: "Work/Plan.md")
        try root.write("Shopping\n", to: "Shopping.md")
        library = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        // A file gone from the folder is waited for a moment before its note goes; not the app's whole moment.
        library.missingGrace = 0.05
        await library.load()
    }

    private func note(at path: String) -> Note? {
        library.notes.first { $0.path == path }
    }

    @Test func aFileChangedOutsideIsReadAgain() async throws {
        let plan = try #require(note(at: "Work/Plan.md"))
        try root.write("# Plan\n\nSecond draft, by an agent\n", to: "Work/Plan.md")
        await library.reread()
        #expect(library.note(plan.id)?.body == "# Plan\n\nSecond draft, by an agent\n")
    }

    @Test func aFileRenamedOutsideStaysTheSameNote() async throws {
        let plan = try #require(note(at: "Work/Plan.md"))
        try FileManager.default.createDirectory(at: root.url.appending(path: "Home"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.url.appending(path: "Work/Plan.md"), to: root.url.appending(path: "Home/Plan B.md"))
        await library.reread()
        let moved = try #require(library.note(plan.id))
        #expect(moved.path == "Home/Plan B.md")
        #expect(moved.title == "Plan B")
        #expect(library.folder(try #require(moved.folderID))?.name == "Home")
    }

    @Test func aFileRenamedOutsideKeepsItsIdentifierWhenAnotherTakesItsName() async throws {
        let shopping = try #require(note(at: "Shopping.md"))
        try FileManager.default.moveItem(at: root.url.appending(path: "Shopping.md"), to: root.url.appending(path: "Groceries.md"))
        try root.write("A new list\n", to: "Shopping.md")
        await library.reread()
        #expect(library.note(shopping.id)?.path == "Groceries.md")
        #expect(library.note(shopping.id)?.body == "Shopping\n")
        let newcomer = try #require(note(at: "Shopping.md"))
        #expect(newcomer.id != shopping.id)
        #expect(newcomer.body == "A new list\n")
    }

    @Test func aFolderRenamedOutsideKeepsItsIdentifierAndItsNotes() async throws {
        let plan = try #require(note(at: "Work/Plan.md"))
        let work = try #require(library.folders.first { $0.name == "Work" })
        try FileManager.default.moveItem(at: root.url.appending(path: "Work"), to: root.url.appending(path: "Office"))
        await library.reread()
        #expect(library.folders.map(\.id) == [work.id])
        #expect(library.folder(work.id)?.name == "Office")
        #expect(library.note(plan.id)?.path == "Office/Plan.md")
        #expect(library.note(plan.id)?.folderID == work.id)
    }

    @Test func filesAddedAndDeletedOutsideComeAndGo() async throws {
        let shopping = try #require(note(at: "Shopping.md"))
        try root.write("Written by an agent\n", to: "Agent.md")
        try FileManager.default.removeItem(at: root.url.appending(path: "Shopping.md"))
        await library.reread()
        #expect(library.note(shopping.id) == nil)
        #expect(note(at: "Agent.md")?.body == "Written by an agent\n")
        #expect(library.notes(in: .recentlyDeleted).isEmpty, "a file deleted outside is gone, not trashed")
    }

    @Test func foldersMadeAndRemovedOutsideAppearAndGo() async throws {
        try FileManager.default.createDirectory(at: root.url.appending(path: "Ideas"), withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: root.url.appending(path: "Work"))
        await library.reread()
        #expect(library.folders.map(\.name) == ["Ideas"])
        #expect(note(at: "Work/Plan.md") == nil)
    }

    @Test func theLibrarysOwnChangesAreNotTakenForAnothersOnceMade() async throws {
        let plan = try #require(note(at: "Work/Plan.md"))
        library.updateBody(of: plan.id, to: "# Plan\n\nMine\n")
        library.setFavorite([plan.id], true)
        library.move([plan.id], to: nil)
        await library.reread()
        let after = try #require(library.note(plan.id))
        #expect(after.body == "# Plan\n\nMine\n")
        #expect(after.isFavorite)
        #expect(after.path == "Plan.md")
        #expect(root.read("Plan.md") == "---\ntags: [favorite]\n---\n# Plan\n\nMine\n")
    }

    @Test func aRenameThatFailsLeavesOneNoteAndIsTriedAgain() async throws {
        let shopping = try #require(note(at: "Shopping.md"))
        let file = root.url.appending(path: "Shopping.md").path
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file) }
        library.updateBody(of: shopping.id, to: "Groceries\n")
        library.store?.drain()
        // A locked file cannot be renamed.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file)
        library.leave(shopping.id)
        #expect(library.note(shopping.id)?.path == "Groceries.md")
        library.store?.drain()
        for _ in 0..<100 where library.note(shopping.id)?.path != "Shopping.md" || library.failure == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(library.note(shopping.id)?.path == "Shopping.md", "the note is where its file stayed")
        #expect(library.note(shopping.id)?.title == "Groceries", "and still goes by its first line")
        #expect(library.failure != nil)

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file)
        library.leave(shopping.id)
        library.store?.drain()
        #expect(library.note(shopping.id)?.path == "Groceries.md")
        #expect(root.read("Groceries.md") == "Groceries\n")
        #expect(!root.exists("Shopping.md"))
    }

    @Test func aMoveToAFolderThatFailsKeepsTheNotesLinksWhereItStayed() async throws {
        let shopping = try #require(note(at: "Shopping.md"))
        let work = try #require(library.folders.first { $0.name == "Work" })
        library.updateBody(of: shopping.id, to: "Shopping\n\n![Receipt](Attachments/Receipt.png)\n")
        library.store?.drain()
        let file = root.url.appending(path: "Shopping.md").path
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file) }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file)
        library.move([shopping.id], to: work.id)
        #expect(library.note(shopping.id)?.body.contains("](../Attachments/Receipt.png)") == true)
        library.store?.drain()
        for _ in 0..<100 where library.note(shopping.id)?.path != "Shopping.md" || library.failure == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let stayed = try #require(library.note(shopping.id))
        #expect(stayed.path == "Shopping.md")
        #expect(stayed.folderID == nil)
        #expect(stayed.body == "Shopping\n\n![Receipt](Attachments/Receipt.png)\n")
    }
}
