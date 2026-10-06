import Foundation
import Observation
import os
import Testing
@testable import MAPP

/// The views hold a library as `any ItemLibrary`, so what they read through it must still be observed.
struct ItemLibraryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Whether a change to anything `read` touched would redraw a view that read it.
    func invalidates(_ read: () -> Void, when change: () -> Void) -> Bool {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking(read) { changed.withLock { $0 = true } }
        change()
        return changed.withLock { $0 }
    }

    @Test func aListReadThroughTheProtocolIsRedrawnWhenANoteChanges() {
        let note = Note(body: "# Plan", created: start)
        let files = NoteLibrary(notes: [note], now: { start })
        let library: any ItemLibrary = files
        #expect(invalidates({ _ = library.items(in: .allNotes) }, when: { files.updateBody(of: note.id, to: "# Plan\n\nMore\n") }))
        #expect(invalidates({ _ = library.item(note.id) }, when: { library.setFavorite([note.id], true, undoManager: nil) }))
        #expect(invalidates({ _ = library.count(in: .recentlyDeleted) }, when: { library.delete([note.id], undoManager: nil) }))
    }

    @Test func folderAndStateReadsThroughTheProtocolAreRedrawn() {
        let files = NoteLibrary(notes: [], now: { start })
        let library: any ItemLibrary = files
        #expect(invalidates({ _ = library.folders }, when: { library.newFolder(undoManager: nil) }))
        #expect(invalidates({ _ = library.failure }, when: { library.failure = ("Title", "Message") }))
    }

    @Test func aReadNotTouchedByAChangeIsLeftAlone() {
        let note = Note(body: "# Plan", created: start)
        let library: any ItemLibrary = NoteLibrary(notes: [note], now: { start })
        #expect(!invalidates({ _ = library.folders }, when: { library.updateBody(of: note.id, to: "# Plan\n\nMore\n") }))
    }

    @Test func theFilesLibraryOffersEveryFilesCommandButNeitherArchivesNorSends() async throws {
        let library: any ItemLibrary = NoteLibrary(notes: [], now: { start })
        #expect(library.capabilities == [.move, .purge, .renameFiles, .folders, .importFiles])
        #expect(library.trashDays == NoteLibrary.trashDays)
        #expect(library.syncReport.waiting == 0 && library.syncReport.problems.isEmpty && library.syncReport.queueRead)
        #expect(try await !library.resolve(.write("w1"), by: .discard), "a folder has no problems to resolve")
        #expect(library.folderURL == nil, "a library with no folder store has no folder")
    }

    // MARK: What each library offers

    static let everything: SourceCapabilities = [.archive, .purge, .move, .retype, .retier, .renameFiles, .folders, .importFiles]

    @Test func renameNoteNamesAFileOnlyWhereTheLibraryHasFiles() {
        let note = FakeItemLibrary.note("Plan", modified: start)
        let trashed = FakeItemLibrary.note("Old", modified: start, state: .trashed)
        let library = FakeItemLibrary(items: [note, trashed])
        #expect(!library.canRenameFile(of: note), "a library without files offers no Rename Note")
        library.capabilities = Self.everything
        #expect(library.canRenameFile(of: note))
        #expect(!library.canRenameFile(of: trashed), "a deleted note is not renamed")
        #expect(!library.canRenameFile(of: nil))
    }

    @Test func aTitleIsEditedAsAPropertyWhereFilesCannotBeRenamed() throws {
        let note = Note(body: "# Plan", path: "Plan.md", created: start)
        let library = NoteLibrary(notes: [note], now: { start })
        let item = try #require(library.item(note.id))
        #expect(library.setItemProperty(note.id, key: "title", value: .string("Roadmap"), undoManager: nil))
        #expect(library.item(note.id)?.title == "Roadmap")
        #expect(item.isEditable, "retitling needs only an editable item, not the rename capability")
    }

    // MARK: Files

    @Test func aFileItemsURLIsTheSameWhetherAskedAtOnceOrAwaited() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        try root.write("png", to: "Photo.png")
        let files = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        await files.load()
        let library: any ItemLibrary = files
        let file = try #require(library.items(in: .files).first)
        let url = try #require(library.fileURL(for: file.id))
        #expect(try await library.fileURL(of: file.id) == url)
    }

    @Test func aFolderStoreGivesTheLibraryItsFolder() throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let library: any ItemLibrary = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        #expect(library.folderURL == root.url)
    }
}
