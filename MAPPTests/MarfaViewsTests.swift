import Foundation
import Marfa
import MarfaTesting
import Synchronization
import struct MarfaCore.Item
import struct MarfaCore.KeptFetch
import Testing
@testable import MAPP

/// The views saved on the server: kept out of the items, listed in the sidebar, and each a place that lists what
/// the copy holds of its items.
@MainActor
@Suite(.hangLimit)
struct MarfaViewsTests {
    private static let planning = LibraryView(id: ItemID("view-planning"), title: "Planning")
    private static let reading = LibraryView(id: ItemID("view-reading"), title: "Reading")

    // MARK: The engine

    // The fake copy has no search, so search is checked against a server's copy in `MarfaViewsLiveTests`.

    /// A copy holding a view's row as the slice brings it, beside two notes, read through the engine.
    private static func source(views: SavedViews) -> MarfaSource {
        let stamp = "2026-10-06T00:00:00Z"
        func row(_ id: String, _ type: String, _ properties: JSONObject) -> Marfa.Item {
            Marfa.Item(
                id: id, type: type, properties: properties, state: .active, tier: .library, version: 1, schemaVersion: 1,
                source: "test", sourceId: nil, occurredAt: stamp, createdAt: stamp, updatedAt: stamp, tags: [])
        }
        let fake = WorkingCopy.fake(
            items: [
                row("n1", "core.note", ["title": "Planning the week", "body": "Monday"]),
                row("n2", "core.note", ["title": "Groceries", "body": "Planning dinner"]),
                row("view-planning", "system.view", ["title": "Planning", "query": ["types": ["core.note"]]]),
            ],
            itemTypes: SampleLibrary.itemTypes, edgeTypes: SampleLibrary.edgeTypes)
        let reading = ViewReads(read: MarfaRead(copy: fake.copy), views: views)
        let source = MarfaSource(copy: fake.copy, connection: SampleLibrary.connection, reading: reading, refreshing: reading)
        source.events.yield(.paint)
        return source
    }

    @Test func viewsStayOutOfTheItemsAndTheirCounts() async throws {
        let source = Self.source(views: SavedViews([Self.planning]))
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        #expect(library.views == [Self.planning])
        #expect(Set(library.items(in: .allNotes).map(\.id)) == [ItemID("n1"), ItemID("n2")])
        #expect(library.count(in: .allNotes) == 2)
        #expect(library.items(in: .recents).count == 2)
        #expect(library.item(ItemID("view-planning")) == nil)
        #expect(!library.itemTypeCounts.contains { $0.id.rawValue.hasPrefix("system.") })
        // A view lists only items, even where its read names a view's own row.
        #expect(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [ItemID("n1")] })
        await source.close()
    }

    @Test func aViewWhoseFilterChangesElsewhereListsAnew() async throws {
        let views = SavedViews([Self.planning])
        let source = Self.source(views: views)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [ItemID("n1")] })
        // Another device changes what the view asks for, not its title, so only its version tells it apart.
        views.members.withLock { $0["view-planning"] = ["n2"] }
        views.list.withLock { $0 = [LibraryView(id: Self.planning.id, title: Self.planning.title, version: 2)] }
        source.events.yield(.change(Change(origin: .server(event: "item.updated", cursor: "2"), itemId: Self.planning.id.rawValue, edgeId: nil)))
        #expect(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [ItemID("n2")] })
        await source.close()
    }

    /// A hydration under way answers the views that have arrived, so a view not yet back is not taken as deleted.
    @Test func viewsReadPartwayThroughAHydrationKeepTheOnesAlreadyRead() async throws {
        let views = SavedViews([Self.planning])
        let source = Self.source(views: views)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.views == [Self.planning] })
        let browser = Browser()
        browser.show(.view(Self.planning.id), in: library, order: NoteOrder())

        views.completeness.withLock { $0 = .partial }
        views.list.withLock { $0 = [Self.reading] }
        source.events.yield(.change(Change(origin: .refreshed(.unfinished), itemId: nil, edgeId: nil)))
        #expect(await eventually { library.views == [Self.planning, Self.reading] })
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .view(Self.planning.id))

        // Once whole, the answer is what the copy holds.
        views.completeness.withLock { $0 = .complete }
        source.events.yield(.change(Change(origin: .refreshed(.hydrated), itemId: nil, edgeId: nil)))
        #expect(await eventually { library.views == [Self.reading] })
        await source.close()
    }

    @Test func aViewDeletedElsewhereLeavesTheSidebarAndItsPlace() async throws {
        let views = SavedViews([Self.planning])
        let source = Self.source(views: views)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.views == [Self.planning] })
        let browser = Browser()
        browser.show(.view(Self.planning.id), in: library, order: NoteOrder())
        views.list.withLock { $0 = [] }
        // As the copy tells of a view deleted through it; the engine reads the views again for the view's id.
        source.events.yield(.change(Change(origin: .refreshed(.purged), itemId: Self.planning.id.rawValue, edgeId: nil)))
        #expect(await eventually { library.views.isEmpty })
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .allNotes)
        #expect(SidebarPlan(library, layout: SidebarLayout()).library.contains(.views) == false)
        await source.close()
    }

    // MARK: The library

    private static func loaded(views: [LibraryView]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue, views: views)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func theSidebarListsTheViewsAfterTypesAndNoneWithoutThem() async throws {
        let (library, source) = try await Self.loaded(views: [Self.planning, Self.reading])
        let plan = SidebarPlan(library, layout: SidebarLayout())
        #expect(plan.library == [.types, .views])
        #expect(library.views.map(\.title) == ["Planning", "Reading"])
        #expect(library.name(of: .view(Self.reading.id)) == "Reading")

        // A view renamed elsewhere is named anew; a view gone has no place and no name.
        source.send(.views([LibraryView(id: Self.planning.id, title: "This Week")]))
        #expect(await eventually { library.views.map(\.title) == ["This Week"] })
        #expect(library.name(of: .view(Self.reading.id)) == "")

        source.send(.views([]))
        #expect(await eventually { library.views.isEmpty })
        #expect(SidebarPlan(library, layout: SidebarLayout()).library == [.types])
    }

    @Test func aViewHiddenFromTheSidebarStaysListedForSettings() async throws {
        let (library, _) = try await Self.loaded(views: [Self.planning])
        var layout = SidebarLayout()
        layout.setHidden(.views, true)
        let plan = SidebarPlan(library, layout: layout)
        #expect(plan.library.contains(.views))
        #expect(!plan.shownLibrary.contains(.views))
    }

    @Test func selectingAViewListsWhatTheCopyHoldsOfIt() async throws {
        let F = LibraryFixture.self
        let (library, source) = try await Self.loaded(views: [Self.planning])
        // An id the library does not hold, such as one the copy has not read yet, is not listed.
        source.viewMembers.withLock { $0[Self.planning.id] = [F.n1, F.t1, ItemID("not-held")] }
        #expect(await eventually { Set(library.items(in: .view(Self.planning.id)).map(\.id)) == [F.n1, F.t1] })
        #expect(library.count(in: .view(Self.planning.id)) == 2)

        // A change to the items reads the view again.
        source.viewMembers.withLock { $0[Self.planning.id] = [F.n1] }
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Other"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [F.n1] })
    }

    @Test func aChangedViewDropsItsListAndTheOthersKeepTheirs() async throws {
        let F = LibraryFixture.self
        let (library, source) = try await Self.loaded(views: [Self.planning, Self.reading])
        source.viewMembers.withLock { $0 = [Self.planning.id: [F.n1], Self.reading.id: [F.t1]] }
        #expect(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [F.n1] })
        #expect(await eventually { library.items(in: .view(Self.reading.id)).map(\.id) == [F.t1] })

        // Neither can be read again, so each shows what it kept: nothing for the view that changed.
        source.viewFails.withLock { $0 = true }
        let reads = source.viewReads.withLock { $0 }
        source.send(.views([LibraryView(id: Self.planning.id, title: Self.planning.title, version: 2), Self.reading]))
        #expect(await eventually {
            _ = library.items(in: .view(Self.planning.id))
            _ = library.items(in: .view(Self.reading.id))
            return source.viewReads.withLock { $0 } >= reads + 2
        })
        #expect(await eventually { library.items(in: .view(Self.planning.id)).isEmpty })
        #expect(library.items(in: .view(Self.reading.id)).map(\.id) == [F.t1])
    }

    @Test func aViewTheCopyCannotAnswerKeepsItsListAndSaysSoOnce() async throws {
        let F = LibraryFixture.self
        let (library, source) = try await Self.loaded(views: [Self.planning])
        source.viewMembers.withLock { $0[Self.planning.id] = [F.n1] }
        #expect(await eventually { library.items(in: .view(Self.planning.id)).map(\.id) == [F.n1] })

        source.viewFails.withLock { $0 = true }
        for title in ["Other", "Another"] {
            var renamed = try #require(library.item(F.n2))
            renamed.title = title
            let reads = source.viewReads.withLock { $0 }
            source.send(.upserted([renamed]))
            #expect(await eventually {
                _ = library.items(in: .view(Self.planning.id))
                return source.viewReads.withLock { $0 } > reads
            })
        }
        #expect(await eventually { library.notices.waiting.count == 1 })
        #expect(library.notices.waiting.first?.title == String(localized: "Can’t Show This View"))
        #expect(library.items(in: .view(Self.planning.id)).map(\.id) == [F.n1])
    }

    // MARK: The window

    @Test func aViewRemovedWhileSelectedFallsBackToItems() {
        let library = FakeItemLibrary(items: [])
        library.views = [Self.planning]
        let browser = Browser()
        browser.show(.view(Self.planning.id), in: library, order: NoteOrder())
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .view(Self.planning.id))

        library.views = []
        browser.placeRemoved(in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .allNotes)
    }

    @Test func aWindowRestoresAViewOnlyWhileItIsThere() {
        let library = FakeItemLibrary(items: [])
        let snapshot = Browser.Snapshot(place: .view(Self.planning.id), selection: [])
        let browser = Browser()
        browser.restore(snapshot, in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .allNotes)
        library.views = [Self.planning]
        browser.restore(snapshot, in: library, order: NoteOrder())
        #expect(browser.sidebarItem == .view(Self.planning.id))
    }
}

/// The views the server holds, which a test changes as another device would.
private nonisolated final class SavedViews: Sendable {
    let list: Mutex<[LibraryView]>
    /// The ids each view lists, as the copy answers them.
    let members = Mutex<[String: [String]]>(["view-planning": ["n1", "view-planning"]])
    let completeness = Mutex(Completeness.complete)
    init(_ views: [LibraryView]) { list = Mutex(views) }
}

/// Reads the fake copy, which holds no views of its own, answering the views and their items as the copy would.
private nonisolated struct ViewReads: MarfaReading, MarfaRefreshing {
    let read: MarfaRead
    let views: SavedViews

    func status() async throws -> Status { try await readStatus() }
    func items() async throws -> Rows<Marfa.Item> { try await read.items() }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] { try await read.edges(ofTypes: types) }
    func edges(touching id: String) async throws -> [Marfa.Edge] { try await read.edges(touching: id) }
    func views() async throws -> Rows<LibraryView> {
        Rows(views.list.withLock { $0 }, completeness: views.completeness.withLock { $0 })
    }
    func items(inView id: String) async throws -> [Marfa.Item] {
        let ids = views.members.withLock { $0[id] ?? [] }
        return try await read.items().rows.filter { ids.contains($0.id) }
    }

    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        throw FakeCopyError.unsupported(call: "hydrate")
    }
    func catchUp() async throws {}
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
}
