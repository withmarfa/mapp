import Foundation
import Testing

@testable import MAPP

@MainActor
struct SidebarBlocksTests {
    // MARK: Blocks

    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now), FakeItemLibrary.note("Two", modified: .now)])
        library.views = [LibraryView(id: ItemID("view-1"), title: "Open work"), LibraryView(id: ItemID("view-2"), title: "Reading")]
        return library
    }

    private let viewOne = ItemID("view-1")
    private let viewTwo = ItemID("view-2")

    @Test func everyBlockShowsByDefault() {
        let blocks = SidebarPlan(library(), layout: SidebarLayout())
        #expect(blocks.shownDestinations == [.all, .sources, .collections])
        #expect(blocks.shownBuiltInViews == [.inbox, .recents, .favorites])
        #expect(blocks.shownSavedViews.map(\.id) == [viewOne, viewTwo])
        #expect(blocks.showsTypes)
        #expect(blocks.showsViews)
    }

    @Test func aBuiltInViewSwitchedOffLeavesTheBlock() {
        var layout = SidebarLayout()
        layout.setHidden(.recents, true)
        layout.setHidden(.sources, true)
        let blocks = SidebarPlan(library(), layout: layout)
        #expect(blocks.shownBuiltInViews == [.inbox, .favorites])
        #expect(blocks.shownDestinations == [.all, .collections])
        #expect(blocks.shownSavedViews.count == 2)
    }

    @Test func theViewsBlockStaysOnSavedViewsOnceAllThreeBuiltInsAreOff() {
        var layout = SidebarLayout()
        for place in [SidebarPlace.inbox, .recents, .favorites] { layout.setHidden(place, true) }
        let blocks = SidebarPlan(library(), layout: layout)
        #expect(blocks.shownBuiltInViews.isEmpty)
        #expect(blocks.showsViews)
    }

    @Test func theViewsBlockStaysOnBuiltInsWhenShowViewsIsOffOrThereAreNoSavedViews() {
        var layout = SidebarLayout()
        layout.setHidden(.views, true)
        var blocks = SidebarPlan(library(), layout: layout)
        #expect(blocks.shownSavedViews.isEmpty)
        #expect(blocks.shownBuiltInViews == [.inbox, .recents, .favorites])
        #expect(blocks.showsViews)

        let bare = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        blocks = SidebarPlan(bare, layout: SidebarLayout())
        #expect(blocks.shownSavedViews.isEmpty)
        #expect(blocks.showsViews)
    }

    @Test func theViewsBlockIsGoneOnlyWhenEveryBuiltInAndSavedViewIsOff() {
        var layout = SidebarLayout()
        for place in [SidebarPlace.inbox, .recents, .favorites] { layout.setHidden(place, true) }
        layout.setHidden(.view(viewOne), true)
        #expect(SidebarPlan(library(), layout: layout).showsViews)
        layout.setHidden(.view(viewTwo), true)
        #expect(!SidebarPlan(library(), layout: layout).showsViews)

        // Show Views off with the built-ins off as well leaves nothing.
        layout.setHidden(.view(viewOne), false)
        layout.setHidden(.view(viewTwo), false)
        layout.setHidden(.views, true)
        #expect(!SidebarPlan(library(), layout: layout).showsViews)
    }

    @Test func theTypesBlockFollowsItsSwitchAndSavedViewsKeepTheirOrder() {
        var layout = SidebarLayout()
        layout.setHidden(.types, true)
        layout.move([SidebarPlace.view(viewOne), .view(viewTwo)], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let blocks = SidebarPlan(library(), layout: layout)
        #expect(!blocks.showsTypes)
        #expect(blocks.shownSavedViews.map(\.id) == [viewTwo, viewOne])
    }

    // MARK: Six types

    private func node(_ id: String, children: [TypeNode] = []) -> TypeNode {
        TypeNode(id: id, type: TypeID(id), label: id, icon: nil, count: 1, total: 1, children: children)
    }

    /// The rows of `nodes` with every subtype row shown, as the sidebar draws them folded open.
    private func rows(_ nodes: [TypeNode], depth: Int = 0) -> [SidebarPlan.TypeRow] {
        nodes.flatMap { [SidebarPlan.TypeRow(node: $0, depth: depth, isExpanded: true)] + rows($0.children, depth: depth + 1) }
    }

    @Test func sixTypesOrFewerShowInFullWithNothingToExpand() {
        let all = rows((1...6).map { node("t\($0)") })
        let result = SidebarPlan.limited(all, showsAll: false)
        #expect(result.rows.map(\.id) == all.map(\.id))
        #expect(!result.hasMore)
        #expect(!SidebarPlan.limited([], showsAll: false).hasMore)
    }

    @Test func moreThanSixTypesShowSixUntilShowMore() {
        let all = rows((1...9).map { node("t\($0)") })
        let result = SidebarPlan.limited(all, showsAll: false)
        #expect(result.rows.map(\.id) == (1...6).map { "t\($0)" })
        #expect(result.hasMore)
    }

    @Test func showMoreRevealsTheRestAndStillOffersShowLess() {
        let all = rows((1...9).map { node("t\($0)") })
        let result = SidebarPlan.limited(all, showsAll: true)
        #expect(result.rows.count == 9)
        #expect(result.hasMore)
    }

    @Test func aTypeKeepsItsSubtypeRowsAndTheyDoNotCountTowardsSix() {
        let kids = [node("a.1"), node("a.2"), node("a.3")]
        let all = rows([node("a", children: kids)] + (2...8).map { node("t\($0)") })
        let result = SidebarPlan.limited(all, showsAll: false)
        // Six top-level types: a and t2 to t6, with a's three subtypes under it.
        #expect(result.rows.map(\.id) == ["a", "a.1", "a.2", "a.3", "t2", "t3", "t4", "t5", "t6"])
        #expect(result.hasMore)
    }

    @Test func aFoldedTypeCountsOnceAndHidesItsSubtypeRows() {
        let kids = [node("a.1"), node("a.2")]
        var all = rows([node("a", children: kids)] + (2...7).map { node("t\($0)") })
        all.removeAll { $0.depth > 0 }
        all[0] = SidebarPlan.TypeRow(node: all[0].node, depth: 0, isExpanded: false)
        let result = SidebarPlan.limited(all, showsAll: false)
        #expect(result.rows.map(\.id) == ["a", "t2", "t3", "t4", "t5", "t6"])
        #expect(result.hasMore)
    }

    // MARK: Landing

    private func browser(_ item: SidebarItem, mode: ItemViewMode) -> Browser {
        let browser = Browser()
        browser.sidebarItem = item
        browser.viewMode = mode
        return browser
    }

    @Test func theRowOfChipsStandsAboveItemsInALayoutThatSpansTheWindow() {
        for mode in [ItemViewMode.gallery, .table, .board, .timeline] {
            #expect(browser(.allNotes, mode: mode).offersNewItemChips)
        }
        #expect(!browser(.allNotes, mode: .list).offersNewItemChips)
    }

    @Test func theRowOfChipsStandsAboveTheSourcesAndCollectionsIndexes() {
        #expect(browser(.sources, mode: .list).offersNewItemChips)
        #expect(browser(.collections, mode: .gallery).offersNewItemChips)
    }

    @Test func theRowOfChipsLeavesWhenAnItemOpensOrAnotherPlaceShows() {
        let items = browser(.allNotes, mode: .gallery)
        items.isCollectionItemPresented = true
        #expect(!items.offersNewItemChips)
        items.returnToCollection()
        #expect(items.offersNewItemChips)
        #expect(!browser(.recents, mode: .gallery).offersNewItemChips)
        #expect(!browser(.itemType("core.note"), mode: .table).offersNewItemChips)
    }

    @Test func settingsHasNoRowOfChips() {
        let items = browser(.allNotes, mode: .gallery)
        items.showSettings()
        #expect(!items.offersNewItemChips)
        items.leaveSettings()
        #expect(items.offersNewItemChips)
    }

    @Test func choosingItemsMovesAWindowOnTheListToTheGalleryAndLeavesAnotherLayoutBe() {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        let onList = browser(.recents, mode: .list)
        onList.choose(.allNotes, in: library, order: NoteOrder())
        #expect(onList.item == .allNotes)
        #expect(onList.viewMode == .gallery)
        let onTable = browser(.recents, mode: .table)
        onTable.choose(.allNotes, in: library, order: NoteOrder())
        #expect(onTable.viewMode == .table)
        #expect(onTable.offersNewItemChips)
    }

    // MARK: Chips

    private func option(_ id: String) -> ItemTypeOption { ItemTypeOption(id: TypeID(id), label: id, icon: nil) }

    @Test func chipsLeadWithTheTypesHeldMostAndFillUpFromTheRest() {
        let options = ["a", "b", "c", "d", "e", "f"].map(option)
        let split = NewItemChips.split(options, usedMost: [TypeID("e"), TypeID("c"), TypeID("zzz")], limit: 4)
        #expect(split.shown.map(\.label) == ["e", "c", "a", "b"])
        #expect(split.more.map(\.label) == ["d", "f"])
    }

    @Test func fewerTypesThanChipsLeavesNothingUnderMore() {
        let split = NewItemChips.split([option("a")], usedMost: [])
        #expect(split.shown.map(\.label) == ["a"])
        #expect(split.more.isEmpty)
    }

    // MARK: Places

    @Test func theSixPlacesEachOpenSomethingWithAMark() {
        let places = SidebarPlace.destinations + SidebarPlace.builtInViews
        #expect(places.compactMap(\.item) == [.allNotes, .sources, .collections, .inbox, .recents, .favorites])
        #expect(places.allSatisfy { $0.symbol != nil })
        #expect(Set(places.compactMap(\.symbol)).count == places.count)
    }

    @Test func aBlockOrATypeOpensNothingAndASavedViewOpensItself() {
        #expect(SidebarPlace.types.item == nil)
        #expect(SidebarPlace.views.item == nil)
        #expect(SidebarPlace.type("core.note").item == nil)
        #expect(SidebarPlace.type("core.note").symbol == nil)
        #expect(SidebarPlace.view(viewOne).item == .view(viewOne))
        #expect(SidebarPlace.view(viewOne).symbol == SidebarPlace.viewSymbol)
    }

    @Test func onlyItemsInboxAndFavoritesCarryACount() {
        let counted = (SidebarPlace.destinations + SidebarPlace.builtInViews).filter(\.showsCount)
        #expect(counted == [.all, .inbox, .favorites])
    }

    @Test func theViewsBlockComesBeforeTheTypesBlock() {
        #expect(SidebarPlan(library(), layout: SidebarLayout()).library == [.views, .types])
    }
}
