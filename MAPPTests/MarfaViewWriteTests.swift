import Foundation
import Synchronization
import Testing
@testable import MAPP

/// Saving, changing and deleting views, which go to the server at once and are never queued.
@MainActor
@Suite(.hangLimit)
struct MarfaViewWriteTests {
    private static let settings = LibraryViewSettings(
        title: "Open Tasks", query: LibraryViewQuery(types: [TypeID("core.task")], states: [.active]),
        sort: [LibraryViewSort(field: "updated_at", ascending: false)], group: LibraryViewGroup(field: "properties.status"))

    private static func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        source.state.set(.online)
        try #require(await eventually { library.canEditViews })
        return (library, source)
    }

    @Test func aSavedViewIsListedAtOnce() async throws {
        let (library, source) = try await Self.loaded()
        let view = try #require(await library.createView(Self.settings))
        #expect(view.settings == Self.settings)
        #expect(library.views.map(\.id) == [view.id])
        #expect(source.savedViews.withLock { $0[view.id] } == view)
    }

    @Test func aRenameAndAnUpdateNameOnlyWhatChanged() async throws {
        let (library, source) = try await Self.loaded()
        let view = try #require(await library.createView(Self.settings))
        let renamed = try await library.changeView(view.id, LibraryViewChange(title: "Doing"), baseVersion: view.version).get()
        #expect(renamed.title == "Doing")
        #expect(renamed.sort == Self.settings.sort)
        #expect(renamed.version == view.version + 1)
        let ungrouped = try await library.changeView(view.id, LibraryViewChange(group: .clear), baseVersion: renamed.version).get()
        #expect(ungrouped.group == nil)
        #expect(ungrouped.title == "Doing")
        #expect(library.views == [ungrouped])
        #expect(source.refreshes.withLock { $0 } == 0)
    }

    @Test func aChangeOnAStaleVersionIsToldAndOverwritesNothing() async throws {
        let (library, source) = try await Self.loaded()
        let view = try #require(await library.createView(Self.settings))
        _ = try await library.changeView(view.id, LibraryViewChange(title: "Elsewhere"), baseVersion: view.version).get()
        let refreshes = source.refreshes.withLock { $0 }

        let stale = await library.changeView(view.id, LibraryViewChange(sort: []), baseVersion: view.version)
        #expect(throws: ViewWriteFailure.self) { try stale.get() }
        #expect(source.savedViews.withLock { $0[view.id]?.sort } == Self.settings.sort)
        #expect(library.views.first?.title == "Elsewhere")
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Update View"))
        // The library asks the server again for the view as it is.
        #expect(source.refreshes.withLock { $0 } == refreshes + 1)
    }

    @Test func offlineNothingIsSavedAndTheRetryReusesItsKey() async throws {
        let (library, source) = try await Self.loaded()
        source.viewFailure.withLock { $0 = ViewWriteFailure(kind: .offline, message: "No server.") }
        #expect(await library.createView(Self.settings) == nil)
        #expect(library.views.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Save View"))
        #expect(library.notices.waiting.last?.message == "No server.")

        source.viewFailure.withLock { $0 = nil }
        let view = try #require(await library.createView(Self.settings))
        #expect(library.views.map(\.id) == [view.id])
        let keys = source.viewKeys.withLock { $0 }
        #expect(keys.count == 2 && keys[0] == keys[1])

        // Once a write is answered, the next is a write of its own.
        _ = await library.createView(Self.settings)
        #expect(Set(source.viewKeys.withLock { $0 }).count == 2)
    }

    @Test func viewWritesWaitForTheServer() async throws {
        let (library, source) = try await Self.loaded()
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { !library.canEditViews })
        source.state.set(.connecting)
        #expect(await eventually { library.connection == .connecting })
        #expect(!library.canEditViews)
    }

    @Test func aDeletedViewGoesAtOnce() async throws {
        let (library, source) = try await Self.loaded()
        let view = try #require(await library.createView(Self.settings))
        #expect(await library.deleteView(view.id))
        #expect(library.views.isEmpty)
        #expect(source.savedViews.withLock { $0.isEmpty })

        // A view already gone is told, not deleted twice.
        #expect(await !library.deleteView(view.id))
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Delete View"))
    }
}

extension LiveMarfaTests {
    /// Views written to the test instance, in the Live test plan. Each view the test makes is deleted when it ends.
    @MainActor
    @Suite(.serialized)
    struct MarfaViewWriteLiveTests {
        @Test(.timeLimit(.minutes(2)))
        func aViewIsSavedChangedRefusedOnAStaleVersionAndDeleted() async throws {
            let root = URL.temporaryDirectory.appending(path: "MarfaViewWrites-\(UUID().uuidString)", directoryHint: .isDirectory)
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]), location: MarfaStoreLocation(root: root))
            let library = MarfaLibrary(source: source, notices: Notices())
            defer { try? FileManager.default.removeItem(at: root) }
            source.refresh()
            try #require(await eventually { library.isLoaded && library.canEditViews })

            let settings = LibraryViewSettings(
                title: "MAPPTEST view \(UUID().uuidString.prefix(8))",
                query: LibraryViewQuery(
                    types: [TypeID("core.task")], states: [.active],
                    filter: #"properties.status eq "todo" OR backref[parent-of] not_exists"#),
                sort: [LibraryViewSort(field: "properties.priority", ascending: false), LibraryViewSort(field: "updated_at", ascending: false)],
                group: LibraryViewGroup(field: "created_at", bucket: .month))
            let view = try #require(await library.createView(settings), "\(library.notices.waiting.map(\.message))")
            do {
                #expect(view.settings == settings)
                // The copy's own word on the write agrees with the server's answer.
                #expect(await eventually { library.views.first { $0.id == view.id }?.settings == settings })

                let ungrouped = try await library.changeView(view.id, LibraryViewChange(group: .clear), baseVersion: view.version).get()
                #expect(ungrouped.group == nil)
                #expect(ungrouped.sort == settings.sort)

                // The grouping changed since the version this change was based on.
                let stale = await library.changeView(
                    view.id, LibraryViewChange(group: .set(LibraryViewGroup(field: "type"))), baseVersion: view.version)
                guard case .failure(let failure) = stale else {
                    Issue.record("a stale change was taken: \(stale)")
                    _ = await library.deleteView(view.id)
                    return
                }
                #expect(failure.kind == .conflict)
                #expect(await eventually { library.views.first { $0.id == view.id }?.group == nil })

                #expect(await library.deleteView(view.id))
                #expect(await eventually { !library.views.contains { $0.id == view.id } })
            } catch {
                _ = await library.deleteView(view.id)
                throw error
            }
            await source.close()
        }
    }
}
