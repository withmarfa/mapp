import Foundation
import Testing

@testable import MarfaMac

/// The sidebar's tabs and sections, the shortcuts, and the color of a view's mark: what a layout stored by today's
/// build still reads as, and what each change to the arrangement leaves behind, at the edges.
@Suite(.hangLimit)
@MainActor
struct SidebarTabsTests {
    private func library(views: [String] = ["Open work", "Reading"]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        library.views = views.map { LibraryView(id: ItemID("v-\($0)"), title: $0) }
        return library
    }

    private func kinds(_ layout: SidebarLayout, tab: String = SidebarTab.homeID) -> [SidebarGroup.Kind] {
        layout.groups(in: tab).map(\.kind)
    }

    private func ids(_ layout: SidebarLayout, tab: String) -> [String] { layout.groups(in: tab).map(\.id) }

    /// A layout with a second tab and a section of the person's own, in the first.
    private func arranged() -> (layout: SidebarLayout, work: String, section: String) {
        var layout = SidebarLayout()
        let work = layout.addTab(named: "Work", id: "work")
        let section = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        return (layout, work, section)
    }

    // MARK: A layout stored by today's build

    @Test func aStoredLayoutWithNoTabsOrColorsLoadsAsOneTabUnchanged() throws {
        let saved = Data(#"{"hidden":["favorites","type:core.task"],"order":["view:v-Reading","view:v-Open work"],"collapsed":["type:core.note"]}"#.utf8)
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.tabs == nil && layout.groups == nil && layout.homes == nil && layout.colors == nil)
        #expect(layout.allTabs.map(\.id) == [SidebarTab.homeID])
        #expect(kinds(layout) == [.shortcuts, .library, .views, .types])
        #expect(layout.isHidden(.favorites) && layout.isCollapsed(.type("core.note")))

        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.tabs.count == 1)
        #expect(plan.shownBuiltInViews == [.feed])
        #expect(plan.shownSavedViews.map(\.title) == ["Reading", "Open work"], "the person's order of views holds")
        #expect(plan.groups(in: SidebarTab.homeID, customizing: false).map(\.group.kind) == [.shortcuts, .library, .views, .types])
        // Written back, it is the layout it was, with nothing added.
        #expect(try JSONDecoder().decode(SidebarLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }

    @Test func aSectionOfAKindThisCopyDoesNotKnowIsSkippedAloneAndKept() throws {
        let saved = Data(#"""
        {"groups":[{"id":"library","kind":"library","tab":"home","isHidden":false,"shortcuts":[]},
        {"id":"later","kind":"pinboard","tab":"home","extra":1},
        {"id":"types","kind":"types","tab":"home","isHidden":false,"shortcuts":[]}],"order":["library"]}
        """#.utf8)
        var layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.allGroups.map(\.id) == ["library", "types"])
        #expect(layout.order == ["library"])
        layout.setHidden(.library, true)
        let back = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any])
        let groups = try #require(back["groups"] as? [[String: Any]])
        #expect(groups.map { $0["id"] as? String } == ["library", "later", "types"])
        #expect(groups[1]["kind"] as? String == "pinboard" && groups[1]["extra"] as? Int == 1)
    }

    @Test func draggingARowAcrossTheBlocksOfADefaultSectionIsKept() {
        var layout = SidebarLayout()
        let members = SidebarPlan(library(), layout: layout).section(.views)?.members ?? []
        // The first saved view, dragged above Inbox.
        let from = members.firstIndex(of: .view(ItemID("v-Open work"))) ?? 0
        layout.moveInSection("views", places: members, shown: members, fromOffsets: [from], toOffset: 0)
        let after = SidebarPlan(library(), layout: layout).section(.views)?.shown ?? []
        #expect(after.first == .view(ItemID("v-Open work")))
        #expect(Set(after) == Set(members))
    }

    @Test func placingARowInASectionByHandMakesItOneListInThePersonsOrder() {
        var layout = SidebarLayout()
        layout.put(.view(ItemID("v-Reading")), in: "views")
        let places = SidebarPlan(library(), layout: layout).section(.views)?.shown ?? []
        #expect(places.first == .view(ItemID("v-Reading")), "placed, so it has a position, ahead of those never placed")
    }

    @Test func aNewLibrarysShortcutsAreNewAndSearchAndNoneMakesAnItemOfATypeThePersonMade() {
        let shortcuts = SidebarGroup.defaults(tab: SidebarTab.homeID).first { $0.kind == .shortcuts }?.shortcuts
        #expect(shortcuts == [.new, .search])
        let plan = SidebarPlan(library(), layout: SidebarLayout())
        #expect(plan.section(.shortcuts)?.group.shortcuts == [.new, .search])
        #expect(shortcuts?.contains { if case .create = $0 { true } else { false } } == false)
    }

    @Test func aShortcutKeepsItsKeyThroughStorage() throws {
        let all: [SidebarShortcut] = [.new, .search, .settings, .create("core.note"), .go("view:v-1")]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([SidebarShortcut].self, from: data) == all)
        #expect(SidebarShortcut(key: "create:") == nil && SidebarShortcut(key: "nonsense") == nil)
    }

    // MARK: What the library no longer holds

    @Test func aDeletedViewCollectionOrSourceDropsItsRowAndTheSectionStays() throws {
        let library = library()
        let collection = FakeItemLibrary.collection("Reading list")
        library.items.append(collection)
        var layout = SidebarLayout()
        let section = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.collection(collection.id), in: section)
        layout.put(.view(ItemID("v-Reading")), in: section)
        layout.put(.source("feed"), in: section)

        let before = SidebarPlan(library, layout: layout).groups.first { $0.id == section }
        #expect(before?.shown.contains(.collection(collection.id)) == true)
        #expect(before?.shown.contains(.view(ItemID("v-Reading"))) == true)
        #expect(before?.shown.contains(.source("feed")) == false, "a source the copy has never held has no row")

        library.items.removeAll { $0.id == collection.id }
        library.views.removeAll { $0.id == ItemID("v-Reading") }
        let after = SidebarPlan(library, layout: layout)
        let group = try #require(after.groups.first { $0.id == section })
        #expect(group.shown.isEmpty)
        #expect(after.groups(in: SidebarTab.homeID, customizing: true).contains { $0.id == section }, "the section stays to put something in")
        #expect(layout.homes?[SidebarPlace.collection(collection.id).key] == section, "the layout is not touched, so the row returns")
    }

    @Test func aSyncMissingCollectionReturnsItsRowWhenTheCopyHoldsItAgain() {
        let library = library()
        let collection = FakeItemLibrary.collection("Reading list")
        var layout = SidebarLayout()
        let section = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.collection(collection.id), in: section)
        #expect(SidebarPlan(library, layout: layout).groups.first { $0.id == section }?.shown.isEmpty == true)
        library.items.append(collection)
        #expect(SidebarPlan(library, layout: layout).groups.first { $0.id == section }?.shown == [.collection(collection.id)])
    }

    @Test func removingASectionFreesItsCollectionsAndSourcesToBeAddedAgain() {
        let library = library()
        let collection = FakeItemLibrary.collection("Reading list")
        library.items.append(collection)
        var layout = SidebarLayout()
        let section = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        let other = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "other")
        layout.put(.collection(collection.id), in: section)
        layout.put(.source("feed"), in: section)
        layout.put(.source("kept"), in: other)
        #expect(layout.home(of: .collection(collection.id)) == section)

        let placed = SidebarContent(library: library, layout: layout, tab: nil, customizing: true).choices
        #expect(!placed.unplacedCollections.contains { $0.key == SidebarPlace.collection(collection.id).key }, "in a section already")
        #expect(placed.collections.contains { $0.key == SidebarPlace.collection(collection.id).key }, "Go To still offers it")

        layout.hideGroup(section)
        #expect(layout.homes == [SidebarPlace.source("kept").key: other], "only the removed section's places are freed")
        #expect(layout.home(of: .collection(collection.id)) == nil)
        let freed = SidebarContent(library: library, layout: layout, tab: nil, customizing: true).choices
        #expect(freed.unplacedCollections.contains { $0.key == SidebarPlace.collection(collection.id).key })
    }

    @Test func aCollectionMissingFromTheCopyIsOfferedNowhereAndKeepsItsPlace() {
        let library = library()
        let collection = FakeItemLibrary.collection("Reading list")
        var layout = SidebarLayout()
        let section = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.collection(collection.id), in: section)
        // Missing from the copy, as in a sync gap: its key stays so the row returns, and no picker offers what the library lacks.
        let choices = SidebarContent(library: library, layout: layout, tab: nil, customizing: true).choices
        #expect(choices.collections.isEmpty && choices.unplacedCollections.isEmpty)
        #expect(layout.homes?[SidebarPlace.collection(collection.id).key] == section)
    }

    @Test func aShortcutToWhatIsGoneIsKeptInTheLayout() {
        var layout = SidebarLayout()
        layout.addShortcut(.go(SidebarPlace.view(ItemID("v-Gone")).key), toTab: SidebarTab.homeID)
        let section = SidebarPlan(library(), layout: layout).section(.shortcuts)
        #expect(section?.group.shortcuts.contains(.go("view:v-Gone")) == true)
    }

    // MARK: Moving sections

    @Test func theFirstSectionCannotMoveUpAndTheLastCannotMoveDown() {
        var layout = SidebarLayout()
        let before = ids(layout, tab: SidebarTab.homeID)
        layout.moveGroup(before[0], by: -1)
        #expect(ids(layout, tab: SidebarTab.homeID) == before)
        layout.moveGroup(before[before.count - 1], by: 1)
        #expect(ids(layout, tab: SidebarTab.homeID) == before)
        layout.moveGroup("types", by: -1)
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", "library", "types", "views"])
        layout.moveGroup("types", by: 1)
        #expect(ids(layout, tab: SidebarTab.homeID) == before)
    }

    @Test func movingPassesAHiddenSectionByAndNeverMakesAnInvisibleMove() {
        var layout = SidebarLayout()
        layout.hideGroup("views")
        layout.moveGroup("types", by: -1)
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", "types", "views", "library"], "Types takes Library's place")
    }

    @Test func aSectionMovedToATabWithNoneJoinsItAndTheSourceTabKeepsTheRest() {
        var (layout, work, section) = arranged()
        #expect(ids(layout, tab: work).isEmpty)
        layout.moveGroup(section, toTab: work)
        #expect(ids(layout, tab: work) == [section])
        #expect(!ids(layout, tab: SidebarTab.homeID).contains(section))
        #expect(kinds(layout) == [.shortcuts, .library, .views, .types])
    }

    @Test func aSectionMovedToATabThatDoesNotExistStaysWhereItIs() {
        var (layout, _, section) = arranged()
        let before = layout
        layout.moveGroup(section, toTab: "gone")
        #expect(layout == before)
    }

    @Test func hidingTheLastSectionOfATabLeavesTheTabAndItsSectionToBeShownAgain() {
        var (layout, work, section) = arranged()
        layout.moveGroup(section, toTab: work)
        layout.hideGroup(section)
        #expect(layout.allTabs.map(\.id).contains(work))
        #expect(ids(layout, tab: work).isEmpty, "a person's own section is removed with its hiding")

        layout.moveGroup("views", toTab: work)
        layout.hideGroup("views")
        #expect(layout.allTabs.map(\.id).contains(work))
        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.groups(in: work, customizing: false).isEmpty)
        // Add Section brings the built-in one back, here.
        layout.addGroup(.views, toTab: work)
        #expect(ids(layout, tab: work) == ["views"])
        #expect(SidebarPlan(library(), layout: layout).groups(in: work, customizing: false).map(\.id) == ["views"])
    }

    @Test func removingTheSecondTabReturnsItsSectionsToTheFirstAndLosesNone() {
        var (layout, work, section) = arranged()
        layout.moveGroup(section, toTab: work)
        layout.moveGroup("types", toTab: work)
        let removed = layout.removeTab(work)
        #expect(removed)
        #expect(layout.allTabs.map(\.id) == [SidebarTab.homeID])
        let home = ids(layout, tab: SidebarTab.homeID)
        #expect(Set(home) == ["shortcuts", "library", "views", "types", section])
        #expect(home.count == 5)
        #expect(layout.allGroups.count == 5)
    }

    @Test func theOnlyTabCannotBeRemovedAndAnUnknownTabIsRefused() {
        var layout = SidebarLayout()
        let removedOnly = layout.removeTab(SidebarTab.homeID)
        #expect(!removedOnly)
        let (arrangedLayout, _, _) = arranged()
        layout = arrangedLayout
        let removedMissing = layout.removeTab("gone")
        #expect(!removedMissing)
        #expect(layout.allTabs.count == 2)
    }

    @Test func aSectionWhoseTabIsGoneAppearsInTheFirst() throws {
        var layout = SidebarLayout()
        layout.groups = [SidebarGroup(id: "orphan", kind: .custom, tab: "gone")]
        layout.tabs = [SidebarTab.home]
        #expect(layout.groups(in: SidebarTab.homeID).map(\.id) == ["orphan"])
    }

    @Test func aTabIsNamedAndRenamedAndAnEmptyNameChangesNothing() {
        var layout = SidebarLayout()
        let id = layout.addTab(named: "  Work  ")
        #expect(layout.allTabs.map(\.name) == [SidebarTab.home.name, "Work"])
        layout.renameTab(id, to: "   ")
        #expect(layout.allTabs.last?.name == "Work")
        layout.renameTab(id, to: "Home life")
        #expect(layout.allTabs.last?.name == "Home life")
        #expect(layout.tab("gone").id == SidebarTab.homeID)
    }

    @Test func aSectionIsRenamedAndAnEmptyNameReturnsTheKindsOwn() {
        var layout = SidebarLayout()
        layout.renameGroup("library", to: "Stuff")
        #expect(layout.allGroups.first { $0.id == "library" }?.name == "Stuff")
        layout.renameGroup("library", to: "")
        #expect(layout.allGroups.first { $0.id == "library" }?.name == String(localized: "Library"))
    }

    @Test func draggingASectionOntoAnotherTakesItsPlaceAndNeverCrossesTabs() {
        var (layout, work, section) = arranged()
        layout.moveGroup(section, onto: "library")
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", section, "library", "views", "types"])
        layout.moveGroup(section, toTab: work)
        let before = layout
        layout.moveGroup(section, onto: "library")
        #expect(layout == before)
    }

    // MARK: Putting places in sections

    @Test func aPlacePutInASectionLeavesItsOldOneAndTakingItBackHidesOrForgetsIt() {
        var layout = SidebarLayout()
        layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.favorites, in: "mine")
        #expect(layout.home(of: .favorites) == "mine")
        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.section(.views)?.shown.contains(.favorites) == false)
        #expect(plan.groups.first { $0.id == "mine" }?.shown == [.favorites])

        layout.take(.favorites)
        #expect(layout.isHidden(.favorites))
        layout.put(.collection(ItemID("c")), in: "mine")
        layout.take(.collection(ItemID("c")))
        #expect(layout.homes?[SidebarPlace.collection(ItemID("c")).key] == nil)
    }

    @Test func aPlaceCannotBePutInTheTypesSectionOrAMissingOne() {
        var layout = SidebarLayout()
        layout.put(.favorites, in: "types")
        layout.put(.favorites, in: "gone")
        #expect(layout.homes == nil)
        #expect(layout.home(of: .favorites) == "views")
    }

    @Test func aPlaceInASectionThatIsGoneReturnsToItsOwn() {
        var layout = SidebarLayout()
        layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.favorites, in: "mine")
        layout.hideGroup("mine")
        #expect(layout.home(of: .favorites) == "views")
    }

    // MARK: Shortcuts

    @Test func shortcutsAreAddedOnceRemovedAndReordered() {
        var layout = SidebarLayout()
        layout.addShortcut(.settings, toTab: SidebarTab.homeID)
        layout.addShortcut(.settings, toTab: SidebarTab.homeID)
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.new, .search, .settings])
        layout.moveShortcuts(in: "shortcuts", fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.settings, .new, .search])
        layout.removeShortcut(.new, from: "shortcuts")
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.settings, .search])
    }

    @Test func aTabWithNoShortcutsBlockGetsOneFirstWhenAShortcutIsAdded() {
        var (layout, work, _) = arranged()
        layout.addShortcut(.search, toTab: work)
        #expect(layout.groups(in: work).map(\.kind) == [.shortcuts])
        #expect(layout.groups(in: work).first?.shortcuts == [.search])
    }

    // MARK: Colors

    @Test func aViewsColorIsKeptAndReadBackAndNilReturnsItsOwn() throws {
        let view = SidebarPlace.view(ItemID("v-Reading"))
        var layout = SidebarLayout()
        #expect(layout.color(of: view) == .gray)
        for place in [SidebarPlace.feed, .favorites, .library, .sources, .collections, .collection(ItemID("c-One")), .source("rss")] {
            #expect(layout.color(of: place) == .gray && place.defaultTone == .gray)
        }
        #expect(SidebarPlace.type("core.note").defaultTone == nil)
        layout.setColor(.blue, of: .library)
        #expect(layout.color(of: .library) == .blue)
        layout.setColor(nil, of: .library)
        layout.setColor(.purple, of: view)
        #expect(layout.color(of: view) == .purple)
        let stored = try JSONDecoder().decode(SidebarLayout.self, from: JSONEncoder().encode(layout))
        #expect(stored.color(of: view) == .purple)
        layout.setColor(nil, of: view)
        #expect(layout.color(of: view) == .gray)
        #expect(layout.colors == nil)
    }

    @Test func aColorSurvivesRelaunchForItsLibraryAlone() throws {
        let defaults = ThrowawayDefaults.make("SidebarTabsTests.colors")
        let view = SidebarPlace.view(ItemID("v-Reading"))
        SidebarLayouts(defaults: defaults).update("marfa:one") { $0.setColor(.teal, of: view) }
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").color(of: view) == .teal)
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:two").color(of: view) == .gray)
    }

    @Test func aColorChosenBeforeGrayBecameTheDefaultStays() throws {
        let saved = Data(#"{"colors":{"inbox":"blue","favorites":"pink"}}"#.utf8)
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.color(of: .feed) == .blue && layout.color(of: .favorites) == .pink && layout.color(of: .library) == .gray)
    }

    @Test func anUnknownStoredColorReadsAsTheViewsOwn() throws {
        let saved = Data(#"{"colors":{"view:v-Reading":"chartreuse"}}"#.utf8)
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.color(of: .view(ItemID("v-Reading"))) == .gray)
    }

    // MARK: Two windows

    @Test func aWindowThatMovesToAnotherLibraryStopsCustomizingAndForgetsItsTab() {
        let browser = Browser()
        browser.adopt(library())
        browser.customizesSidebar = true
        browser.sidebarTab = "work"
        browser.adopt(library())
        #expect(!browser.customizesSidebar)
        #expect(browser.sidebarTab == nil)
    }

}
