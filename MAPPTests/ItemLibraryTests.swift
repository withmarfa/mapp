import Foundation
import Observation
import os
import Testing
@testable import MAPP

/// The views hold a library as `any ItemLibrary`, so what they read through it must still be observed.
@MainActor
struct ItemLibraryTests {
    typealias F = LibraryFixture

    /// A Marfa library over a source the test drives, with the fixture's items read.
    func loaded() async throws -> (library: any ItemLibrary, source: FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// Starts following what `read` touches, and reports whether a change to it has come since.
    func follow(_ read: () -> Void) -> () -> Bool {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking(read) { changed.withLock { $0 = true } }
        return { changed.withLock { $0 } }
    }

    @Test func readsThroughTheProtocolAreRedrawnWhenTheCopyChanges() async throws {
        let (library, source) = try await loaded()
        var item = try #require(library.item(F.n1))
        item.title = "Changed"
        item.version = ItemVersion(2)
        let list = follow { _ = library.items(in: .allNotes) }
        let one = follow { _ = library.item(F.n1) }
        source.send(.upserted([item]))
        #expect(await eventually { list() && one() })
        let notice = follow { _ = library.notices.waiting.last }
        library.notices.tell("Title", "Message")
        #expect(notice())
    }

    @Test func aReadNotTouchedByAChangeIsLeftAlone() async throws {
        let (library, source) = try await loaded()
        var item = try #require(library.item(F.n1))
        item.title = "Changed"
        item.version = ItemVersion(2)
        let notice = follow { _ = library.notices.waiting.last }
        source.send(.upserted([item]))
        try #require(await eventually { library.item(F.n1)?.title == "Changed" })
        #expect(!notice())
    }

    @Test func anEraseConfirmedAfterTheLibraryCanNoLongerEraseLeavesTheItemsAndSaysSo() {
        let trashed = FakeItemLibrary.note("Old", modified: .now, state: .trashed)
        let library = FakeItemLibrary(items: [trashed])
        library.canPurge = true
        Browser.delete([trashed.id], in: library, undoManager: nil)
        #expect(library.notesToPurge == [trashed.id], "the person is asked while the library can erase")
        library.canPurge = false
        library.deletePermanentlyOnConfirm([trashed.id])
        #expect(library.item(trashed.id) != nil, "nothing is erased once the library cannot")
        #expect(library.notices.waiting.last?.title == "Can’t Delete Immediately")
        #expect(library.notices.waiting.last?.message == "Deleting for good needs the server, which can’t be reached right now. The items are still in Recently Deleted.")
        library.notices.answerAll()
        library.canPurge = true
        library.deletePermanentlyOnConfirm([trashed.id])
        #expect(library.item(trashed.id) == nil)
        #expect(library.notices.waiting.last == nil)
    }
}
