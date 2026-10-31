import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@Suite(.hangLimit)
struct FileDropTests {
    let disk = TestFiles()

    @Test func droppedFilesBecomeItemsAndAreSelected() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let ids = await browser.importFiles(
            [disk.url("one.txt"), disk.url("two.txt")], in: library, order: NoteOrder(), undoManager: nil)
        #expect(ids.count == 2)
        #expect(library.addedFiles.map(\.name) == ["one.txt", "two.txt"])
        #expect(browser.selection == Set(ids))
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func filesDroppedWhileACollectionIsShownJoinIt() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: NoteOrder())
        let ids = await browser.importFiles([disk.url("a.txt")], in: library, order: NoteOrder(), undoManager: nil)
        let added = try #require(ids.first)
        #expect(library.item(added)?.edgesOut.contains { $0.target == .item(collection.id) } == true)
    }

    @Test func filesDroppedOnACollectionJoinItWhereverTheWindowIs() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        let ids = await browser.importFiles([disk.url("a.txt")], into: collection.id, in: library, order: NoteOrder(), undoManager: nil)
        let added = try #require(ids.first)
        #expect(library.item(added)?.edgesOut.contains { $0.target == .item(collection.id) } == true)
        #expect(browser.selection == [added])
    }

    @Test func aFileThatCannotBeReadIsToldAndTheRestAreStillAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let missing = disk.directory.appending(path: "gone.txt")
        let ids = await browser.importFiles([missing, disk.url("kept.txt")], in: library, order: NoteOrder(), undoManager: nil)
        #expect(ids.count == 1)
        #expect(library.notices.waiting.count == 1)
    }

    @Test func nothingIsToldWhenNothingWasDropped() async {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let ids = await browser.importFiles([], in: library, order: NoteOrder(), undoManager: nil)
        #expect(ids.isEmpty)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aDraggedNoteLeavesAsAMarkdownFileNamedAfterIt() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans\n\nSome text")
        let reference = library.dragReference(of: note.id)
        #expect(reference.text == "# Plans\n\nSome text")
        let text = try #require(reference.text)
        let file = try #require(QuickLookFile.write(text, titled: reference.title, as: reference.type, in: "Drag-test", key: note.id.rawValue))
        defer { file.remove() }
        #expect(file.url.lastPathComponent == QuickLookFile.name(for: "Plans", type: .markdown))
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "# Plans\n\nSome text")
    }

    @Test func aDraggedFileItemFetchesItsFileOnlyWhenAskedFor() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let id = try #require(await library.addFile(disk.url("scan.txt", "contents"), title: nil, parentID: nil, in: .allNotes))
        library.files[id] = disk.url("kept")
        let reference = library.dragReference(of: id)
        #expect(library.fetches == 0)
        guard case .file(let fetch) = reference.content else { Issue.record("A file item carries its file."); return }
        #expect(try await fetch() == library.files[id])
        #expect(library.fetches == 1)
    }

    @Test func anItemDraggedToAnotherWindowArrivesAsItsIdentifierOnly() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans")
        let data = try JSONEncoder().encode(library.dragReference(of: note.id))
        let decoded = try JSONDecoder().decode(ItemReference.self, from: data)
        #expect(decoded.id == note.id)
        #expect(decoded.text == nil)
    }

    @Test func quickLookShowsANoteAsTextAndAFileAsItself() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans\n\nSome text")
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, in: .allNotes))
        library.files[fileID] = disk.url("kept", "file contents")
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [note.id, fileID]
        await browser.quickLookSelection(in: library)
        let request = try #require(browser.quickLook)
        #expect(request.urls.count == 2)
        let texts = try request.urls.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(Set(texts) == ["# Plans\n\nSome text", "file contents"])
        #expect(request.current == request.urls[0])
        browser.dismissQuickLook()
        #expect(browser.quickLook == nil)
        #expect(request.urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func quickLookTellsThePersonWhenTheFileCannotBeFetched() async throws {
        let library = FakeItemLibrary()
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, in: .allNotes))
        library.fetchFails = true
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [fileID]
        await browser.quickLookSelection(in: library)
        #expect(browser.quickLook == nil)
        #expect(library.notices.waiting.count == 1)
    }

    @Test func quickLookWithNothingSelectedDoesNothing() async {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        await browser.quickLookSelection(in: library)
        #expect(browser.quickLook == nil)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func quickLookIsOfferedOnlyWithASelection() {
        let library = FakeItemLibrary()
        let note = library.add("# Plans")
        let none = ItemCommandContext(library: library, ids: [], hasBrowser: true, pageItem: nil)
        let some = ItemCommandContext(library: library, ids: [note.id], hasBrowser: true, pageItem: note.id)
        #expect(!ItemCommand.quickLook.isEnabled(in: none))
        #expect(ItemCommand.quickLook.isEnabled(in: some))
    }
}
