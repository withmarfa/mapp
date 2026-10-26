import Foundation
import Testing
@testable import MAPP

/// Delete on a selection: what goes to Recently Deleted, what asks the person, and that erasing for good is never
/// offered by a command that also moves other items.
@MainActor
@Suite struct BrowserDeleteTests {
    private struct Fixture {
        let library: FakeItemLibrary
        let first: Item, second: Item, binned: Item, alsoBinned: Item
    }

    private func fixture(canPurge: Bool = true) -> Fixture {
        let first = FakeItemLibrary.note("First", modified: .now)
        let second = FakeItemLibrary.note("Second", modified: .now)
        let binned = FakeItemLibrary.note("Binned", modified: .now, state: .trashed)
        let alsoBinned = FakeItemLibrary.note("Also binned", modified: .now, state: .trashed)
        let library = FakeItemLibrary(items: [first, second, binned, alsoBinned])
        library.canPurge = canPurge
        return Fixture(library: library, first: first, second: second, binned: binned, alsoBinned: alsoBinned)
    }

    private func states(_ library: FakeItemLibrary) -> [ItemID: ItemState] {
        Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0.state) })
    }

    @Test(arguments: [true, false])
    func aMixedSelectionAsksOnceToMoveOnlyTheLiveItems(canPurge: Bool) {
        let f = fixture(canPurge: canPurge)
        let before = states(f.library)
        var asked: [Set<ItemID>] = []
        Browser.delete([f.first.id, f.second.id, f.binned.id], in: f.library, undoManager: nil, asking: { asked.append($0) })
        #expect(asked == [[f.first.id, f.second.id]], "one confirmation, naming only the live items")
        #expect(f.library.notesToPurge.isEmpty, "a command that also moves items never offers to erase")
        #expect(f.library.notices.told == 0)
        #expect(states(f.library) == before, "nothing changes until the person confirms")

        f.library.delete(asked[0], undoManager: nil)
        #expect(f.library.item(f.first.id)?.state == .trashed)
        #expect(f.library.item(f.second.id)?.state == .trashed)
        #expect(f.library.item(f.binned.id)?.state == .trashed, "the item already in the bin is neither erased nor touched")
        #expect(f.library.items.count == 4)
    }

    @Test func cancellingTheMoveLeavesEveryItemAsItWas() {
        let f = fixture()
        let before = states(f.library)
        Browser.delete([f.first.id, f.second.id, f.binned.id], in: f.library, undoManager: nil, asking: { _ in })
        #expect(states(f.library) == before)
        #expect(f.library.notesToPurge.isEmpty)
    }

    @Test func aSingleLiveItemInAMixedSelectionMovesWithoutAskingAndErasesNothing() {
        let f = fixture()
        var asked = false
        Browser.delete([f.first.id, f.binned.id], in: f.library, undoManager: nil, asking: { _ in asked = true })
        #expect(!asked)
        #expect(f.library.item(f.first.id)?.state == .trashed)
        #expect(f.library.item(f.binned.id)?.state == .trashed)
        #expect(f.library.notesToPurge.isEmpty)
        #expect(f.library.items.count == 4)
    }

    @Test func aSelectionOfOnlyBinnedItemsAsksToEraseThemAndMovesNothing() {
        let f = fixture()
        let before = states(f.library)
        var asked = false
        Browser.delete([f.binned.id, f.alsoBinned.id], in: f.library, undoManager: nil, asking: { _ in asked = true })
        #expect(f.library.notesToPurge == [f.binned.id, f.alsoBinned.id])
        #expect(!asked, "the move confirmation is not raised")
        #expect(states(f.library) == before, "nothing is erased until the person confirms")
        #expect(f.library.notices.told == 0)

        // Cancelling the erase dialog never calls the library, and the items stay.
        f.library.notesToPurge = []
        #expect(states(f.library) == before)

        f.library.deletePermanentlyOnConfirm([f.binned.id, f.alsoBinned.id])
        #expect(Set(f.library.items.map(\.id)) == [f.first.id, f.second.id])
    }

    @Test func aSelectionOfOnlyBinnedItemsTellsWhyWhenTheLibraryCannotEraseThem() {
        let f = fixture(canPurge: false)
        let before = states(f.library)
        Browser.delete([f.binned.id, f.alsoBinned.id], in: f.library, undoManager: nil)
        #expect(f.library.notesToPurge.isEmpty)
        #expect(states(f.library) == before)
        #expect(f.library.notices.waiting.last?.title == "Can’t Delete Immediately")
        #expect(f.library.notices.waiting.last?.message.contains("server") == true)
    }

    @Test func aLiveSelectionWithNothingToAskAboutMovesAtOnce() {
        let f = fixture()
        Browser.delete([f.first.id, f.second.id], in: f.library, undoManager: nil)
        #expect(f.library.item(f.first.id)?.state == .trashed)
        #expect(f.library.item(f.second.id)?.state == .trashed)
    }

    @Test func anEmptySelectionDoesNothing() {
        let f = fixture()
        let before = states(f.library)
        Browser.delete([], in: f.library, undoManager: nil, asking: { _ in Issue.record("asked about nothing") })
        #expect(states(f.library) == before)
        #expect(f.library.notesToPurge.isEmpty)
        #expect(f.library.notices.told == 0)
    }
}
