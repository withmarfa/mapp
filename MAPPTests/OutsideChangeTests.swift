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
        library.setPinned([plan.id], true)
        library.move([plan.id], to: nil)
        await library.reread()
        let after = try #require(library.note(plan.id))
        #expect(after.body == "# Plan\n\nMine\n")
        #expect(after.isPinned)
        #expect(after.path == "Plan.md")
        #expect(root.read("Plan.md") == "---\npinned: true\n---\n# Plan\n\nMine\n")
    }
}
