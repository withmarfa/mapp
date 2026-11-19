import Foundation
import Testing
@testable import MAPP

/// Where an item opens (Settings > Lists > Open Items In), and what the modal does with the window around it.
struct ItemOpeningTests {
    /// Defaults of the test's own, so a run never reads or writes the person's.
    private func defaults(_ stored: String? = nil) -> UserDefaults {
        let suite = UserDefaults(suiteName: "ItemOpeningTests.\(UUID().uuidString)")!
        if let stored { suite.set(stored, forKey: ListKey.openItemsIn) }
        return suite
    }

    private func browser(_ mode: ItemViewMode = .list) -> (Browser, FakeItemLibrary, [ItemID]) {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        browser.adopt(library)
        // Recents lists every item with a layout of its own, which All Items, an index, does not.
        browser.sidebarItem = .recents
        browser.viewMode = mode
        return (browser, library, library.items.map(\.id))
    }

    // MARK: The setting

    @Test func openingInAModalIsTheDefaultAndWhatIsStoredIsKept() {
        #expect(ItemOpening.stored(in: defaults()) == .modal)
        for way in ItemOpening.allCases {
            #expect(ItemOpening.stored(in: defaults(way.rawValue)) == way)
        }
        #expect(ItemOpening.stored(in: defaults("somethingElse")) == .modal, "a value this version does not know falls back")
    }

    @Test func aModalAndAFullPageTakeOneItemAndWindowsTakeAny() {
        #expect(!ItemOpening.modal.canOpen(0) && ItemOpening.modal.canOpen(1) && !ItemOpening.modal.canOpen(2))
        #expect(!ItemOpening.fullPage.canOpen(2))
        #expect(!ItemOpening.newWindow.canOpen(0) && ItemOpening.newWindow.canOpen(5))
    }

    // MARK: Routing

    @Test(arguments: ItemViewMode.allCases)
    func openFollowsTheSettingInEveryLayout(_ mode: ItemViewMode) {
        let (browser, _, ids) = browser(mode)
        var windows: [Set<ItemID>] = []
        browser.windowOpener = { windows.append($0) }

        #expect(browser.open([ids[0]], defaults: defaults("modal")))
        #expect(browser.modalItem == ids[0] && browser.selection == [ids[0]] && !browser.isCollectionItemPresented)
        browser.closeModal()

        #expect(browser.open([ids[1]], defaults: defaults("fullPage")))
        #expect(browser.isCollectionItemPresented && browser.modalItem == nil && browser.selection == [ids[1]])
        browser.returnToCollection()

        #expect(browser.open([ids[2]], defaults: defaults("newWindow")))
        #expect(windows == [[ids[2]]] && browser.modalItem == nil && !browser.isCollectionItemPresented)
    }

    @Test func severalItemsOpenOnlyInWindows() {
        let (browser, _, ids) = browser(.table)
        var windows: [Set<ItemID>] = []
        browser.windowOpener = { windows.append($0) }
        let two: Set<ItemID> = [ids[0], ids[1]]
        #expect(!browser.open(two, defaults: defaults("modal")))
        #expect(!browser.open(two, defaults: defaults("fullPage")))
        #expect(!browser.isModalPresented && !browser.isCollectionItemPresented && windows.isEmpty)
        #expect(browser.open(two, defaults: defaults("newWindow")))
        #expect(windows == [two])
    }

    @Test func aModalOpenedOverAFullPageGoesBackToTheLayoutFirst() {
        let (browser, _, ids) = browser(.gallery)
        browser.open([ids[0]], as: .fullPage)
        browser.open([ids[1]], as: .modal)
        #expect(browser.modalItem == ids[1] && !browser.isCollectionItemPresented && browser.showsCollection)
    }

    @Test func theSettingChangedWhileAModalIsOpenLeavesItOpen() {
        let (browser, _, ids) = browser()
        let settings = defaults("modal")
        browser.open([ids[0]], defaults: settings)
        settings.set("newWindow", forKey: ListKey.openItemsIn)
        #expect(browser.modalItem == ids[0])
    }

    // MARK: The modal's end

    @Test func theModalEndsWhenAnotherItemOrPlaceOrLayoutOrSettingsTakesTheWindow() {
        for leave in [
            { (browser: Browser, id: ItemID) in browser.selection = [id] },
            { browser, _ in browser.sidebarItem = .favorites },
            { browser, _ in browser.viewMode = .table },
            { browser, _ in browser.showSettings() },
        ] {
            let (browser, _, ids) = browser()
            browser.open([ids[0]], as: .modal)
            leave(browser, ids[1])
            #expect(!browser.isModalPresented)
        }
    }

    @Test func aModalReachedByALinkStaysAModal() {
        let (browser, library, ids) = browser(.table)
        browser.open([ids[0]], as: .modal)
        browser.reveal(library.item(ids[1])!, in: library, order: ItemOrder())
        #expect(browser.modalItem == ids[1] && browser.selection == [ids[1]])
    }

    // MARK: Up and down

    @Test func theNeighboursAreNilAtTheEndsAndWhenTheItemLeft() {
        let order = (0..<3).map { _ in ItemID.mint() }
        #expect(ListNeighbors(of: order[0], in: order).previous == nil)
        #expect(ListNeighbors(of: order[0], in: order).next == order[1])
        #expect(ListNeighbors(of: order[1], in: order).previous == order[0])
        #expect(ListNeighbors(of: order[1], in: order).next == order[2])
        #expect(ListNeighbors(of: order[2], in: order).next == nil)
        // Taken out of the list behind, the item has no neighbour either way, and never a wrong one.
        let left = ListNeighbors(of: order[1], in: [order[0], order[2]])
        #expect(left.previous == nil && left.next == nil)
    }

    @Test func theArrowsMoveTheModalAndTheSelectionTogetherAndStopAtTheEnds() {
        let (browser, library, _) = browser()
        let order = browser.orderBehind(in: library, order: ItemOrder())
        #expect(order.count == 3)
        browser.open([order[0]], as: .modal)
        browser.moveModal(.previous, in: library, order: ItemOrder())
        #expect(browser.modalItem == order[0], "nothing is before the first item")
        browser.moveModal(.next, in: library, order: ItemOrder())
        #expect(browser.modalItem == order[1] && browser.selection == [order[1]])
        browser.moveModal(.next, in: library, order: ItemOrder())
        browser.moveModal(.next, in: library, order: ItemOrder())
        #expect(browser.modalItem == order[2] && browser.isModalPresented, "nothing is after the last item")
    }

    @Test func anItemRemovedBehindTheModalLeavesItWithNoNeighbours() {
        let (browser, library, _) = browser()
        let order = browser.orderBehind(in: library, order: ItemOrder())
        browser.open([order[1]], as: .modal)
        library.items.removeAll { $0.id == order[1] }
        let neighbors = browser.modalNeighbors(in: library, order: ItemOrder())
        #expect(neighbors.previous == nil && neighbors.next == nil)
    }

    @Test func steppingThroughTheListBehindTheModalAddsNoStepToBack() {
        let (browser, library, _) = browser()
        let order = browser.orderBehind(in: library, order: ItemOrder())
        browser.selection = [order[0]]
        browser.open([order[1]], as: .modal)
        #expect(browser.history.entries.map(\.id) == [order[0], order[1]], "opening adds one step")
        browser.moveModal(.next, in: library, order: ItemOrder())
        browser.moveModal(.previous, in: library, order: ItemOrder())
        browser.moveModal(.previous, in: library, order: ItemOrder())
        #expect(browser.selection == [order[0]] && browser.modalItem == order[0])
        #expect(browser.history.entries.map(\.id) == [order[0], order[1]])
    }

    // MARK: Search and the selection under a full page

    @Test(arguments: ItemViewMode.allCases)
    func searchPutsAFullPageAndTheModalAwayInEveryLayout(_ mode: ItemViewMode) {
        for way in [ItemOpening.fullPage, .modal] {
            let (browser, _, ids) = browser(mode)
            browser.open([ids[0]], as: way)
            browser.showSearchField()
            #expect(!browser.isCollectionItemPresented && !browser.isModalPresented)
            #expect(browser.isSearchExpanded && browser.searchFocusRequests == 1)
        }
    }

    @Test func theSelectionFollowsTheListWhenItsFullPageIsOpenFromTheList() {
        let (browser, library, _) = browser()
        let order = browser.orderBehind(in: library, order: ItemOrder())
        browser.open([order[1]], as: .fullPage)
        let before = browser.collectionItemIDs(in: library, order: ItemOrder())
        #expect(before == order)
        library.items.removeAll { $0.id == order[1] }
        browser.collectionItemsChanged(from: before, to: browser.collectionItemIDs(in: library, order: ItemOrder()))
        #expect(browser.selection == [order[2]], "the next item in the list's own order")
    }

    @Test func theListKeepsItsOwnSelectionWhenNoFullPageIsOpen() {
        let (browser, library, _) = browser()
        let order = browser.orderBehind(in: library, order: ItemOrder())
        browser.selection = [order[1]]
        library.items.removeAll { $0.id == order[1] }
        browser.collectionItemsChanged(from: order, to: [])
        #expect(browser.selection == [order[1]])
    }

    // MARK: The row menu

    @Test func theRowMenuHasOneOrderWhereverItIsOpened() {
        #expect(RowMenuEntry.entries(opening: .modal, inBin: false) == [
            .open, .openAs(.fullPage), .openAs(.newWindow),
            .divider, .quickLook, .share,
            .divider, .favorite, .tag, .collection, .layoutActions, .changeType, .customizeLayout, .versionHistory,
            .divider, .delete,
        ])
        #expect(RowMenuEntry.entries(opening: .newWindow, inBin: false).prefix(3) == [.open, .openAs(.modal), .openAs(.fullPage)])
        #expect(RowMenuEntry.entries(opening: .fullPage, inBin: false).prefix(3) == [.open, .openAs(.modal), .openAs(.newWindow)])
    }

    @Test func theRowMenuOfDeletedItemsRecoversInsteadOfOrganizing() {
        let entries = RowMenuEntry.entries(opening: .modal, inBin: true)
        #expect(entries.contains(.recover) && !entries.contains(.favorite) && !entries.contains(.tag))
        #expect(entries.last == .delete)
    }
}
