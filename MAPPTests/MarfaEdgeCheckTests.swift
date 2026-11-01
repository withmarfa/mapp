import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

/// What the core says of an edge before it is written, asked through the library with no server and nothing queued.
@MainActor
@Suite(.hangLimit)
struct MarfaEdgeCheckTests {
    private struct Scene {
        let fake: FakeCopy
        let source: MarfaSource
        let library: MarfaLibrary
        let ids: [String: ItemID]

        func id(_ name: String) -> ItemID { ids[name]! }
    }

    private static func scene(_ names: [(name: String, type: String)]) async throws -> Scene {
        let fake = WorkingCopy.fake(itemTypes: SampleLibrary.itemTypes, edgeTypes: SampleLibrary.edgeTypes)
        var ids: [String: ItemID] = [:]
        for (name, type) in names {
            let queued = try await fake.copy.items.create(Draft(type: type, properties: ["title": .string(name)]))
            ids[name] = ItemID(try #require(queued.itemId))
        }
        let source = MarfaSource(copy: fake.copy, connection: SampleLibrary.connection)
        source.events.yield(.paint)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded && ids.values.allSatisfy { library.item($0) != nil } })
        return Scene(fake: fake, source: source, library: library, ids: ids)
    }

    /// `parent` filed above `child`: a parent edge is written at the child, from the parent to the child.
    private static func file(_ child: String, under parent: String, in scene: Scene) async throws {
        _ = try await scene.fake.copy.edges.create(
            from: scene.id(parent).rawValue, to: scene.id(child).rawValue, type: MarfaMapping.parentEdge)
        try #require(await eventually { scene.library.relationships(for: scene.id(child)).contains { $0.field == "child-of" && !$0.targets.isEmpty } })
    }

    @Test func aLinkThatWouldCloseACycleOnAnAcyclicTypeIsRefusedWithTheCoresWords() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note"), ("c", "core.note")])
        try await Self.file("b", under: "a", in: scene)
        try await Self.file("c", under: "b", in: scene)
        let queued = try await scene.fake.copy.queue.all().count
        // `a` filed under its own grandchild, from either end.
        let fromChild = await scene.library.relationshipVerdict(for: scene.id("a"), field: "child-of", to: scene.id("c")).refusal
        let fromParent = await scene.library.relationshipVerdict(for: scene.id("c"), field: "inverse:parent-of", to: scene.id("a")).refusal
        #expect(fromChild?.localizedStandardContains("cycle") == true, "\(String(describing: fromChild))")
        #expect(fromParent == fromChild)
        // An unrelated item, and the parent already above, are taken.
        let sibling = await scene.library.relationshipVerdict(for: scene.id("c"), field: "child-of", to: scene.id("a"))
        #expect(sibling == .taken)
        #expect(try await scene.fake.copy.queue.all().count == queued, "asking queued a write")
        await scene.source.close()
    }

    @Test func anItemCantBeLinkedToItself() async throws {
        let scene = try await Self.scene([("a", "core.note")])
        let refusal = await scene.library.relationshipVerdict(for: scene.id("a"), field: "child-of", to: scene.id("a")).refusal
        #expect(refusal?.isEmpty == false)
        await scene.source.close()
    }

    @Test func aCollectionCantBeInAnotherBecauseTheTypeIsFlat() async throws {
        let scene = try await Self.scene([("holiday", "core.collection"), ("archive", "core.collection"), ("note", "core.note")])
        let nested = await scene.library.relationshipVerdict(for: scene.id("archive"), field: "in-collection", to: scene.id("holiday")).refusal
        #expect(nested?.isEmpty == false)
        #expect(await scene.library.relationshipVerdict(for: scene.id("note"), field: "in-collection", to: scene.id("holiday")) == .taken)
        // The catalogue says so too, so a collection is not offered the field.
        #expect(scene.library.catalogue.edgeTypes[MarfaMapping.collectionEdge]?.flat == true)
        #expect(!scene.library.canJoinCollection(try #require(scene.library.item(scene.id("archive")))))
        await scene.source.close()
    }

    @Test func aSecondParentIsNotTheChecksToRefuseSoTheLibraryMovesTheEdge() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note"), ("child", "core.note")])
        try await Self.file("child", under: "a", in: scene)
        // The check judges types, cycles, the bin and flat nesting; how many an end holds is the move's to keep.
        #expect(await scene.library.relationshipVerdict(for: scene.id("child"), field: "child-of", to: scene.id("b")) == .taken)
        #expect(scene.library.setItemRelationship(scene.id("child"), field: "child-of", targetIDs: [scene.id("b")], undoManager: nil))
        try #require(await eventually {
            scene.library.relationships(for: scene.id("child")).first { $0.field == "child-of" }?.targets.map(\.itemID) == [scene.id("b")]
        })
        await scene.source.close()
    }

    @Test func anItemInTheBinIsRefused() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note")])
        _ = try await scene.fake.copy.items.delete(scene.id("b").rawValue)
        try #require(await eventually { scene.library.item(scene.id("b"))?.state == .trashed })
        let refusal = await scene.library.relationshipVerdict(for: scene.id("a"), field: "child-of", to: scene.id("b")).refusal
        #expect(refusal?.isEmpty == false)
        await scene.source.close()
    }

    @Test func aCheckThatCouldNotBeMadeIsNotARefusal() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note")])
        await scene.source.close()
        // The copy is closed, so the core cannot be asked: neither a refusal to show nor a go-ahead.
        let verdict = await scene.library.relationshipVerdict(for: scene.id("a"), field: "child-of", to: scene.id("b"))
        #expect(verdict == .unknown, "\(verdict)")
    }

    @Test func aParentIsCheckedBeforeTheItemUnderItExists() async throws {
        let scene = try await Self.scene([("parent", "core.note"), ("binned", "core.note"), ("holiday", "core.collection")])
        _ = try await scene.fake.copy.items.delete(scene.id("binned").rawValue)
        try #require(await eventually { scene.library.item(scene.id("binned"))?.state == .trashed })
        let queued = try await scene.fake.copy.queue.all().count
        #expect(await scene.library.newChildVerdict(under: scene.id("parent")) == .taken)
        #expect(await scene.library.newChildVerdict(under: scene.id("binned")).refusal?.isEmpty == false, "a parent in the bin")
        #expect(try await scene.fake.copy.queue.all().count == queued, "asking queued a write")
        await scene.source.close()
    }

    @Test func aChangeOfSeveralLinksIsNotPartlyWrittenWhenTheCoreRefusesOne() async throws {
        let scene = try await Self.scene([("holiday", "core.collection"), ("archive", "core.collection"), ("note", "core.note")])
        let queued = try await scene.fake.copy.queue.all().count
        // The note may join; the other collection may not, since the type is flat. Neither is written.
        #expect(scene.library.setItemRelationship(
            scene.id("holiday"), field: "inverse:in-collection", targetIDs: [scene.id("note"), scene.id("archive")], undoManager: nil))
        try #require(await eventually { !scene.library.notices.waiting.isEmpty })
        try await Task.sleep(for: .milliseconds(200))
        #expect(try await scene.fake.copy.queue.all().count == queued)
        #expect(scene.library.relationships(for: scene.id("holiday")).allSatisfy { $0.targets.isEmpty })
        // The note alone is taken.
        #expect(scene.library.setItemRelationship(scene.id("holiday"), field: "inverse:in-collection", targetIDs: [scene.id("note")], undoManager: nil))
        try #require(await eventuallyAsking { try await scene.fake.copy.queue.all().count == queued + 1 })
        await scene.source.close()
    }
}
