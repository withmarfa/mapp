import Foundation
import Testing
@testable import MAPP

@MainActor
struct TypedRecordTests {
    @Test(arguments: [("\n", "\n"), ("\r\n", "\r\n"), ("\r\n", "\n")])
    func unpinningTheFirstPropertyKeepsTypedMetadataAfterReread(opening: String, following: String) async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let store = FolderStore(root: root.url, bin: bin.url)
        let path = "Records/Task.md"
        let remainder = "type: example.task\(following)title: Task\(following)child-of: \"[[Parent]]\"\(following)\(following)custom: unchanged\(following)---\(opening)Body\(following)"
        try root.write("---\(opening)pinned: true\(opening)\(following)\(remainder)", to: path)
        let library = NoteLibrary(loadingFrom: store, defaults: nil)
        await library.load()
        let note = try #require(library.notes.first)
        library.setPinned([note.id], false)
        store.drain()
        #expect(try Data(contentsOf: root.url.appending(path: path)) == Data("---\(opening)\(remainder)".utf8))
        await library.reread()
        let reopened = NoteLibrary(loadingFrom: store, defaults: nil)
        await reopened.load()
        let reread = try #require(reopened.note(note.id))
        #expect(reread.file.property("type") == "example.task")
        #expect(reread.file.property("child-of") == "[[Parent]]")
        #expect(reread.file.property("custom") == "unchanged")
        #expect(reread.body == "Body\n")
    }

    @Test(arguments: ["example.project", "example.task", "example.decision"])
    func editingANestedTypedRecordKeepsItsEnvelopeAndConnections(type: String) async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let store = FolderStore(root: root.url, bin: bin.url)
        let path = "Records/Group/Original.md"
        let header = """
        ---
        type: \(type)
        title: Record title
        description: 'A description: with punctuation'
        status: open
        priority: high
        child-of: "[[Parent]]"
        related-to:
          - "[[One]]"
          - "[[Two]]"
        marfa_id: 00000000-0000-0000-0000-000000000001
        custom:
          threshold: 3
          tags: [first, second] # keep this spelling
        ---

        """
        let original = "\u{FEFF}" + (header + "## Outcome\n\nOriginal body.\n").replacingOccurrences(of: "\n", with: "\r\n")
        try root.write(original, to: path)
        let library = NoteLibrary(loadingFrom: store, defaults: nil)
        await library.load()
        let note = try #require(library.notes.first)
        let folder = try #require(library.folders.first)
        #expect(note.title == "Record title")
        #expect(note.file.text == original)
        #expect(note.directory == "Records/Group")
        #expect(library.notes(in: .folder(folder.id)).map(\.id) == [note.id])
        library.leave(note.id)
        store.drain()
        #expect(try Data(contentsOf: root.url.appending(path: path)) == Data(original.utf8), "opening and leaving must not rewrite a typed record")

        let editedBody = "## Outcome\n\nEdited body with [[Parent]].\n"
        library.updateBody(of: note.id, to: editedBody)
        library.leave(note.id)
        store.drain()
        let edited = "\u{FEFF}" + (header + editedBody).replacingOccurrences(of: "\n", with: "\r\n")
        #expect(try Data(contentsOf: root.url.appending(path: path)) == Data(edited.utf8))
        #expect(library.note(note.id)?.title == "Record title", "a body heading does not replace the explicit title")
        await library.reread()
        #expect(library.note(note.id)?.body == editedBody)
        #expect(library.note(note.id)?.file.text == edited)

        library.setPinned([note.id], true)
        library.setPinned([note.id], false)
        store.drain()
        #expect(try Data(contentsOf: root.url.appending(path: path)) == Data(edited.utf8))
        library.renameNote(note.id, to: "Renamed record")
        store.drain()
        #expect(!root.exists(path))
        let renamedPath = "Records/Group/Renamed record.md"
        let renamed = edited.replacingOccurrences(of: "title: Record title", with: "title: Renamed record")
        #expect(try Data(contentsOf: root.url.appending(path: renamedPath)) == Data(renamed.utf8))

        library.delete([note.id])
        store.drain()
        #expect(try store.load().trash.first?.note.text == renamed)
        library.recover([note.id])
        store.drain()
        #expect(try Data(contentsOf: root.url.appending(path: renamedPath)) == Data(renamed.utf8))
    }
}
