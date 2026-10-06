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

    @Test func theFilesLibraryMovesAndPurgesButNeitherArchivesNorSends() {
        let library: any ItemLibrary = NoteLibrary(notes: [], now: { start })
        #expect(library.capabilities == [.move, .purge])
        #expect(library.trashDays == NoteLibrary.trashDays)
        #expect(library.syncReport.waiting == 0 && library.syncReport.problems.isEmpty && library.syncReport.queueRead)
        #expect(library.folderURL == nil, "a library with no folder store has no folder")
    }

    @Test func aFolderStoreGivesTheLibraryItsFolder() throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let library: any ItemLibrary = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        #expect(library.folderURL == root.url)
    }
}
