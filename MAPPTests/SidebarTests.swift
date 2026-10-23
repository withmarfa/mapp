import Foundation
import Testing
@testable import MAPP

/// What a library reports for the sidebar: its collections, its types with their counts and how they nest, and the
/// plan the sidebar makes of them.
@MainActor
struct SidebarTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Folder library

    func folderLibrary() -> NoteLibrary {
        func note(_ name: String, type: String? = nil, deleted: Bool = false) -> Note {
            let front = type.map { "---\ntype: \($0)\n---\n" } ?? ""
            return Note(
                path: "\(name).md", text: front + "# \(name)\n", created: start, deleted: deleted ? start : nil)
        }
        return NoteLibrary(
            notes: [
                note("One", type: "aic.ticket.task"), note("Two", type: "aic.ticket.task"),
                note("Three", type: "aic.ticket.feature"), note("Plan", type: "aic.project"), note("Plain"),
                note("Gone", type: "aic.ticket.feature", deleted: true),
            ],
            folders: [], store: RecordingStore(), now: { start })
    }

    @Test func aFolderLibraryCountsEachTypeExactly() {
        let counts = folderLibrary().itemTypeCounts
        let byID = Dictionary(uniqueKeysWithValues: counts.map { ($0.id.rawValue, $0.count) })
        #expect(byID["aic.ticket.task"] == 2)
        #expect(byID["aic.ticket.feature"] == 1)
        // No type is special: a project is counted like any other.
        #expect(byID["aic.project"] == 1)
        #expect(counts.map(\.label) == ["Task", "Feature", "Note", "Project"])
        #expect(counts.allSatisfy { $0.count > 0 })
    }

    @Test func aFolderLibraryShowsFoldersAndNoTypes() {
        let library = folderLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.types.isEmpty)
        // Nothing is filed under anything, so there is no Collections section.
        #expect(plan.collections.isEmpty)
        #expect(plan.library == [.folders])
    }

    @Test func recentlyDeletedCountsWhatTheBinHolds() {
        #expect(folderLibrary().count(in: .recentlyDeleted) == 1)
        #expect(NoteLibrary(notes: [], folders: [], store: RecordingStore(), now: { start }).count(in: .recentlyDeleted) == 0)
    }

    // MARK: Marfa library

    func marfaLibrary(_ items: [Item] = LibraryFixture.items, catalogue: Catalogue = LibraryFixture.catalogue) async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue, places: [])))
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
        #expect(counts.map(\.symbol) == ["doc.text", "square.stack", "ticket", "doc", "checkmark.circle"])
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

    func filed(_ title: String, under parent: Item? = nil, state: ItemState = .active) -> Item {
        var item = FakeItemLibrary.note(title, modified: start, state: state)
        item.tier = .library
        if let parent {
            item.edgesOut = [Edge(id: EdgeID(title), type: "child-of", source: item.id, target: .item(parent.id), origin: .property("child-of"))]
        }
        return item
    }

    @Test func aCollectionIsAnythingOtherItemsAreFiledUnder() async throws {
        let library = try await marfaLibrary()
        let tree = library.collectionTree
        // Alpha holds Epic task, which holds Bug one. Beta, with nothing filed under it, is no collection.
        #expect(tree.map(\.title) == ["Alpha"])
        #expect(tree.first?.symbol == "square.stack")
        #expect(tree.first?.children.map(\.title) == ["Epic task"])
        #expect(tree.first?.children.first?.symbol == "checkmark.circle")
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.types, .collections])
    }

    @Test func theSidebarShowsTwoLevelsOfCollectionsByTitle() {
        let root = filed("Root")
        let b = filed("B", under: root), a = filed("A", under: root)
        let deep = filed("Deep", under: a)
        let leaf = filed("Leaf", under: deep)
        let loose = filed("Loose")
        let library = FakeItemLibrary(items: [root, b, a, deep, leaf, loose, filed("Under B", under: b)])
        let tree = library.collectionTree
        #expect(tree.map(\.title) == ["Root"])
        #expect(tree.first?.children.map(\.title) == ["A", "B"])
        // Deep holds an item, but sits a third level down, which the collection's own list reaches.
        #expect(tree.first?.children.allSatisfy(\.children.isEmpty) == true)
    }

    @Test func aCollectionFiledUnderOneInTheBinStandsAtTheTop() {
        let gone = filed("Gone", state: .trashed)
        let kept = filed("Kept", under: gone)
        let library = FakeItemLibrary(items: [gone, kept, filed("Child", under: kept)])
        #expect(library.collectionTree.map(\.title) == ["Kept"])
    }

    @Test func anItemFiledUnderItselfIsNoCollection() {
        var item = filed("Self")
        item.edgesOut = [Edge(id: EdgeID("loop"), type: "child-of", source: item.id, target: .item(item.id), origin: .property("child-of"))]
        #expect(FakeItemLibrary(items: [item]).collectionTree.isEmpty)
    }

    @Test func aTypeWhoseLastItemGoesLeavesTheListAndTheWindowMovesToAllItems() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue, places: [])))
        try #require(await eventually { library.isLoaded })
        let browser = Browser()
        browser.show(.itemType(LibraryFixture.entity.rawValue), in: library, order: NoteOrder())
        #expect(browser.item == .itemType(LibraryFixture.entity.rawValue))
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .itemType(LibraryFixture.entity.rawValue))
        source.send(.removed([LibraryFixture.en1]))
        try #require(await eventually { library.isGone(LibraryFixture.en1) })
        #expect(!library.itemTypeCounts.contains { $0.id == LibraryFixture.entity })
        browser.folderRemoved(in: library, order: NoteOrder())
        #expect(browser.item == .allNotes)
    }

    @Test func theNewItemMenuListsEveryCatalogueTypeButFilesByLabel() async throws {
        let library = try await marfaLibrary()
        let types = library.creatableTypes
        #expect(types.map(\.label) == ["Album", "Bug", "Entity", "Note", "Project", "Task", "Ticket"])
        #expect(types.first { $0.id == LibraryFixture.project }?.symbol == "square.stack")
        #expect(types.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func aMarfaLibraryShowsTypesNotFolders() async throws {
        let library = try await marfaLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library == [.types, .collections])
        #expect(!plan.types.contains { $0.type.map(library.catalogue.isFileType) == true })
        #expect(library.count(in: .recentlyDeleted) == 1)
    }

    @Test func anEmptyLibraryHasNoSectionsBelowTheTop() async throws {
        let library = try await marfaLibrary([])
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library.isEmpty)
        #expect(plan.top == [.inbox, .recents, .all])
    }

    @Test func filesJoinTheTopWhereTheLibraryHoldsAny() async throws {
        let library = try await marfaLibrary()
        #expect(SidebarPlan(library, layout: SidebarLayout()).top == [.inbox, .recents, .all, .files])
        #expect(SidebarPlan(folderLibrary(), layout: SidebarLayout()).top == [.inbox, .recents, .all])
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
        let folder = folderLibrary()
        #expect(folder.count(in: .recents) == folder.items(in: .recents).count)
        #expect(folder.items(in: .recents).count == 5)
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
        #expect(SidebarPlan(library, layout: layout).shownLibrary == [.types, .collections])
    }

    @Test func hidingARowHidesWhatIsUnderIt() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.bug.rawValue), true)
        let ticket = SidebarPlan(library, layout: layout).shownTypes.first { $0.id == "aic.ticket" }
        #expect(ticket?.children.map(\.id) == ["aic.ticket.task"])
        layout.setHidden(.type(LibraryFixture.ticket.rawValue), true)
        #expect(!SidebarPlan(library, layout: layout).shownTypes.contains { $0.id == "aic.ticket" })

        let alpha = try #require(library.collectionTree.first)
        layout.setHidden(.collection(try #require(alpha.children.first).id), true)
        #expect(SidebarPlan(library, layout: layout).shownCollections.first?.children.isEmpty == true)
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
        SidebarLayouts(defaults: defaults).update("folder:/notes") {
            $0.setHidden(.type(LibraryFixture.entity.rawValue), true)
            $0.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        let layout = SidebarLayouts(defaults: defaults).layout(for: "folder:/notes")
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
