import Foundation
import Testing
@testable import MarfaMac

/// Where an item opens (Settings > General > Open Items), and what the modal does with the window around it.
struct ItemOpeningTests {
    // MARK: What is stored

    @Test func whatAPersonChoseIsKeptAndNothingStoredOpensBesideTheList() {
        let defaults = ThrowawayDefaults.make("ItemOpeningTests")
        #expect(ItemOpening.stored(in: defaults) == .besideList)
        for way in ItemOpening.allCases {
            defaults.set(way.rawValue, forKey: ListKey.openItemsIn)
            #expect(ItemOpening.stored(in: defaults) == way)
        }
    }

    @Test func aWordThisCopyDoesNotKnowIsReadAsTheStandardAndLeftStored() {
        let defaults = ThrowawayDefaults.make("ItemOpeningTests")
        defaults.set("aLaterWay", forKey: ListKey.openItemsIn)
        #expect(ItemOpening.stored(in: defaults) == .besideList)
        #expect(defaults.string(forKey: ListKey.openItemsIn) == "aLaterWay")
    }

    // MARK: Keep in the modal

    @Test @MainActor func keepMovesOnOnlyOnceTheMoveIsQueuedForTheItem() {
        let library = FakeItemLibrary()
        let kept = FakeItemLibrary.note("From the Feed", modified: .now, tier: .feed)
        let binned = FakeItemLibrary.note("Binned", modified: .now, tier: .feed, state: .trashed)
        library.items += [kept, binned]
        var movedOn: [ItemID] = []

        PageKeepButton.keep(binned.id, in: library, undoManager: nil, details: nil) { movedOn.append(binned.id) }
        #expect(movedOn.isEmpty, "a refused move leaves the modal on the item")
        #expect(library.item(binned.id)?.tier == .feed)

        PageKeepButton.keep(kept.id, in: library, undoManager: nil, details: nil) { movedOn.append(kept.id) }
        #expect(movedOn == [kept.id])
        #expect(library.item(kept.id)?.tier == .library)
    }

    // MARK: The column beside a layout

    @Test @MainActor func theWindowHoldsAPageOnlyWhileTheColumnBesideALayoutShowsIt() {
        let browser = Browser()
        browser.showing = .sources
        let table = UUID(), items = UUID()
        #expect(!browser.showsBesideColumn && !browser.showsPage, "an index with no column shows no page")
        browser.columnBeside(table, isShown: true)
        #expect(browser.showsBesideColumn && browser.showsPage)

        // The window leaves for Sources, Collections or Version History, which unmount the column.
        browser.columnBeside(table, isShown: false)
        #expect(!browser.showsBesideColumn && !browser.showsPage, "no menu acts on a page that is not on screen")

        // The next layout's column mounts before the last one's goes: the old one cannot clear the new one's claim.
        browser.columnBeside(table, isShown: true)
        browser.columnBeside(items, isShown: true)
        browser.columnBeside(table, isShown: false)
        #expect(browser.showsBesideColumn)
        browser.columnBeside(items, isShown: false)
        #expect(!browser.showsBesideColumn)
    }

    // MARK: The modal's card

    @Test func theModalCardIs1020By788InAWindow1440By900AndKeepsItsMarginsAsTheWindowGrows() {
        #expect(ItemModal.cardSize(in: CGSize(width: 1440, height: 900)) == CGSize(width: 1020, height: 788))
        #expect(ItemModal.cardSize(in: CGSize(width: 1920, height: 1080)) == CGSize(width: 1500, height: 968))
        #expect(ItemModal.cardSize(in: CGSize(width: 720, height: 600)) == CGSize(width: 510, height: 488), "a narrower window keeps the card's share")
    }

    // MARK: The row menu

    @Test func theRowMenuOfDeletedItemsRecoversInsteadOfOrganizing() {
        let entries = RowMenuEntry.entries(opening: .modal, inBin: true)
        #expect(entries.contains(.recover) && !entries.contains(.favorite) && !entries.contains(.tag))
        #expect(entries.contains(.copyLink))
        #expect(entries.last == .delete)
    }

    @Test func theMovesEndTheMenuBeforeDelete() {
        let entries = RowMenuEntry.entries(opening: .modal, inBin: false)
        #expect(Array(entries.suffix(3)) == [.divider, .moves, .delete])
        #expect(!RowMenuEntry.entries(opening: .modal, inBin: true).contains(.moves))
    }
}
