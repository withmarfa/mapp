import Foundation
import Testing
@testable import MAPP

/// What a library reports for the sidebar: its types with their counts, and the plan the sidebar makes of them.
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
        #expect(byID["aic.project"] == 1)
        #expect(counts.allSatisfy { $0.count > 0 })
    }

    @Test func aFolderLibraryShowsFoldersAndNoTypes() {
        let library = folderLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.types.isEmpty)
        #expect(plan.library == [.projects, .folders, .recentlyDeleted])
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

    @Test func aMarfaLibraryListsTheTypesThatHoldItemsByLabel() async throws {
        let library = try await marfaLibrary()
        let counts = library.itemTypeCounts
        // Album holds nothing, so it is left out; the trashed note counts for nothing.
        #expect(counts.map(\.label) == ["Bug", "Entity", "File", "Image", "Note", "Project", "Task", "Ticket"])
        #expect(!counts.contains { $0.id == LibraryFixture.album })
    }

    @Test func aMarfaTypeCountsItsSubtypesAsItsListDoes() async throws {
        let library = try await marfaLibrary()
        let counts = Dictionary(uniqueKeysWithValues: library.itemTypeCounts.map { ($0.id, $0.count) })
        #expect(counts[LibraryFixture.ticket] == 2)
        #expect(counts[LibraryFixture.task] == 1)
        for count in library.itemTypeCounts {
            #expect(count.count == library.items(in: .itemType(count.id.rawValue)).count)
        }
    }

    @Test func aMarfaLibraryShowsTypesNotFolders() async throws {
        let library = try await marfaLibrary()
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library == [.projects, .types, .recentlyDeleted])
        #expect(!plan.types.contains { $0.id == .project })
        #expect(library.count(in: .recentlyDeleted) == 1)
    }

    @Test func anEmptyLibraryStillOffersProjectsAndRecentlyDeleted() async throws {
        let library = try await marfaLibrary([])
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.projects, .recentlyDeleted])
    }

    @Test func aCatalogueWithoutTheProjectTypeHasNoProjectsRow() async throws {
        let notesOnly = Catalogue(
            itemTypes: [LibraryFixture.catalogue.itemTypes[LibraryFixture.note]!],
            edgeTypes: Array(LibraryFixture.catalogue.edgeTypes.values))
        let library = try await marfaLibrary(
            [LibraryFixture.item(LibraryFixture.n1, LibraryFixture.note, "Plain note", age: 1)], catalogue: notesOnly)
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.types, .recentlyDeleted])
    }

    @Test func aTypeTheCatalogueGainsAppearsAfterTheOnesAlreadyPlaced() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        let before = SidebarPlan(library, layout: layout).types
        layout.move(
            before, by: { SidebarPlace.type($0.id).key }, fromOffsets: IndexSet(integer: before.count - 1), toOffset: 0)
        // Only the Ticket row has been placed (first); every other type keeps showing.
        let after = SidebarPlan(library, layout: layout)
        #expect(after.types.first?.id == LibraryFixture.ticket)
        #expect(after.shownTypes.count == before.count)
    }

    // MARK: Layout

    @Test func hidingAPlaceTakesItOutOfWhatShowsButKeepsItListed() async throws {
        let library = try await marfaLibrary()
        var layout = SidebarLayout()
        layout.setHidden(.type(LibraryFixture.entity), true)
        layout.setHidden(.recentlyDeleted, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.types.contains { $0.id == LibraryFixture.entity })
        #expect(!plan.shownTypes.contains { $0.id == LibraryFixture.entity })
        #expect(plan.shownLibrary == [.projects, .types])
        layout.setHidden(.recentlyDeleted, false)
        #expect(SidebarPlan(library, layout: layout).shownLibrary.last == .recentlyDeleted)
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
            $0.setHidden(.type(LibraryFixture.entity), true)
            $0.move([.inbox, .all], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        let layout = SidebarLayouts(defaults: defaults).layout(for: "folder:/notes")
        #expect(layout.isHidden(.type(LibraryFixture.entity)))
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
