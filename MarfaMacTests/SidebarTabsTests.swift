import Foundation
import Testing

@testable import MarfaMac

/// The sidebar's tabs and sections and the commands: what each change to the arrangement leaves behind, at the edges.
/// How a layout an earlier copy stored reads is `SidebarReadingTests`.
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

    @Test func draggingARowAcrossTheBlocksOfADefaultSectionIsKept() {
        var layout = SidebarLayout()
        let members = SidebarPlan(library(), layout: layout).section(.places)?.members ?? []
        #expect(members == [.library, .feed])
        layout.moveInSection("places", places: members, shown: members, fromOffsets: [1], toOffset: 0)
        #expect(SidebarPlan(library(), layout: layout).section(.places)?.shown == [.feed, .library])
    }

    @Test func placingARowInASectionByHandMakesItOneListInThePersonsOrder() {
        var layout = SidebarLayout()
        layout.put(.view(ItemID("v-Reading")), in: "pinned")
        let places = SidebarPlan(library(), layout: layout).section(.pinned)?.shown ?? []
        #expect(places.first == .view(ItemID("v-Reading")), "placed, so it has a position, ahead of those never placed")
    }

    @Test func aNewLibrarysShortcutsAreSearchAndNewAndNoneMakesAnItemOfATypeThePersonMade() {
        let shortcuts = SidebarGroup.defaults(tab: SidebarTab.homeID).first { $0.kind == .shortcuts }?.shortcuts
        #expect(shortcuts == [.search, .new])
        let plan = SidebarPlan(library(), layout: SidebarLayout())
        #expect(plan.section(.shortcuts)?.group.shortcuts == [.search, .new])
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

    @Test func removingASectionFreesOnlyItsOwnPlaces() {
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
        layout.hideGroup(section)
        #expect(layout.homes == [SidebarPlace.source("kept").key: other], "only the removed section's places are freed")
        #expect(layout.home(of: .collection(collection.id)) == nil)
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
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", "places", "types", "pinned"])
        layout.moveGroup("types", by: 1)
        #expect(ids(layout, tab: SidebarTab.homeID) == before)
    }

    @Test func movingPassesAHiddenSectionByAndNeverMakesAnInvisibleMove() {
        var layout = SidebarLayout()
        layout.hideGroup("pinned")
        layout.moveGroup("types", by: -1)
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", "types", "pinned", "places"], "Types takes the Library's place")
    }

    @Test func aSectionMovedToATabWithNoneJoinsItAndTheSourceTabKeepsTheRest() {
        var (layout, work, section) = arranged()
        #expect(ids(layout, tab: work).isEmpty)
        layout.moveGroup(section, toTab: work)
        #expect(ids(layout, tab: work) == [section])
        #expect(!ids(layout, tab: SidebarTab.homeID).contains(section))
        #expect(kinds(layout) == [.shortcuts, .places, .pinned, .types])
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

        layout.moveGroup("pinned", toTab: work)
        layout.hideGroup("pinned")
        #expect(layout.allTabs.map(\.id).contains(work))
        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.groups(in: work, customizing: false).isEmpty)
        // The Section place brings the built-in one back, here.
        layout.addGroup(.pinned, toTab: work)
        #expect(ids(layout, tab: work) == ["pinned"])
        #expect(SidebarPlan(library(), layout: layout).groups(in: work, customizing: false).map(\.id) == ["pinned"])
    }

    @Test func removingTheSecondTabReturnsItsSectionsToTheFirstAndLosesNone() {
        var (layout, work, section) = arranged()
        layout.moveGroup(section, toTab: work)
        layout.moveGroup("types", toTab: work)
        let removed = layout.removeTab(work)
        #expect(removed)
        #expect(layout.allTabs.map(\.id) == [SidebarTab.homeID])
        let home = ids(layout, tab: SidebarTab.homeID)
        #expect(Set(home) == ["shortcuts", "places", "pinned", "types", section])
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
        layout.renameGroup("pinned", to: "Stuff")
        #expect(layout.allGroups.first { $0.id == "pinned" }?.name == "Stuff")
        layout.renameGroup("pinned", to: "")
        #expect(layout.allGroups.first { $0.id == "pinned" }?.name == String(localized: "Pinned"))
        layout.renameGroup("places", to: "Stuff")
        #expect(layout.allGroups.first { $0.id == "places" }?.title == nil, "the zones have no heading to name")
    }

    @Test func draggingASectionOntoAnotherTakesItsPlaceAndNeverCrossesTabs() {
        var (layout, work, section) = arranged()
        layout.moveGroup(section, onto: "pinned")
        #expect(ids(layout, tab: SidebarTab.homeID) == ["shortcuts", "places", section, "pinned", "types"])
        layout.moveGroup(section, toTab: work)
        let before = layout
        layout.moveGroup(section, onto: "pinned")
        #expect(layout == before)
    }

    // MARK: Putting places in sections

    @Test func aPlacePutInASectionLeavesItsOldOneAndTakingItBackHidesOrForgetsIt() {
        var layout = SidebarLayout()
        layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        let view = SidebarPlace.view(ItemID("v-Reading"))
        layout.put(view, in: "mine")
        #expect(layout.home(of: view) == "mine")
        let plan = SidebarPlan(library(), layout: layout)
        #expect(plan.section(.pinned)?.shown.contains(view) == false)
        #expect(plan.groups.first { $0.id == "mine" }?.shown == [view])

        layout.take(view)
        #expect(layout.isHidden(view))
        layout.put(.collection(ItemID("c")), in: "mine")
        layout.take(.collection(ItemID("c")))
        #expect(layout.homes?[SidebarPlace.collection(ItemID("c")).key] == nil)
    }

    @Test func aSectionTakesOnlyWhatItCanHold() {
        var layout = SidebarLayout()
        layout.put(.view(ItemID("v-Reading")), in: "types")
        layout.put(.view(ItemID("v-Reading")), in: "gone")
        layout.put(.view(ItemID("v-Reading")), in: "places")
        layout.put(.collections, in: "pinned")
        #expect(layout.homes == nil)
        #expect(layout.home(of: .view(ItemID("v-Reading"))) == "pinned")
        layout.put(.collections, in: "places")
        #expect(layout.home(of: .collections) == "places")
        #expect(SidebarPlan(library(), layout: layout).section(.places)?.shown == [.library, .feed, .collections])
    }

    @Test func aPlaceInASectionThatIsGoneReturnsToItsOwn() {
        var layout = SidebarLayout()
        layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.view(ItemID("v-Reading")), in: "mine")
        layout.hideGroup("mine")
        #expect(layout.home(of: .view(ItemID("v-Reading"))) == "pinned")
    }

    @Test func anItemIsPinnedWhileTheCopyHoldsItAndTakingItOutForgetsIt() {
        let library = library()
        let note = library.items[0]
        var layout = SidebarLayout()
        layout.put(.item(note.id), in: "pinned")
        #expect(SidebarPlan(library, layout: layout).section(.pinned)?.shown.contains(.item(note.id)) == true)
        library.items.removeAll()
        #expect(SidebarPlan(library, layout: layout).section(.pinned)?.shown.contains(.item(note.id)) == false)
        #expect(layout.home(of: .item(note.id)) == "pinned", "kept, so the row returns with the item")
        layout.take(.item(note.id))
        #expect(layout.homes == nil)
    }

    // MARK: Shortcuts

    @Test func shortcutsAreAddedOnceRemovedAndReordered() {
        var layout = SidebarLayout()
        layout.addShortcut(.settings, toTab: SidebarTab.homeID)
        layout.addShortcut(.settings, toTab: SidebarTab.homeID)
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.search, .new, .settings])
        layout.moveShortcuts(in: "shortcuts", fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.settings, .search, .new])
        layout.removeShortcut(.new, from: "shortcuts")
        #expect(layout.groups(in: SidebarTab.homeID).first?.shortcuts == [.settings, .search])
    }

    @Test func aTabWithNoShortcutsBlockGetsOneFirstWhenAShortcutIsAdded() {
        var (layout, work, _) = arranged()
        layout.addShortcut(.search, toTab: work)
        #expect(layout.groups(in: work).map(\.kind) == [.shortcuts])
        #expect(layout.groups(in: work).first?.shortcuts == [.search])
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
