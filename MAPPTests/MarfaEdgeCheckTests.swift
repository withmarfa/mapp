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

    /// `source` linked to `target` by an edge of `type`, once the library shows it.
    private static func link(_ type: String, from source: String, to target: String, in scene: Scene) async throws {
        _ = try await scene.fake.copy.edges.create(from: scene.id(source).rawValue, to: scene.id(target).rawValue, type: type)
        try #require(await eventually {
            scene.library.relationships(for: scene.id(target)).contains { $0.targets.contains { $0.itemID == scene.id(source) } }
        })
    }

    private static func holds(_ name: String, _ field: String, in scene: Scene) -> [ItemID?] {
        scene.library.relationships(for: scene.id(name)).first { $0.field == field }?.targets.map(\.itemID) ?? []
    }

    private func fullMessage(_ name: String) -> String {
        String(localized: "“\(name)” can hold only one link of this kind, and already holds it.")
    }

    @Test func aSecondParentIsRefusedByTheCoreAndAReplacementIsAMoveItTakes() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note"), ("child", "core.note")])
        try await Self.file("child", under: "a", in: scene)
        let queued = try await scene.fake.copy.queue.all().count
        // A picker replaces the one parent, so the row is asked as a move, which the core takes.
        #expect(await scene.library.relationshipVerdict(for: scene.id("child"), field: "child-of", to: scene.id("b")) == .taken)
        // A second parent beside the first is the core's to refuse, in words naming the item that holds one already.
        #expect(await scene.library.changeItemRelationship(scene.id("child"), field: "child-of", adding: [scene.id("b")], removing: [], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.title == String(localized: "Can’t Change This Relationship"))
        #expect(scene.library.notices.waiting.last?.message == fullMessage("child"))
        #expect(try await scene.fake.copy.queue.all().count == queued, "a refused change queued a write")
        #expect(Self.holds("child", "child-of", in: scene) == [scene.id("a")])
        // Replacing it is one move.
        scene.library.notices.answerAll()
        #expect(await scene.library.changeItemRelationship(scene.id("child"), field: "child-of", adding: [scene.id("b")], removing: [scene.id("a")], undoManager: nil))
        try #require(await eventually { Self.holds("child", "child-of", in: scene) == [scene.id("b")] })
        #expect(scene.library.notices.waiting.isEmpty)
        await scene.source.close()
    }

    @Test func twoParentsChosenAtOnceAreRefusedAndNeitherIsWritten() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note"), ("c", "core.note"), ("child", "core.note")])
        try await Self.file("child", under: "a", in: scene)
        let queued = try await scene.fake.copy.queue.all().count
        #expect(await scene.library.changeItemRelationship(
            scene.id("child"), field: "child-of", adding: [scene.id("b"), scene.id("c")], removing: [], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.message == fullMessage("child"))
        #expect(try await scene.fake.copy.queue.all().count == queued)
        // Chosen under a parent that has the child already, from either end, is not a new link.
        #expect(await scene.library.changeItemRelationship(scene.id("a"), field: "inverse:parent-of", adding: [scene.id("child")], removing: [], undoManager: nil))
        #expect(try await scene.fake.copy.queue.all().count == queued)
        await scene.source.close()
    }

    @Test func aChildChosenUnderAParentFromTheParentsSideIsAMoveTheCoreChecks() async throws {
        let scene = try await Self.scene([("a", "core.note"), ("b", "core.note"), ("child", "core.note")])
        try await Self.file("child", under: "a", in: scene)
        #expect(await scene.library.changeItemRelationship(scene.id("b"), field: "inverse:parent-of", adding: [scene.id("child")], removing: [], undoManager: nil))
        try #require(await eventually { Self.holds("child", "child-of", in: scene) == [scene.id("b")] })
        // Moving a source end expires the copy and the app fills it again, which the fake can't do, so a notice
        // about reading the library may wait here. None of them is a refusal of the move.
        #expect(!scene.library.notices.waiting.contains { $0.title == String(localized: "Can’t Change This Relationship") })
        await scene.source.close()
    }

    @Test func aLinkBothOfWhoseEndsHoldOneIsMovedOnlyWhereTheOtherEndHasRoom() async throws {
        let scene = try await Self.scene([("x", "core.note"), ("y", "core.note"), ("z", "core.note"), ("w", "core.note"), ("v", "core.note")])
        // `x` supersedes `y`, and `z` supersedes `w`: each of the four holds its one link.
        try await Self.link("supersedes", from: "x", to: "y", in: scene)
        try await Self.link("supersedes", from: "z", to: "w", in: scene)
        let queued = try await scene.fake.copy.queue.all().count

        // A second link beside the one `x` holds is refused naming `x`.
        #expect(await scene.library.changeItemRelationship(scene.id("x"), field: "supersedes", adding: [scene.id("v")], removing: [], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.message == fullMessage("x"))
        // Replacing `y` by `w`, whose superseder is `z`'s link, is never taken from `z`.
        scene.library.notices.answerAll()
        #expect(await scene.library.changeItemRelationship(scene.id("x"), field: "supersedes", adding: [scene.id("w")], removing: [scene.id("y")], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.message
            == String(localized: "“\("z")” already holds this link to “\("w")”. Remove it there first."))
        // `y`'s superseder `x` replaced by `z`, which already supersedes `w`, would leave `z` with two.
        scene.library.notices.answerAll()
        #expect(await scene.library.changeItemRelationship(scene.id("y"), field: "inverse:supersedes", adding: [scene.id("z")], removing: [scene.id("x")], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.message == fullMessage("z"))
        // Taken from the other end it is the same: `z`'s link would move onto `y`, which has one.
        scene.library.notices.answerAll()
        #expect(await scene.library.changeItemRelationship(scene.id("y"), field: "inverse:supersedes", adding: [scene.id("z")], removing: [], undoManager: nil) == false)
        #expect(scene.library.notices.waiting.last?.message == fullMessage("y"))
        #expect(try await scene.fake.copy.queue.all().count == queued, "a refused change queued a write")

        // `y` replaced by `v`, which holds none, is one move.
        scene.library.notices.answerAll()
        #expect(await scene.library.changeItemRelationship(scene.id("x"), field: "supersedes", adding: [scene.id("v")], removing: [scene.id("y")], undoManager: nil))
        try #require(await eventually { Self.holds("x", "supersedes", in: scene) == [scene.id("v")] })
        #expect(scene.library.notices.waiting.isEmpty)
        #expect(Self.holds("y", "inverse:supersedes", in: scene).isEmpty)
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
        #expect(await scene.library.changeItemRelationship(
            scene.id("holiday"), field: "inverse:in-collection", adding: [scene.id("note"), scene.id("archive")], removing: [], undoManager: nil) == false)
        #expect(!scene.library.notices.waiting.isEmpty, "the core's refusal is told before the call answers")
        #expect(try await scene.fake.copy.queue.all().count == queued)
        #expect(scene.library.relationships(for: scene.id("holiday")).allSatisfy { $0.targets.isEmpty })
        // The note alone is taken.
        #expect(await scene.library.changeItemRelationship(scene.id("holiday"), field: "inverse:in-collection", adding: [scene.id("note")], removing: [], undoManager: nil))
        try #require(await eventuallyAsking { try await scene.fake.copy.queue.all().count == queued + 1 })
        await scene.source.close()
    }
}
