import Foundation
import Testing
@testable import MAPP

/// What a library reports for the sidebar: its collections, its types with their counts and how they nest, and the
/// plan the sidebar makes of them.
@MainActor
struct SidebarTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Marfa library

    func marfaLibrary(_ items: [Item] = LibraryFixture.items, catalogue: Catalogue = LibraryFixture.catalogue) async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    @Test func aMarfaLibraryListsTheTypesThatDirectlyHoldItemsMostFirst() async throws {
        let library = try await marfaLibrary()
        let counts = library.itemTypeCounts
        // Note and Project hold two. Ticket and Album hold none themselves, the trashed note counts for nothing and
        // the file types are reached through All Items.
        #expect(counts.map(\.label) == ["Note", "Project", "Bug", "Entity", "Task"])
        #expect(counts.map(\.count) == [2, 2, 1, 1, 1])
        // Project, Bug and Task descend from Note and take its symbol; Entity has no built-in symbol.
        #expect(counts.map(\.symbol) == ["doc.text", "doc.text", "doc.text", "doc", "doc.text"])
    }

    @Test func aMarfaTypeCountsOnlyItsOwnItemsAndItsListAgrees() async throws {
        let library = try await marfaLibrary()
        let counts = Dictionary(uniqueKeysWithValues: library.itemTypeCounts.map { ($0.id, $0.count) })
        #expect(counts[LibraryFixture.ticket] == nil)
        #expect(counts[LibraryFixture.task] == 1)
        #expect(counts[LibraryFixture.note] == 2)
        for count in library.itemTypeCounts {
            #expect(count.count == library.items(in: .itemType(count.id.rawValue)).count)
        }
    }

    @Test func twoShownTypesWithOneLabelNameTheirParents() async throws {
        var catalogue = LibraryFixture.catalogue
        catalogue.itemTypes[TypeID("core.task")] = ItemTypeInfo(
            id: TypeID("core.task"), label: "Task", fields: [], titleField: nil, bodyField: nil, parent: nil)
        let items = LibraryFixture.items + [
            LibraryFixture.item(ItemID("ct1"), TypeID("core.task"), "Core task", age: 20),
            LibraryFixture.item(ItemID("ct2"), TypeID("core.task"), "Another core task", age: 21),
            LibraryFixture.item(ItemID("ct3"), TypeID("core.task"), "A third", age: 22),
        ]
        let library = try await marfaLibrary(items, catalogue: catalogue)
        let labels = Dictionary(uniqueKeysWithValues: library.itemTypeCounts.map { ($0.id.rawValue, $0.label) })
        #expect(labels["aic.ticket.task"] == "Task (Ticket)")
        // A type with no parent has nothing to add, and the rest keep their own labels.
        #expect(labels["core.task"] == "Task")
        #expect(labels["aic.ticket.bug"] == "Bug")
        #expect(library.itemTypeCounts.first?.id == TypeID("core.task"))
        // Nested under Ticket, the ticket's task needs no parent's name.
        let ticket = try #require(library.typeTree.first { $0.id == "aic.ticket" })
        #expect(ticket.children.map(\.label) == ["Bug", "Task"])
    }

    // MARK: Nesting

    @Test func typesNestByTheirIdentifiers() async throws {
        let library = try await marfaLibrary()
        let tree = library.typeTree
        // Each branch is ordered by all the items under it, then by label.
        #expect(tree.map(\.id) == ["core.note", "aic.project", "aic.ticket", "core.entity"])
        let ticket = try #require(tree.first { $0.id == "aic.ticket" })
        #expect(ticket.type == LibraryFixture.ticket)
        #expect(ticket.count == 0)
        #expect(ticket.total == 2)
        // Ticket holds nothing itself, so its row only folds open.
        #expect(!ticket.opens)
        #expect(ticket.children.map(\.id) == ["aic.ticket.bug", "aic.ticket.task"])
        #expect(ticket.children.allSatisfy { $0.opens && $0.children.isEmpty })
        #expect(tree.first { $0.id == "core.note" }?.children.isEmpty == true)
    }

    static func agentCatalogue(_ types: [String: String]) -> Catalogue {
        Catalogue(itemTypes: types.map { id, label in
            ItemTypeInfo(id: TypeID(id), label: label, fields: [], titleField: nil, bodyField: nil, parent: nil)
        })
    }

    static func counts(_ counts: [String: Int], in catalogue: Catalogue) -> [ItemTypeCount] {
        counts.map { id, count in
            ItemTypeCount(id: TypeID(id), label: TypeSymbol.label(for: TypeID(id), in: catalogue), symbol: "doc", count: count)
        }
    }

    @Test func typesThatShareAStemThatIsNoTypeAreGroupedUnderIt() throws {
        let catalogue = Self.agentCatalogue(["aic.agent.session": "Agent session", "aic.agent.log": "Agent log"])
        let tree = TypeNode.tree(of: Self.counts(["aic.agent.session": 3, "aic.agent.log": 5], in: catalogue), in: catalogue)
        #expect(tree.count == 1)
        let agent = try #require(tree.first)
        #expect(agent.id == "aic.agent")
        #expect(agent.type == nil)
        #expect(agent.label == "Agent")
        #expect(!agent.opens)
        #expect(agent.total == 8)
        // A row under its group drops the words it repeats.
        #expect(agent.children.map(\.label) == ["Log", "Session"])
        #expect(agent.children.map(\.count) == [5, 3])
    }

    @Test func aGroupOfOneGivesWayToItsRowUnderItsFullName() {
        let catalogue = Self.agentCatalogue(["aic.agent.log": "Agent log", "core.note": "Note"])
        let tree = TypeNode.tree(of: Self.counts(["aic.agent.log": 2, "core.note": 1], in: catalogue), in: catalogue)
        #expect(tree.map(\.id) == ["aic.agent.log", "core.note"])
        #expect(tree.map(\.label) == ["Agent log", "Note"])
        #expect(tree.allSatisfy { $0.children.isEmpty && $0.opens })
    }

    @Test func aLabelThatDoesNotRepeatItsParentStaysWhole() throws {
        let catalogue = Self.agentCatalogue(["aic.ticket": "Ticket", "aic.ticket.spike": "Question", "aic.ticket.task": "Ticket task"])
        let tree = TypeNode.tree(
            of: Self.counts(["aic.ticket": 1, "aic.ticket.spike": 1, "aic.ticket.task": 1], in: catalogue), in: catalogue)
        #expect(tree.count == 1)
        let ticket = try #require(tree.first)
        #expect(ticket.opens)
        #expect(ticket.count == 1)
        #expect(ticket.total == 3)
        #expect(ticket.children.map(\.label) == ["Question", "Task"])
    }

    // MARK: Collections

    @Test func theCollectionsIndexListsContainerItemsByTitle() {
        let project = FakeItemLibrary.note("Project", modified: start)
        var child = FakeItemLibrary.note("Child", modified: start)
        child.edgesOut = [Edge(id: EdgeID("c"), type: "child-of", source: child.id, target: .item(project.id), origin: .property("child-of"))]
        let library = FakeItemLibrary(items: [
            project, child, FakeItemLibrary.collection("Reading"), FakeItemLibrary.collection("Home"),
            FakeItemLibrary.collection("Gone", state: .trashed),
        ])
        // An item other items are filed under is no collection; only a container type's items are.
        #expect(library.collections.map(\.title) == ["Home", "Reading"])
    }

    @Test func aMarfaLibraryWithoutAContainerHasNoCollections() async throws {
        let library = try await marfaLibrary()
        // Alpha holds Epic task through `child-of`, which once made it a collection.
        #expect(library.collections.isEmpty)
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.types])
    }

    @Test func aTypeWhoseLastItemGoesLeavesTheListAndTheWindowMovesToAllItems() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let browser = Browser()
        browser.show(.itemType(LibraryFixture.entity.rawValue), in: library, order: NoteOrder())
        #expect(browser.item == .itemType(LibraryFixture.entity.rawValue))
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .itemType(LibraryFixture.entity.rawValue))
        source.send(.removed([LibraryFixture.en1]))
        try #require(await eventually { library.isGone(LibraryFixture.en1) })
        #expect(!library.itemTypeCounts.contains { $0.id == LibraryFixture.entity })
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
    }

    @Test func theTypesToMakeAreEveryCatalogueTypeButFilesByLabel() async throws {
        let library = try await marfaLibrary()
        let types = library.creatableTypes
        #expect(types.map(\.label) == ["Album", "Bug", "Entity", "Note", "Project", "Task", "Ticket"])
        #expect(types.first { $0.id == LibraryFixture.project }?.symbol == "doc.text")
        #expect(types.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func aLibraryShowsItsTypesWithoutFiles() async throws {
        let library = try await marfaLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library == [.types])
        #expect(!plan.types.contains { $0.type.map(library.catalogue.isFileType) == true })
        #expect(library.count(in: .recentlyDeleted) == 1)
    }

    @Test func anEmptyLibraryHasNoSectionsBelowTheTop() async throws {
        let library = try await marfaLibrary([])
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library.isEmpty)
        #expect(plan.top == [.inbox, .recents, .favorites])
        #expect(plan.browse == [.all, .sources, .collections])
    }

    @Test func filesStayUnderItemsWithoutAddingAnotherSidebarDestination() async throws {
        let library = try await marfaLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.top + plan.browse == [.inbox, .recents, .favorites, .all, .sources, .collections])
    }

    @Test func recentsListsTheItemsEditedMostRecentlyUpToTheLimit() {
        let notes = (0..<40).map { FakeItemLibrary.note("Note \($0)", modified: start.addingTimeInterval(Double($0))) }
        let gone = FakeItemLibrary.note("Gone", modified: start.addingTimeInterval(100), state: .trashed)
        let library = FakeItemLibrary(items: notes + [gone])
        let recents = library.items(in: .recents)
        #expect(recents.count == FakeItemLibrary.recentLimit)
        #expect(recents.first?.title == "Note 39")
        #expect(!recents.contains { $0.id == gone.id })
    }

    @Test func eachLibrarysRecentsFollowsItsEdits() async throws {
        let library = try await marfaLibrary()
        #expect(library.count(in: .recents) == library.items(in: .recents).count)
    }

    @Test func aLibraryWithNothingFiledHasNoCollectionsSection() async throws {
        let library = try await marfaLibrary([LibraryFixture.item(LibraryFixture.n1, LibraryFixture.note, "Plain note", age: 1)])
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.types])
    }

    @Test func aTypeTheCatalogueGainsAppearsAfterTheOnesAlreadyPlaced() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        let before = SidebarPlan(library, layout: layout).types
        layout.move(
            before, by: { SidebarPlace.type($0.id).key }, fromOffsets: IndexSet(integer: before.count - 1), toOffset: 0)
        // Only the last row has been placed (first); every other type keeps showing.
        let after = SidebarPlan(library, layout: layout)
        #expect(after.types.first?.id == before.last?.id)
        #expect(after.shownTypes.count == before.count)
    }

    // MARK: Views

    private func viewsLibrary(_ titles: [String]) -> FakeItemLibrary {
        let library = FakeItemLibrary(items: [])
        library.views = LibraryView.ordered(titles.map { LibraryView(id: ItemID("v-" + $0), title: $0) })
        return library
    }

    private func titles(_ views: [LibraryView]) -> [String] { views.map(\.title) }
    private let viewKey: (LibraryView) -> String = { SidebarPlace.view($0.id).key }

    @Test func viewsStayInTitleOrderUntilThePersonMovesOne() {
        let library = viewsLibrary(["Cats", "Apples", "Bears"])
        #expect(titles(SidebarPlan(library, layout: SidebarLayout()).views) == ["Apples", "Bears", "Cats"])
    }

    @Test func aMovedViewKeepsItsPlaceAndANewViewFollowsThePlacedOnes() {
        let library = viewsLibrary(["Apples", "Bears", "Cats"])
        var layout = SidebarLayout()
        let plan = SidebarPlan(library, layout: layout)
        layout.move(plan.views, shown: plan.shownViews, by: viewKey, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(titles(SidebarPlan(library, layout: layout).views) == ["Cats", "Apples", "Bears"])
        library.views = LibraryView.ordered(library.views + [LibraryView(id: ItemID("v-Aardvarks"), title: "Aardvarks")])
        #expect(titles(SidebarPlan(library, layout: layout).views) == ["Cats", "Apples", "Bears", "Aardvarks"])
    }

    @Test func hidingOneViewLeavesTheOthersAndTheSectionShown() {
        let library = viewsLibrary(["Apples", "Bears"])
        var layout = SidebarLayout()
        layout.setHidden(.view(ItemID("v-Apples")), true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(titles(plan.shownViews) == ["Bears"])
        #expect(titles(plan.views) == ["Apples", "Bears"])
        #expect(plan.shownLibrary == [.views])
        layout.setHidden(.view(ItemID("v-Apples")), false)
        #expect(titles(SidebarPlan(library, layout: layout).shownViews) == ["Apples", "Bears"])
    }

    @Test func theSectionGoesWhenEveryViewIsHiddenOrTheSectionIsHidden() {
        let library = viewsLibrary(["Apples", "Bears"])
        var layout = SidebarLayout()
        layout.setHidden(.view(ItemID("v-Apples")), true)
        layout.setHidden(.view(ItemID("v-Bears")), true)
        #expect(SidebarPlan(library, layout: layout).shownLibrary.isEmpty)
        #expect(SidebarPlan(library, layout: layout).library == [.views])
        var section = SidebarLayout()
        section.setHidden(.views, true)
        #expect(SidebarPlan(library, layout: section).shownLibrary.isEmpty)
    }

    @Test func aViewDeletedOnTheServerDropsOut() {
        let library = viewsLibrary(["Apples", "Bears", "Cats"])
        var layout = SidebarLayout()
        let plan = SidebarPlan(library, layout: layout)
        layout.move(plan.views, shown: plan.shownViews, by: viewKey, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        layout.setHidden(.view(ItemID("v-Bears")), true)
        library.views.removeAll { $0.title == "Cats" || $0.title == "Bears" }
        let after = SidebarPlan(library, layout: layout)
        #expect(titles(after.views) == ["Apples"])
        #expect(titles(after.shownViews) == ["Apples"])
    }

    @Test func movingAmongTheShownViewsKeepsAHiddenOneInItsSlot() {
        let library = viewsLibrary(["Apples", "Bears", "Cats", "Dogs"])
        var layout = SidebarLayout()
        layout.setHidden(.view(ItemID("v-Bears")), true)
        let plan = SidebarPlan(library, layout: layout)
        // Shown: Apples, Cats, Dogs. Dogs moves to the top.
        layout.move(plan.views, shown: plan.shownViews, by: viewKey, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let after = SidebarPlan(library, layout: layout)
        #expect(titles(after.shownViews) == ["Dogs", "Apples", "Cats"])
        #expect(titles(after.views) == ["Dogs", "Bears", "Apples", "Cats"])
    }

    @Test func aViewsPlaceSurvivesRelaunch() {
        let defaults = UserDefaults(suiteName: "SidebarTests.views")!
        defaults.removePersistentDomain(forName: "SidebarTests.views")
        SidebarLayouts(defaults: defaults).update("marfa:one") { $0.setHidden(.view(ItemID("v-Apples")), true) }
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isHidden(.view(ItemID("v-Apples"))))
        #expect(!SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isHidden(.view(ItemID("v-Bears"))))
    }

    // MARK: Layout

    @Test func aSectionCollapsedForOneLibraryStaysCollapsedForThatLibraryOnly() {
        let defaults = UserDefaults(suiteName: "SidebarTests.collapsed")!
        defaults.removePersistentDomain(forName: "SidebarTests.collapsed")
        defer { defaults.removePersistentDomain(forName: "SidebarTests.collapsed") }
        let layouts = SidebarLayouts(defaults: defaults)
        layouts.update("marfa:one") { $0.setCollapsed(.types, true) }
        #expect(SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isCollapsed(.types))
        #expect(!SidebarLayouts(defaults: defaults).layout(for: "marfa:one").isCollapsed(.collections))
        #expect(!layouts.layout(for: "marfa:two").isCollapsed(.types))
    }

    @Test func aLayoutSavedWithoutCollapsedSectionsStillReads() throws {
        let saved = Data(#"{"hidden":["favorites"],"order":["inbox"]}"#.utf8)
        let layout = try JSONDecoder().decode(SidebarLayout.self, from: saved)
        #expect(layout.isHidden(.favorites))
        #expect(!layout.isCollapsed(.favorites))
    }

    @Test func hidingAPlaceTakesItOutOfWhatShowsButKeepsItListed() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.entity.rawValue), true)
        layout.setHidden(.collections, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.types.contains { $0.type == LibraryFixture.entity })
        #expect(!plan.shownTypes.contains { $0.type == LibraryFixture.entity })
        #expect(plan.shownLibrary == [.types])
        layout.setHidden(.collections, false)
        #expect(SidebarPlan(library, layout: layout).shownBrowse.contains(.collections))
    }

    @Test func hidingAPlaceTakesItOutOfBrowseWhileTheRestKeepTheirOrder() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.sources, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.shownBrowse == [.all, .collections])
        #expect(plan.browse == [.all, .sources, .collections])
    }

    @Test func showAllTypesBringsBackTypesAndLeavesOtherPlacesHidden() {
        var layout = SidebarLayout()
        layout.setHidden(.type("aic.ticket"), true)
        layout.setHidden(.type("core.note"), true)
        layout.setHidden(.sources, true)
        #expect(layout.hidesTypes)
        layout.showAllTypes()
        #expect(!layout.hidesTypes)
        #expect(layout.isHidden(.sources))
    }

    @Test func hidingARowHidesWhatIsUnderIt() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.bug.rawValue), true)
        let ticket = SidebarPlan(library, layout: layout).shownTypes.first { $0.id == "aic.ticket" }
        #expect(ticket?.children.map(\.id) == ["aic.ticket.task"])
        layout.setHidden(.type(LibraryFixture.ticket.rawValue), true)
        #expect(!SidebarPlan(library, layout: layout).shownTypes.contains { $0.id == "aic.ticket" })
    }

    @Test func movingPlacesReordersThemWithinTheirGroup() {
        var layout = SidebarLayout()
        layout.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(layout.ordered([.inbox, .all]) == [.all, .inbox])
        layout.move([.all, .inbox], fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(layout.ordered([.inbox, .all]) == [.inbox, .all])
    }

    @Test func aLayoutKeptForOneLibraryDoesNotChangeAnother() {
        let defaults = UserDefaults(suiteName: "SidebarTests.separate")!
        defaults.removePersistentDomain(forName: "SidebarTests.separate")
        defer { defaults.removePersistentDomain(forName: "SidebarTests.separate") }
        let layouts = SidebarLayouts(defaults: defaults)
        layouts.update("marfa:one") { $0.setHidden(.favorites, true) }
        #expect(layouts.layout(for: "marfa:one").isHidden(.favorites))
        #expect(!layouts.layout(for: "marfa:two").isHidden(.favorites))
    }

    @Test func aLayoutIsFoundAgainByANewStore() {
        let defaults = UserDefaults(suiteName: "SidebarTests.persist")!
        defaults.removePersistentDomain(forName: "SidebarTests.persist")
        defer { defaults.removePersistentDomain(forName: "SidebarTests.persist") }
        SidebarLayouts(defaults: defaults).update("marfa:one") {
            $0.setHidden(.type(LibraryFixture.entity.rawValue), true)
            $0.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        let layout = SidebarLayouts(defaults: defaults).layout(for: "marfa:one")
        #expect(layout.isHidden(.type(LibraryFixture.entity.rawValue)))
        #expect(layout.ordered([.inbox, .all]) == [.all, .inbox])
    }

    @Test func aStoredLayoutThatCannotBeReadLeavesTheDefault() {
        let defaults = UserDefaults(suiteName: "SidebarTests.unreadable")!
        defaults.removePersistentDomain(forName: "SidebarTests.unreadable")
        defer { defaults.removePersistentDomain(forName: "SidebarTests.unreadable") }
        defaults.set(Data("not json".utf8), forKey: "sidebarLayouts")
        #expect(SidebarLayouts(defaults: defaults).layout(for: "any") == SidebarLayout())
    }
}
