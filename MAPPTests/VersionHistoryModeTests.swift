import Foundation
import Synchronization
import Testing
@testable import MAPP

private func snapshot(_ version: Int, body: String) -> ItemSnapshot {
    ItemSnapshot(id: "v\(version)", version: version, type: TypeChangeFixture.note, properties: ["body": .string(body)], replaced: nil, writer: nil)
}

private func page(_ snapshots: [ItemSnapshot]) -> Result<ItemHistoryPage, ItemHistoryFailure> {
    .success(ItemHistoryPage(snapshots: snapshots, next: nil))
}

/// A window entering and leaving Version History, and what Restore Version does there.
@MainActor
@Suite(.hangLimit) struct VersionHistoryModeTests {
    private func library(_ answers: [Result<ItemHistoryPage, ItemHistoryFailure>]?) -> (FakeItemLibrary, Item, FakeHistory?) {
        let library = FakeItemLibrary(items: [])
        library.catalogue = TypeChangeFixture.catalogue
        let note = library.add("Agenda")
        let source = answers.map { FakeHistory($0) }
        library.history = source
        return (library, note, source)
    }

    @Test func enteringShowsTheModeAndReadsTheVersions() async throws {
        let (library, note, _) = library([page([snapshot(1, body: "First"), snapshot(2, body: "Second")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(mode.item == note.id)
        #expect(await eventually { mode.thread.phase == .loaded })
        let list = try #require(mode.list(in: library))
        // The newest version before the item as it is now is the one shown first.
        #expect(list.entries.map(\.version).count == 3)
        mode.chooseDefault(in: list)
        #expect(mode.thread.selection == "v2")
        // Choosing again keeps the person's own choice.
        mode.thread.selection = "v1"
        mode.chooseDefault(in: list)
        #expect(mode.thread.selection == "v1")
    }

    @Test func openingItAgainWhileItIsOpenChangesNothing() async throws {
        let (library, note, source) = library([page([snapshot(1, body: "First")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let first = try #require(details.history)
        #expect(await eventually { first.thread.phase == .loaded })
        details.showHistory(of: note.id, in: library)
        #expect(details.history === first)
        #expect(source?.cursors.withLock { $0.count } == 1)
    }

    @Test func leavingClearsTheModeAndStopsReading() async throws {
        let (library, note, _) = library([page([snapshot(1, body: "First")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        #expect(details.history != nil)
        details.leaveHistory()
        #expect(details.history == nil)
        // Leaving a window that shows no history is nothing.
        details.leaveHistory()
        #expect(details.history == nil)
    }

    @Test func aLibraryWithNoHistoryOpensWithTheReasonAndStillLeaves() async throws {
        let (library, note, _) = library(nil)
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .failed(.unsupported) })
        #expect(mode.restoreCheck(in: library) == nil)
        #expect(!mode.canRestore(in: library))
        details.leaveHistory()
        #expect(details.history == nil)
    }

    @Test func aFailedLoadKeepsTheModeAndCanBeTriedAgain() async throws {
        let (library, note, source) = library([.failure(.unreachable)])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .failed(.unreachable) })
        source?.set([page([snapshot(1, body: "First")])])
        mode.thread.load()
        #expect(await eventually { mode.thread.phase == .loaded })
        #expect(mode.list(in: library)?.entries.count == 2)
    }

    @Test func restoringAVersionWritesItAndLeavesTheMode() async throws {
        let (library, note, _) = library([page([snapshot(1, body: "First")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .loaded })
        mode.thread.selection = "v1"
        #expect(mode.canRestore(in: library))
        details.restoreFromHistory(in: library, undoManager: nil)
        #expect(await eventually { details.history == nil })
        #expect(library.restored.map(\.snapshot.id) == ["v1"])
        #expect(library.body(of: note.id)?.text == "First")
    }

    @Test func restoreIsDimmedForTheItemAsItIsAndForAVersionItAlreadyHolds() async throws {
        let (library, note, _) = library([page([snapshot(1, body: "Agenda"), snapshot(2, body: "Other")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .loaded })
        mode.thread.selection = VersionEntry.currentID
        #expect(!mode.canRestore(in: library))
        mode.thread.selection = "v1"
        #expect(mode.restoreCheck(in: library) == .unchanged)
        #expect(!mode.canRestore(in: library))
        #expect(VersionHistoryMode.reason(for: .unchanged) != nil)
        mode.thread.selection = "v2"
        #expect(mode.canRestore(in: library))
        #expect(VersionHistoryMode.reason(for: mode.restoreCheck(in: library)) == nil)
        // Restoring what cannot be restored sends nothing and leaves the mode open.
        mode.thread.selection = "v1"
        details.restoreFromHistory(in: library, undoManager: nil)
        #expect(details.history === mode)
        #expect(library.restored.isEmpty)
    }

    @Test func anItemInRecentlyDeletedCanBeReadButNotRestored() async throws {
        let library = FakeItemLibrary(items: [])
        library.catalogue = TypeChangeFixture.catalogue
        let gone = library.add("Gone", state: .trashed)
        library.history = FakeHistory([page([snapshot(1, body: "Older")])])
        let details = DetailsPresentation()
        details.showHistory(of: gone.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .loaded })
        mode.thread.selection = "v1"
        guard case .unavailable(let reason)? = mode.restoreCheck(in: library) else {
            Issue.record("restorable in Recently Deleted")
            return
        }
        #expect(VersionHistoryMode.reason(for: .unavailable(reason)) == reason)
        details.restoreFromHistory(in: library, undoManager: nil)
        #expect(details.history === mode)
        #expect(library.restored.isEmpty)
    }

    @Test func anItemThatIsGoneLeavesNoThreadToShow() async throws {
        let (library, note, _) = library([page([snapshot(1, body: "First")])])
        let details = DetailsPresentation()
        details.showHistory(of: note.id, in: library)
        let mode = try #require(details.history)
        #expect(await eventually { mode.thread.phase == .loaded })
        #expect(mode.list(in: library) != nil)
        // The window leaves when the list is nil.
        let other = FakeItemLibrary(items: [])
        #expect(mode.list(in: other) == nil)
        mode.thread.selection = "v1"
        #expect(!mode.canRestore(in: other))
    }
}
