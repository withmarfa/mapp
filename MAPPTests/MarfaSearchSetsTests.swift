import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

/// Search is narrowed by the copy through the sets it is given, and MAPP keeps every hit it returns
/// (`MarfaSource.search`), so the limit counts items shown and the bin never takes a place in it.
@Suite(.serialized, .hangLimit)
struct MarfaSearchSetsTests {
    private static let stamp = "2026-10-06T00:00:00Z"

    private static func row(_ id: String, type: String = "core.note", state: Marfa.ItemState = .active) -> Marfa.Item {
        Marfa.Item(
            id: id, type: type, properties: ["title": .string("Zebra \(id)"), "body": .string("zebra crossing")], state: state,
            tier: .library, version: 1, schemaVersion: 1, source: "test", sourceId: nil, occurredAt: stamp,
            createdAt: stamp, updatedAt: stamp, tags: [])
    }

    private func search(
        _ rows: [Marfa.Item], in query: ItemQuery = MarfaLibrary.searchScope
    ) async throws -> SourceSearch {
        let source = SampleLibrary.open(SampleLibrary.connection, items: rows, edges: [])
        defer { Task { await source.close() } }
        return try await source.search("zebra", in: .items(query))
    }

    @Test func aGlobalSearchReturnsEveryLiveHitAndNoneFromTheBin() async throws {
        // More binned matches than the limit: dropped after the read, they would have used up the places.
        let binned = (0..<(SearchResults.limit + 20)).map { Self.row("bin-\($0)", state: .trashed) }
        let live = [Self.row("live-1"), Self.row("live-2"), Self.row("archived", state: .archived)]
        let found = try await search(binned + live)
        #expect(Set(found.hits.map(\.rawValue)) == ["live-1", "live-2", "archived"])
        #expect(!found.isCapped)
    }

    @Test func aSearchByTypeGivesTheCopyTheTypeAndKeepsEveryHit() async throws {
        let rows = [Self.row("note-1"), Self.row("note-2"), Self.row("task-1", type: "core.task")]
        let notes = try await search(rows, in: ItemQuery(types: [TypeID("core.note")], states: [.active, .archived]))
        #expect(Set(notes.hits.map(\.rawValue)) == ["note-1", "note-2"])
        let tasks = try await search(rows, in: ItemQuery(types: [TypeID("core.task")], states: [.active, .archived]))
        #expect(tasks.hits.map(\.rawValue) == ["task-1"])
    }

    @Test func anExcerptIsTheCoresRunsKeptWithTheVersionTheyWereCutFrom() async throws {
        let found = try await search([Self.row("a")])
        let excerpt = try #require(found.excerpts[ItemID("a")])
        #expect(excerpt.runs.contains { $0.isMatch && $0.text.lowercased() == "zebra" })
        #expect(excerpt.version == ItemVersion(1))
    }

    // MARK: Include Subtypes

    /// A type's place holds its own items alone until Include Subtypes is on, and the search follows the list. The copy
    /// is a real one, since the fake working copy answers no `filter` in a search.
    @Test func aTypesSearchFollowsIncludeSubtypes() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let source = MarfaSource(copy: copy, connection: SampleLibrary.connection)
        let library = MarfaLibrary(source: source, notices: Notices())
        defer { Task { await source.close() } }
        source.events.yield(.paint)
        try #require(await eventually { library.isLoaded })
        let catalogue = library.catalogue
        let pair = try #require(
            catalogue.itemTypes.values.sorted { $0.id.rawValue < $1.id.rawValue }.first { child in
                guard let parent = child.parent.flatMap({ catalogue.itemTypes[$0] }) else { return false }
                return [child, parent].allSatisfy { $0.titleKey != nil && $0.bodyKey != nil && catalogue.isCreatable($0.id) }
            }, "the built-in catalogue has no type with a parent that takes a title and text")
        let parent = try #require(pair.parent)
        for (id, type) in [("own", parent), ("sub", pair.id)] {
            let info = try #require(catalogue.itemTypes[type])
            _ = try await copy.items.create(Draft(
                type: type.rawValue,
                properties: [try #require(info.titleKey): .string("Zebra \(id)"), try #require(info.bodyKey): .string("zebra crossing")], id: ItemID.mint().rawValue))
        }
        try #require(await eventually { library.items(in: .itemType(pair.id.rawValue)).count == 1 })
        func found(_ scope: SearchScope) async -> [String] {
            _ = await eventually { !library.search("zebra", in: scope).isPending }
            return library.search("zebra", in: scope).items.map(\.title).sorted()
        }
        #expect(await found(.place(.itemType(parent.rawValue))) == ["Zebra own"])
        #expect(await found(.typeWithSubtypes(parent)) == ["Zebra own", "Zebra sub"])
    }
}
