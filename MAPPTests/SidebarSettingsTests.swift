import Foundation
import Testing

@testable import MAPP

/// What Settings > Sidebar says over the sidebar's own layout: the tabs and their sections, the hidden ones kept for
/// coming back, the views with their colors and order, and the names a tab or a section is given. The arrangement itself
/// is tested in `SidebarTabsTests`.
@Suite(.hangLimit)
@MainActor
struct SidebarSettingsTests {
    private func library(views: [String] = ["Open work", "Reading"]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("One", modified: .now)])
        library.views = views.map { LibraryView(id: ItemID("v-\($0)"), title: $0) }
        return library
    }

    private func plan(_ library: FakeItemLibrary, _ layout: SidebarLayout = SidebarLayout()) -> SidebarSettingsPlan {
        SidebarSettingsPlan(library, layout: layout)
    }

    /// The built-in views' names as the library gives them.
    private func builtIns(_ library: FakeItemLibrary) -> [String] {
        SidebarPlace.builtInViews.compactMap { $0.item.map(library.name(of:)) }
    }

    private func names(_ places: [SidebarPlace], _ library: FakeItemLibrary) -> String {
        places.compactMap { $0.item.map(library.name(of:)) }.joined(separator: ", ")
    }

    // MARK: Tabs and sections

    @Test func aLayoutWithOneTabListsHomeWithTheSidebarsFourSections() {
        let plan = plan(library())
        #expect(plan.tabs.map(\.id) == [SidebarTab.homeID])
        #expect(plan.tabs[0].sections.map(\.kind) == [.shortcuts, .library, .views, .types])
        #expect(plan.tabs[0].sections.allSatisfy { $0.isShown })
        #expect(plan.tabs[0].sections[0].detail == "New, Search")
    }

    @Test func aTabWithNoSectionsIsListedEmpty() {
        var layout = SidebarLayout()
        let work = layout.addTab(named: "Work", id: "work")
        let tabs = plan(library(), layout).tabs
        #expect(tabs.map(\.id) == [SidebarTab.homeID, work])
        #expect(tabs[1].sections.isEmpty)
        #expect(tabs[0].sections.count == 4)
    }

    @Test func aHiddenBuiltInSectionStaysWhereItIsSwitchedOffAndComesBackInPlace() {
        var layout = SidebarLayout()
        layout.hideGroup("library")
        let hidden = plan(library(), layout).tabs[0].sections
        #expect(hidden.map(\.kind) == [.shortcuts, .library, .views, .types], "it is still listed, so it can come back")
        #expect(hidden.map(\.isShown) == [true, false, true, true])

        layout.showGroup("library")
        #expect(plan(library(), layout).tabs[0].sections.map(\.kind) == [.shortcuts, .library, .views, .types])
        #expect(plan(library(), layout).tabs[0].sections.allSatisfy { $0.isShown })
    }

    // MARK: The Types section from a layout stored by today's build

    private func marfaLibrary() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    private func typesSection(_ library: MarfaLibrary, _ layout: SidebarLayout) throws -> SidebarSettingsPlan.Section {
        try #require(SidebarSettingsPlan(library, layout: layout).tabs[0].sections.first { $0.kind == .types })
    }

    private func sidebarShowsTypes(_ library: MarfaLibrary, _ layout: SidebarLayout) -> Bool {
        let plan = SidebarPlan(library, layout: layout)
        return plan.groups(in: SidebarTab.homeID, customizing: false).contains { $0.group.kind == .types }
    }

    @Test func typesHiddenByTodaysShowTypesSwitchReadAsOffHereAndShowBringsThemBack() async throws {
        let library = try await marfaLibrary()
        var layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(#"{"hidden":["types"],"order":[]}"#.utf8))
        #expect(!sidebarShowsTypes(library, layout), "the sidebar hides the section")
        #expect(try !typesSection(library, layout).isShown, "so Settings says it is off")

        layout.showGroup("types")
        #expect(try typesSection(library, layout).isShown)
        #expect(sidebarShowsTypes(library, layout))
        #expect(!layout.isHidden(.types))
        #expect(try JSONDecoder().decode(SidebarLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }

    @Test func hidingTheTypesSectionFromSettingsHidesItInTheSidebarAndShowBringsItBack() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.hideGroup("types")
        #expect(try !typesSection(library, layout).isShown)
        #expect(!sidebarShowsTypes(library, layout))

        layout.showGroup("types")
        #expect(try typesSection(library, layout).isShown)
        #expect(sidebarShowsTypes(library, layout))
    }

    @Test func addSectionBringsBackTypesHiddenByTodaysShowTypesSwitch() async throws {
        let library = try await marfaLibrary()
        var layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(#"{"hidden":["types"],"order":[]}"#.utf8))
        let content = SidebarContent(library: library, layout: layout, tab: nil, customizing: true)
        #expect(content.hiddenKinds == [.types], "Add Section offers it")
        layout.addGroup(.types, toTab: SidebarTab.homeID)
        #expect(try typesSection(library, layout).isShown)
        #expect(sidebarShowsTypes(library, layout))
    }

    @Test func aSubtypeHiddenByItsRowIsOfferedInTheTypesSectionsShowListAndComesBack() async throws {
        let library = try await marfaLibrary()
        var layout = try JSONDecoder().decode(SidebarLayout.self, from: Data(#"{"hidden":["type:aic.ticket.bug"],"order":[]}"#.utf8))
        let bug = SidebarPlace.type("aic.ticket.bug")
        let offered = try typesSection(library, layout).choices
        let choice = try #require(offered.first { $0.place == bug })
        #expect(!choice.isShown && choice.title.hasSuffix("Bugs"))
        #expect(!offered.contains { $0.place == .type("aic.ticket.task") }, "a shown subtype is not offered twice")
        #expect(!SidebarPlan(library, layout: layout).shownTypes.flatMap(\.children).map(\.id).contains("aic.ticket.bug"))

        layout.setHidden(choice.place, false)
        #expect(SidebarPlan(library, layout: layout).shownTypes.flatMap(\.children).map(\.id).contains("aic.ticket.bug"))
        #expect(try !typesSection(library, layout).choices.contains { $0.place == bug })
    }

    @Test func aSectionOfThePersonsOwnIsRemovedNotHidden() {
        var layout = SidebarLayout()
        let mine = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        let section = plan(library(), layout).tabs[0].sections.first { $0.id == mine }
        #expect(section?.canHide == false)
        #expect(section?.detail == "Empty")
        layout.hideGroup(mine)
        #expect(!plan(library(), layout).tabs[0].sections.contains { $0.id == mine })
    }

    @Test func aSectionSaysWhatItHoldsAndHowManyRowsAreShown() {
        var layout = SidebarLayout()
        layout.setHidden(.favorites, true)
        let library = library()
        let sections = plan(library, layout).tabs[0].sections
        let views = sections.first { $0.kind == .views }
        #expect(views?.detail == "5 views")
        #expect(views?.shownCount == 4, "the saved views as a whole are a choice, not a row")
        #expect(sections.first { $0.kind == .library }?.detail == names([.all, .sources, .collections], library))
        layout.setHidden(.sources, true)
        #expect(plan(library, layout).tabs[0].sections.first { $0.kind == .library }?.detail == names([.all, .collections], library))
    }

    @Test func movingSectionsInATabCountsHiddenOnesAndLeavesOtherTabsAlone() {
        var layout = SidebarLayout()
        layout.addTab(named: "Work", id: "work")
        layout.moveGroup("types", toTab: "work")
        layout.hideGroup("library")
        // Home is now shortcuts, library (hidden), views: drag the hidden library below views.
        layout.moveGroups(inTab: SidebarTab.homeID, fromOffsets: [1], toOffset: 3)
        #expect(layout.groups(in: SidebarTab.homeID).map(\.id) == ["shortcuts", "views", "library"])
        #expect(layout.groups(in: "work").map(\.id) == ["types"])
        layout.moveGroups(inTab: SidebarTab.homeID, fromOffsets: [2], toOffset: 0)
        #expect(layout.groups(in: SidebarTab.homeID).map(\.id) == ["library", "shortcuts", "views"])
        layout.moveGroups(inTab: SidebarTab.homeID, fromOffsets: [7], toOffset: 0)
        #expect(layout.groups(in: SidebarTab.homeID).map(\.id) == ["library", "shortcuts", "views"], "an offset outside the list changes nothing")
    }

    // MARK: Views

    @Test func theViewsAreInboxRecentsFavoritesThenTheSavedViewsEachInItsColor() {
        var layout = SidebarLayout()
        layout.setColor(.orange, of: .view(ItemID("v-Reading")))
        let views = plan(library(), layout).views
        #expect(views.map(\.title) == builtIns(library()) + ["Open work", "Reading"])
        #expect(views.map(\.tone) == [.blue, .gray, .yellow, .gray, .orange])
        #expect(views.allSatisfy { $0.isShown && $0.isEnabled })
    }

    @Test func aViewDeletedInMarfaHasNoRow() {
        let library = library()
        var layout = SidebarLayout()
        layout.setColor(.teal, of: .view(ItemID("v-Reading")))
        layout.setHidden(.view(ItemID("v-Reading")), true)
        library.views.removeAll { $0.id == ItemID("v-Reading") }
        #expect(plan(library, layout).views.map(\.title) == builtIns(library) + ["Open work"])
    }

    @Test func aViewHiddenFromItsMenuIsSwitchedOffHere() {
        var layout = SidebarLayout()
        layout.take(.view(ItemID("v-Reading")))
        let row = plan(library(), layout).views.first { $0.place == .view(ItemID("v-Reading")) }
        #expect(row?.isShown == false && row?.isEnabled == true)
    }

    @Test func withTheSavedViewsHiddenAsAWholeTheirRowsStayButCannotBeSwitched() {
        var layout = SidebarLayout()
        layout.setHidden(.views, true)
        let views = plan(library(), layout).views
        #expect(views.map(\.title) == builtIns(library()) + ["Open work", "Reading"])
        #expect(views.map(\.isEnabled) == [true, true, true, false, false])
    }

    @Test func aSavedViewDraggedAboveInboxIsKeptAndTheSidebarFollows() throws {
        var layout = SidebarLayout()
        let places = plan(library(), layout).views.map(\.place)
        layout.moveViews(places, fromOffsets: [4], toOffset: 0)
        #expect(plan(library(), layout).views.first?.place == .view(ItemID("v-Reading")))
        let sidebar = SidebarPlan(library(), layout: layout).section(.views)?.shown ?? []
        #expect(sidebar.first == .view(ItemID("v-Reading")), "the sidebar's section reads the same arrangement")
        #expect(Set(sidebar) == Set(places))
    }

    /// The layout today's build stores after the views and the built-in views were each moved: the saved views come
    /// before Inbox, Recents and Favorites in `order`, and the sidebar draws the built-in ones first.
    private func storedWithSavedViewsBeforeInbox() throws -> SidebarLayout {
        let saved = Data(#"{"hidden":[],"order":["view:v-Reading","view:v-Open work","inbox","recents","favorites"]}"#.utf8)
        return try JSONDecoder().decode(SidebarLayout.self, from: saved)
    }

    /// What Settings lists and what the sidebar's Views section shows, which must agree.
    private func arrangement(_ layout: SidebarLayout) -> (settings: [String], sidebar: [String]) {
        let library = library()
        let name = { (place: SidebarPlace) in place.key }
        return (plan(library, layout).views.map(\.place).map(name), (SidebarPlan(library, layout: layout).section(.views)?.shown ?? []).map(name))
    }

    private let storedDisplay = ["inbox", "recents", "favorites", "view:v-Reading", "view:v-Open work"]

    @Test func draggingInboxInALayoutStoredBeforeTheRedesignMovesOnlyInbox() throws {
        var layout = try storedWithSavedViewsBeforeInbox()
        #expect(arrangement(layout).settings == storedDisplay)
        layout.moveViews(plan(library(), layout).views.map(\.place), fromOffsets: [0], toOffset: 5)
        let after = arrangement(layout)
        #expect(after.settings == ["recents", "favorites", "view:v-Reading", "view:v-Open work", "inbox"])
        #expect(after.sidebar == after.settings)
    }

    @Test func moveUpInALayoutStoredBeforeTheRedesignMovesOnlyThatView() throws {
        for (index, expected) in [
            (2, ["inbox", "favorites", "recents", "view:v-Reading", "view:v-Open work"]),
            (3, ["inbox", "recents", "view:v-Reading", "favorites", "view:v-Open work"]),
            (4, ["inbox", "recents", "favorites", "view:v-Open work", "view:v-Reading"]),
        ] {
            var layout = try storedWithSavedViewsBeforeInbox()
            layout.moveViews(plan(library(), layout).views.map(\.place), fromOffsets: [index], toOffset: index - 1)
            let after = arrangement(layout)
            #expect(after.settings == expected, "Move Up on row \(index)")
            #expect(after.sidebar == expected)
        }
    }

    @Test func moveDownInALayoutStoredBeforeTheRedesignMovesOnlyThatView() throws {
        for (index, expected) in [
            (0, ["recents", "inbox", "favorites", "view:v-Reading", "view:v-Open work"]),
            (2, ["inbox", "recents", "view:v-Reading", "favorites", "view:v-Open work"]),
            (3, ["inbox", "recents", "favorites", "view:v-Open work", "view:v-Reading"]),
        ] {
            var layout = try storedWithSavedViewsBeforeInbox()
            layout.moveViews(plan(library(), layout).views.map(\.place), fromOffsets: [index], toOffset: index + 2)
            let after = arrangement(layout)
            #expect(after.settings == expected, "Move Down on row \(index)")
            #expect(after.sidebar == expected)
        }
    }

    @Test func manySavedViewsStayOneListInOrderWithOneColorEach() {
        let names = (0..<300).map { "View \($0)" }
        var layout = SidebarLayout()
        layout.setColor(.red, of: .view(ItemID("v-View 299")))
        let views = plan(library(views: names), layout).views
        #expect(views.count == 303)
        #expect(views.suffix(300).map(\.title) == names)
        #expect(views.last?.tone == .red && views.last?.position == 302 && views.last?.count == 303)
    }

    // MARK: Adding a section

    @Test func aNewSectionCanHoldACollectionOrSourceWithNoRowYetAndNoOtherOne() {
        let library = library()
        let collection = FakeItemLibrary.collection("Reading list")
        library.items.append(collection)
        var layout = SidebarLayout()
        #expect(plan(library, layout).unplacedCollections.map(\.key) == [SidebarPlace.collection(collection.id).key])
        let mine = layout.addGroup(.custom, toTab: SidebarTab.homeID, id: "mine")
        layout.put(.collection(collection.id), in: mine)
        #expect(plan(library, layout).unplacedCollections.isEmpty)
    }

    // MARK: Naming

    @Test func addingATabNamesItAndMovingASectionIntoItMovesIt() {
        var layout = SidebarLayout()
        let created = SidebarNaming.newTab(moving: "types").apply(name: "  Work ", to: &layout)
        #expect(layout.allTabs.map(\.name) == ["Home", "Work"])
        #expect(created == layout.allTabs[1].id)
        #expect(layout.groups(in: layout.allTabs[1].id).map(\.id) == ["types"])
    }

    @Test func renamingATabOrASectionKeepsAnEmptyNameFromErasingIt() {
        var layout = SidebarLayout()
        #expect(SidebarNaming.renameTab(SidebarTab.homeID, current: "Home").apply(name: "Main", to: &layout) == nil)
        #expect(layout.allTabs[0].name == "Main")
        SidebarNaming.renameTab(SidebarTab.homeID, current: "Main").apply(name: "   ", to: &layout)
        #expect(layout.allTabs[0].name == "Main")
        SidebarNaming.renameGroup("library", current: "Library").apply(name: "Places", to: &layout)
        #expect(plan(library(), layout).tabs[0].sections.map(\.title) == ["Shortcuts", "Places", "Views", "Types"])
        SidebarNaming.renameGroup("library", current: "Places").apply(name: "", to: &layout)
        #expect(plan(library(), layout).tabs[0].sections[1].title == "Library")
    }

    @Test func shortcutsCannotBeRenamed() {
        #expect(plan(library()).tabs[0].sections[0].canRename == false)
    }
}
