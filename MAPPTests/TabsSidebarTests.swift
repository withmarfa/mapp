#if DEBUG
import Testing

@testable import MAPP

struct TabsSidebarTests {
    @Test func theBarHasHomeItemsSourcesAndSettingsInOrder() {
        #expect(SidebarTab.allCases.map(\.rawValue) == ["home", "items", "sources", "settings"])
    }

    @Test func settingsAndHomeTakePrecedenceOverThePlaceBeneath() {
        #expect(SidebarTab.current(item: .sources, home: true, settings: true) == .settings)
        #expect(SidebarTab.current(item: .sources, home: true, settings: false) == .home)
    }

    @Test func everyListOfItemsIsTheItemsTab() {
        let lists: [SidebarItem] = [
            .allNotes, .recents, .favorites, .itemType("core.note"), .collection(ItemID("c")), .collections, .view(ItemID("v")),
            .recentlyDeleted, .files,
        ]
        for item in lists { #expect(SidebarTab.current(item: item, home: false, settings: false) == .items) }
    }

    @Test func sourcesAndASourceAreTheSourcesTab() {
        #expect(SidebarTab.current(item: .sources, home: false, settings: false) == .sources)
        #expect(SidebarTab.current(item: .source("Mail"), home: false, settings: false) == .sources)
    }

    @Test func theInboxHasNoTabOfItsOwnSelected() {
        #expect(SidebarTab.current(item: .inbox, home: false, settings: false) == nil)
    }

    @Test func choosingATabMovesToItsPlace() {
        #expect(SidebarTab.move(for: .home, item: .allNotes, home: false, settings: false) == .home)
        #expect(SidebarTab.move(for: .items, item: .sources, home: false, settings: false) == .place(.allNotes))
        #expect(SidebarTab.move(for: .sources, item: .allNotes, home: false, settings: false) == .place(.sources))
        #expect(SidebarTab.move(for: .settings, item: .allNotes, home: false, settings: false) == .settings)
    }

    @Test func choosingTheTabAlreadyShownChangesNothing() {
        #expect(SidebarTab.move(for: .home, item: .allNotes, home: true, settings: false) == .stay)
        #expect(SidebarTab.move(for: .items, item: .allNotes, home: false, settings: false) == .stay)
        #expect(SidebarTab.move(for: .sources, item: .sources, home: false, settings: false) == .stay)
    }

    @Test func itemsFromInsideAListGoesBackToAllItems() {
        #expect(SidebarTab.move(for: .items, item: .itemType("core.note"), home: false, settings: false) == .place(.allNotes))
        #expect(SidebarTab.move(for: .items, item: .allNotes, home: true, settings: false) == .place(.allNotes))
    }

    @Test func settingsLeavesToThePlaceBeforeAndEveryOtherTabLeavesSettings() {
        #expect(SidebarTab.move(for: .settings, item: .allNotes, home: false, settings: true) == .leaveSettings)
        #expect(SidebarTab.move(for: .items, item: .allNotes, home: false, settings: true) == .place(.allNotes))
        #expect(SidebarTab.move(for: .home, item: .allNotes, home: true, settings: true) == .home)
    }

    @Test func theGreetingFollowsTheHour() {
        #expect(TabsGreeting.text(hour: 4) == "Good evening")
        #expect(TabsGreeting.text(hour: 5) == "Good morning")
        #expect(TabsGreeting.text(hour: 11) == "Good morning")
        #expect(TabsGreeting.text(hour: 12) == "Good afternoon")
        #expect(TabsGreeting.text(hour: 17) == "Good afternoon")
        #expect(TabsGreeting.text(hour: 18) == "Good evening")
        #expect(TabsGreeting.text(hour: 0) == "Good evening")
    }

    @Test func theTabsStyleIsAChoiceOfTheSwitch() {
        #expect(SidebarStyle(rawValue: "tabs") == .tabs)
    }

    @Test func homeEndsWhenAPlaceOrAnItemIsChosenButNotWhenTheAppSelects() {
        let browser = Browser()
        browser.tabsHome = true
        browser.selection = []
        #expect(browser.tabsHome)
        browser.selection = [ItemID("one")]
        #expect(!browser.tabsHome)
        browser.tabsHome = true
        browser.sidebarItem = .inbox
        #expect(!browser.tabsHome)
    }
}
#endif
