import Foundation
import Testing
@testable import MarfaMac

/// Add Attachment, a drop or a paste of files on an item's page, asking first about files already in Marfa.
extension EditorTests {
    /// A library holding the item on the page first, then an item whose bytes match every file named `shot.png`.
    func attachingLibrary() -> (FakeItemLibrary, found: Item) {
        let found = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now), found])
        library.sameBytes = AlreadyInMarfaTests.answering(["shot.png": [found]])
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/other.png", name: "other")]) }
        return (library, found)
    }

    @Test func attachingAFileAlreadyInMarfaAsksAndCancelAttachesNothing() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        #expect(editor.alreadyInMarfa.question?.title == "1 of 2 Files Are Already in Marfa")
        editor.alreadyInMarfa.answer(.cancel)
        // Time for an attach made after Cancel to reach the library, which nothing signals when none is made.
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty)
        #expect(try await markdown(editor) == nil)
    }

    @Test func attachingWithOpenAttachesTheRestThenOpensTheMatchedItem() async throws {
        let disk = TestFiles()
        let (library, found) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        editor.onOpenFound = { opened = $0 }
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { !opened.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["other.png"]])
        #expect(opened == [found.id])
        #expect(try await markdown(editor)?.contains("Attachments/other.png") == true, "the rest were placed before the item opened")
    }

    @Test func attachingWithAddAnywayAttachesEveryFile() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))] + Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.addAnyway)
        try #require(await eventually { !library.attachedBatches.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["shot.png", "other.png", "Photo.png"]])
    }

    @Test func pastedBytesAndUnmatchedFilesAreAttachedUnasked() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("other.png"))] + Self.pasted))
        try #require(await eventually { !library.attachedBatches.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["other.png", "Photo.png"]])
        #expect(library.askedSameBytes.map { $0.map(\.lastPathComponent) } == [["other.png"]], "only files are checked")
        #expect(editor.alreadyInMarfa.question == nil)
    }
}
