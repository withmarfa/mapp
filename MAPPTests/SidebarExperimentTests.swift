#if DEBUG
import Foundation
import Testing

@testable import MAPP

@MainActor
struct SidebarExperimentTests {
    // MARK: Switch

    @Test func theSwitchStartsOnTheCurrentSidebar() {
        #expect(SidebarStyle.knob.initial == .option("current"))
        #expect(SidebarStyle.allCases.map(\.rawValue) == ["current", "experiment", "tabs"])
    }

    // MARK: Blocks

    private func library() -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now), FakeItemLibrary.note("Two", modified: .now)])
        library.views = [LibraryView(id: ItemID("view-1"), title: "Open work"), LibraryView(id: ItemID("view-2"), title: "Reading")]
        return library
    }

    @Test func everyBlockShowsByDefault() {
        let blocks = ExperimentBlocks(SidebarPlan(library(), layout: SidebarLayout()))
        #expect(blocks.top == [.all, .sources, .collections])
        #expect(blocks.places == [.inbox, .recents, .favorites])
        #expect(blocks.showsTypes)
        #expect(blocks.showsViews)
    }

    @Test func aPlaceSwitchedOffLeavesItsBlock() {
        var layout = SidebarLayout()
        layout.setHidden(.recents, true)
        layout.setHidden(.sources, true)
        let blocks = ExperimentBlocks(SidebarPlan(library(), layout: layout))
        #expect(blocks.places == [.inbox, .favorites])
        #expect(blocks.top == [.all, .collections])
    }

    @Test func thePlacesBlockIsGoneOnceAllThreeAreOff() {
        var layout = SidebarLayout()
        for place in [SidebarPlace.inbox, .recents, .favorites] { layout.setHidden(place, true) }
        #expect(ExperimentBlocks(SidebarPlan(library(), layout: layout)).places.isEmpty)
    }

    @Test func theTypesAndViewsBlocksFollowTheirSwitches() {
        var layout = SidebarLayout()
        layout.setHidden(.types, true)
        var blocks = ExperimentBlocks(SidebarPlan(library(), layout: layout))
        #expect(!blocks.showsTypes)
        #expect(blocks.showsViews)
        layout.setHidden(.types, false)
        layout.setHidden(.views, true)
        blocks = ExperimentBlocks(SidebarPlan(library(), layout: layout))
        #expect(blocks.showsTypes)
        #expect(!blocks.showsViews)
    }

    @Test func theViewsBlockIsGoneOnceEveryViewIsOff() {
        var layout = SidebarLayout()
        layout.setHidden(.view(ItemID("view-1")), true)
        #expect(ExperimentBlocks(SidebarPlan(library(), layout: layout)).showsViews)
        layout.setHidden(.view(ItemID("view-2")), true)
        #expect(!ExperimentBlocks(SidebarPlan(library(), layout: layout)).showsViews)
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
        let result = ExperimentTypeLimit.rows(all, showsAll: false)
        #expect(result.rows.map(\.id) == all.map(\.id))
        #expect(!result.hasMore)
        #expect(!ExperimentTypeLimit.rows([], showsAll: false).hasMore)
    }

    @Test func moreThanSixTypesShowSixUntilShowMore() {
        let all = rows((1...9).map { node("t\($0)") })
        let result = ExperimentTypeLimit.rows(all, showsAll: false)
        #expect(result.rows.map(\.id) == (1...6).map { "t\($0)" })
        #expect(result.hasMore)
    }

    @Test func showMoreRevealsTheRestAndStillOffersShowLess() {
        let all = rows((1...9).map { node("t\($0)") })
        let result = ExperimentTypeLimit.rows(all, showsAll: true)
        #expect(result.rows.count == 9)
        #expect(result.hasMore)
    }

    @Test func aTypeKeepsItsSubtypeRowsAndTheyDoNotCountTowardsSix() {
        let kids = [node("a.1"), node("a.2"), node("a.3")]
        let all = rows([node("a", children: kids)] + (2...8).map { node("t\($0)") })
        let result = ExperimentTypeLimit.rows(all, showsAll: false)
        // Six top-level types: a and t2 to t6, with a's three subtypes under it.
        #expect(result.rows.map(\.id) == ["a", "a.1", "a.2", "a.3", "t2", "t3", "t4", "t5", "t6"])
        #expect(result.hasMore)
    }

    @Test func aFoldedTypeCountsOnceAndHidesItsSubtypeRows() {
        let kids = [node("a.1"), node("a.2")]
        var all = rows([node("a", children: kids)] + (2...7).map { node("t\($0)") })
        all.removeAll { $0.depth > 0 }
        all[0] = SidebarPlan.TypeRow(node: all[0].node, depth: 0, isExpanded: false)
        let result = ExperimentTypeLimit.rows(all, showsAll: false)
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
            #expect(browser(.allNotes, mode: mode).offersExperimentLanding)
        }
        #expect(!browser(.allNotes, mode: .list).offersExperimentLanding)
    }

    @Test func theRowOfChipsStandsAboveTheSourcesAndCollectionsIndexes() {
        #expect(browser(.sources, mode: .list).offersExperimentLanding)
        #expect(browser(.collections, mode: .gallery).offersExperimentLanding)
    }

    @Test func theRowOfChipsLeavesWhenAnItemOpensOrAnotherPlaceShows() {
        let items = browser(.allNotes, mode: .gallery)
        items.isCollectionItemPresented = true
        #expect(!items.offersExperimentLanding)
        items.returnToCollection()
        #expect(items.offersExperimentLanding)
        #expect(!browser(.recents, mode: .gallery).offersExperimentLanding)
        #expect(!browser(.itemType("core.note"), mode: .table).offersExperimentLanding)
    }

    @Test func settingsHasNoRowOfChips() {
        let items = browser(.allNotes, mode: .gallery)
        items.showSettings()
        #expect(!items.offersExperimentLanding)
        items.leaveSettings()
        #expect(items.offersExperimentLanding)
    }

    @Test func choosingItemsMovesAWindowOnTheListToTheGalleryAndLeavesAnotherLayoutBe() {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        let onList = browser(.recents, mode: .list)
        onList.showItemsLanding(in: library, order: NoteOrder())
        #expect(onList.item == .allNotes)
        #expect(onList.viewMode == .gallery)
        let onTable = browser(.recents, mode: .table)
        onTable.showItemsLanding(in: library, order: NoteOrder())
        #expect(onTable.viewMode == .table)
        #expect(onTable.offersExperimentLanding)
    }

    // MARK: Chips

    private func option(_ id: String) -> ItemTypeOption { ItemTypeOption(id: TypeID(id), label: id, icon: nil) }

    @Test func chipsLeadWithTheTypesHeldMostAndFillUpFromTheRest() {
        let options = ["a", "b", "c", "d", "e", "f"].map(option)
        let split = ExperimentChips.split(options, usedMost: [TypeID("e"), TypeID("c"), TypeID("zzz")], limit: 4)
        #expect(split.shown.map(\.label) == ["e", "c", "a", "b"])
        #expect(split.more.map(\.label) == ["d", "f"])
    }

    @Test func fewerTypesThanChipsLeavesNothingUnderMore() {
        let split = ExperimentChips.split([option("a")], usedMost: [])
        #expect(split.shown.map(\.label) == ["a"])
        #expect(split.more.isEmpty)
    }
}
#endif
