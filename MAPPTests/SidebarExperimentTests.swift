#if DEBUG
import Testing

@testable import MAPP

struct SidebarExperimentTests {
    @Test func theMainBlockStartsWithItemsSourcesAndCollections() {
        #expect(ExperimentMainBlock(stored: ExperimentMainBlock.defaultStored).keys == ["all", "sources", "collections"])
    }

    @Test func aBlockKeepsItsOrderAndDropsRepeatsAndBlanks() {
        let block = ExperimentMainBlock(stored: "sources,,all,sources,type:aic.ticket")
        #expect(block.keys == ["sources", "all", "type:aic.ticket"])
    }

    @Test func aTogglePutsAPlaceAtTheEndOrTakesItOut() {
        var block = ExperimentMainBlock(stored: "all")
        block.toggle("favorites")
        #expect(block.stored == "all,favorites")
        block.toggle("all")
        #expect(block.stored == "favorites")
        block.toggle("favorites")
        #expect(block.keys.isEmpty)
        #expect(ExperimentMainBlock(stored: block.stored).keys.isEmpty)
    }

    @Test func eachKeyOpensItsPlaceAndAnUnknownKeyOpensNothing() {
        #expect(ExperimentMainBlock.item(forKey: "all") == .allNotes)
        #expect(ExperimentMainBlock.item(forKey: "deleted") == .recentlyDeleted)
        #expect(ExperimentMainBlock.item(forKey: ExperimentMainBlock.typeKey("aic.ticket")) == .itemType("aic.ticket"))
        #expect(ExperimentMainBlock.item(forKey: "nonsense") == nil)
        for key in ExperimentMainBlock.placeKeys { #expect(ExperimentMainBlock.item(forKey: key) != nil) }
    }

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

    @Test func theSwitchStartsOnTheCurrentSidebar() {
        #expect(SidebarStyle.knob.initial == .option("current"))
        #expect(SidebarStyle.allCases.map(\.rawValue) == ["current", "experiment"])
    }

    @Test func aLandingEndsWhenAnItemIsChosenButNotWhenTheAppSelects() {
        let browser = Browser()
        browser.landing = true
        browser.selection = []
        #expect(browser.landing)
        browser.selection = [ItemID("one")]
        #expect(!browser.landing)
        browser.landing = true
        browser.sidebarItem = .recents
        #expect(!browser.landing)
    }
}
#endif
