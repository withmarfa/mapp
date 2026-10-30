import Foundation
import Marfa
import Synchronization
import struct MarfaCore.Draft
import struct MarfaCore.Edit
import struct MarfaCore.Item
import Testing
@testable import MAPP

/// After a whole read the engine keeps the copy's change cursor, and where anything may have changed it asks the copy
/// what did and rereads only that (`MarfaEngine.readChanged`). These tests run a real copy, so what the copy names is
/// the package's own answer, and check that the library ends up as a whole read would leave it.
@Suite(.serialized, .hangLimit) struct MarfaChangedReadsTests {
    /// The copy's reads, counting each whole read and able to change what the copy answers: a copy still filling, an
    /// answer rewritten, a read that fails, rows left out, and a gate that holds the engine inside a reread.
    private nonisolated final class Watched: MarfaReading {
        let read: MarfaRead
        let wholeReads = Mutex(0)
        /// Each answer the copy gave to a read of what changed, as the engine took it.
        let answers = Mutex<[CopyChanges]>([])
        let rewrite = Mutex<(@Sendable (CopyChanges) -> CopyChanges)?>(nil)
        /// Asked in place of the engine's own cursor, once.
        let foreign = Mutex<ChangeCursor?>(nil)
        let filling = Mutex(false)
        /// Rows a reread does not find, as when they left the copy after it named them.
        let gone = Mutex<Set<String>>([])
        /// How many rereads fail before one succeeds.
        let failures = Mutex(0)
        /// Each row whose links were asked for.
        let linksAsked = Mutex<[String]>([])
        private let gate = Mutex((closed: false, waiting: [CheckedContinuation<Void, Never>]()))

        init(copy: WorkingCopy) { read = MarfaRead(copy: copy) }

        var whole: Int { wholeReads.withLock { $0 } }
        var named: Int { answers.withLock { $0.filter { if case .named = $0 { true } else { false } }.count } }
        var everything: Int { answers.withLock { $0.filter { if case .everything = $0 { true } else { false } }.count } }

        func hold() { gate.withLock { $0.closed = true } }

        func letGo() {
            let waiting = gate.withLock { gate in
                gate.closed = false
                defer { gate.waiting = [] }
                return gate.waiting
            }
            for reader in waiting { reader.resume() }
        }

        var holding: Int { gate.withLock { $0.waiting.count } }

        private func refuseWhileFilling() throws {
            if filling.withLock({ $0 }) { throw MarfaError.hydrationIncomplete(message: "The copy is not whole") }
        }

        func status() async throws -> Status {
            Status(hydration: filling.withLock { $0 } ? .inProgress : .complete)
        }

        func items() async throws -> Rows<Marfa.Item> {
            wholeReads.withLock { $0 += 1 }
            let rows = try await read.items()
            return Rows(rows.rows, completeness: filling.withLock { $0 } ? .partial : .complete)
        }

        func items(_ ids: [String]) async throws -> Rows<Marfa.Item> {
            await withCheckedContinuation { reader in
                let waits = gate.withLock { gate in
                    guard gate.closed else { return false }
                    gate.waiting.append(reader)
                    return true
                }
                if !waits { reader.resume() }
            }
            let fails = failures.withLock { failures in
                defer { failures = max(0, failures - 1) }
                return failures > 0
            }
            if fails { throw MarfaError.invalid(message: "The read failed") }
            let gone = gone.withLock { $0 }
            let rows = try await read.items(ids).rows.filter { !gone.contains($0.id) }
            return Rows(rows, completeness: filling.withLock { $0 } ? .partial : .complete)
        }

        func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
            try refuseWhileFilling()
            return try await read.edges(ofTypes: types)
        }

        func edges(touching id: String) async throws -> [Marfa.Edge] {
            try refuseWhileFilling()
            return try await read.edges(touching: id)
        }

        func edges(_ ids: [String]) async throws -> [Marfa.Edge] {
            try refuseWhileFilling()
            let gone = gone.withLock { $0 }
            return try await read.edges(ids).filter { !gone.contains($0.id) }
        }

        func views() async throws -> Rows<LibraryView> { try await read.views() }
        func items(inView id: String) async throws -> [Marfa.Item] { try await read.items(inView: id) }
        func links(in ids: [String]) async throws -> [String: BodyLinks] {
            linksAsked.withLock { $0 += ids }
            return try await read.links(in: ids)
        }

        func links(in id: String) async throws -> BodyLinks {
            linksAsked.withLock { $0.append(id) }
            return try await read.links(in: id)
        }

        func changes(since cursor: ChangeCursor?, most: Int) async throws -> CopyChanges {
            try refuseWhileFilling()
            let asked = cursor == nil ? nil : foreign.withLock { foreign in
                defer { foreign = nil }
                return foreign
            } ?? cursor
            var answer = try await read.changes(since: asked, most: most)
            if let rewrite = rewrite.withLock({ $0 }) { answer = rewrite(answer) }
            // The cursor a whole read takes is no answer the engine rereads by.
            if cursor != nil { answers.withLock { $0.append(answer) } }
            return answer
        }
    }

    private struct Scene {
        let store: TemporaryMarfaCopy
        let copy: WorkingCopy
        let reads: Watched
        let source: MarfaSource
        let log: ChangeLog

        /// Tells the engine the copy caught up with the server, which may have changed anything.
        func caughtUp() {
            source.hear(Change(origin: .refreshed(.caughtUp), itemId: nil, edgeId: nil))
        }

        func note(_ title: String, body: String = "Text") async throws -> String {
            let made = try await copy.items.create(Draft(type: "example.note", properties: ["title": .string(title), "body": .string(body)]))
            return try #require(made.itemId)
        }

        func rename(_ id: String, to title: String) async throws {
            let version = try #require(await copy.items.get(id)?.version)
            _ = try await copy.items.update(id, Edit(properties: JSONObject([("title", .string(title))]), baseVersion: version))
        }

        func shown(_ title: String) -> MAPP.Item? { log.current.item(titled: title) }

        func wait(_ what: String, _ condition: @escaping (ChangeLog.State) -> Bool) async throws {
            try #require(await log.wait(until: condition) != nil, "waiting for \(what)")
        }
    }

    private func makeScene() async throws -> Scene {
        let store = try TemporaryMarfaCopy()
        let copy = try await store.open()
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        _ = try await copy.items.create(Draft(type: "example.note", properties: ["title": "First", "body": "Text"]))
        let reads = Watched(copy: copy)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "http://127.0.0.1:9"), reading: reads)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        let scene = Scene(store: store, copy: copy, reads: reads, source: source, log: log)
        try await scene.wait("the first paint") { $0.item(titled: "First") != nil }
        try #require(await source.engine.cursor != nil, "a whole read takes a cursor")
        return scene
    }

    private func finish(_ scene: Scene) async {
        await scene.source.close()
        scene.store.remove()
    }

    @Test func aCatchUpRereadsOnlyWhatChanged() async throws {
        let scene = try await makeScene()
        let whole = scene.reads.whole
        let parent = try await scene.note("Parent")
        let child = try await scene.note("Child")
        _ = try await scene.copy.edges.create(from: parent, to: child, type: MarfaMapping.parentEdge)
        let first = try #require(scene.shown("First")).id.rawValue
        try await scene.rename(first, to: "Renamed")

        scene.caughtUp()
        // A `parent-of` is held by the child.
        try await scene.wait("what changed") { state in
            state.item(titled: "Renamed") != nil && state.item(titled: "First") == nil
                && state.item(titled: "Child")?.edgesOut.contains { $0.target == .item(ItemID(parent)) } == true
        }
        #expect(scene.reads.whole == whole, "no whole read")
        #expect(scene.reads.named == 1)

        // The next catch-up starts where this one ended, so it names nothing already read.
        scene.caughtUp()
        await scene.source.engineTook()
        guard case .named(let rows, _)? = scene.reads.answers.withLock({ $0.last }) else {
            Issue.record("the copy named no changes")
            return await finish(scene)
        }
        #expect(rows.isEmpty, "\(rows)")
        #expect(scene.reads.whole == whole)
        await finish(scene)
    }

    @Test func aCopyThatCannotNameWhatChangedIsReadWhole() async throws {
        let scene = try await makeScene()
        let whole = scene.reads.whole
        scene.reads.rewrite.withLock { $0 = { .everything(next: $0.next) } }
        _ = try await scene.note("Second")
        scene.caughtUp()
        try await scene.wait("the new note") { $0.item(titled: "Second") != nil }
        #expect(scene.reads.whole == whole + 1)
        await finish(scene)
    }

    @Test func moreChangesThanTheLimitAreReadWhole() async throws {
        let scene = try await makeScene()
        let whole = scene.reads.whole
        let limit = await scene.source.engine.changeLimit
        for index in 0...limit { _ = try await scene.note("Note \(index)") }
        scene.caughtUp()
        try await scene.wait("every new note") { $0.item(titled: "Note \(limit)") != nil && $0.item(titled: "Note 0") != nil }
        #expect(scene.reads.everything == 1)
        #expect(scene.reads.whole == whole + 1)
        await finish(scene)
    }

    @Test func aCursorFromAnotherStoreIsReadWhole() async throws {
        let scene = try await makeScene()
        let other = try TemporaryMarfaCopy()
        let elsewhere = try await other.open()
        let foreign = try await elsewhere.changes(since: nil).next
        scene.reads.foreign.withLock { $0 = foreign }
        let whole = scene.reads.whole
        _ = try await scene.note("Second")
        scene.caughtUp()
        try await scene.wait("the new note") { $0.item(titled: "Second") != nil }
        #expect(scene.reads.everything == 1)
        #expect(scene.reads.whole == whole + 1)

        // The whole read took this store's cursor again.
        _ = try await scene.note("Third")
        scene.caughtUp()
        try await scene.wait("the next note") { $0.item(titled: "Third") != nil }
        #expect(scene.reads.whole == whole + 1)
        other.remove()
        await finish(scene)
    }

    @Test func aRereadThatFailsReadsTheCopyWholeAndShowsWhatChanged() async throws {
        let scene = try await makeScene()
        let whole = scene.reads.whole
        _ = try await scene.note("Second")
        scene.reads.failures.withLock { $0 = 1 }
        scene.caughtUp()
        try await scene.wait("the new note") { $0.item(titled: "Second") != nil }
        #expect(scene.reads.whole == whole + 1)
        #expect(scene.log.current.changes.allSatisfy { if case .unavailable = $0 { false } else { true } }, "nothing to tell")
        await finish(scene)
    }

    @Test func aRowNamedButBinnedBeforeTheRereadIsShownInTheBin() async throws {
        let scene = try await makeScene()
        let first = try #require(scene.shown("First")).id
        try await scene.rename(first.rawValue, to: "Renamed")
        // Binned after it was renamed: the reread finds it in the bin, where the library shows it.
        _ = try await scene.copy.items.delete(first.rawValue)
        scene.caughtUp()
        try await scene.wait("the note in the bin") { $0.item(titled: "Renamed")?.state == .trashed }
        await finish(scene)
    }

    @Test func aRowNamedButGoneBeforeTheRereadLeavesTheLibrary() async throws {
        let scene = try await makeScene()
        let first = try #require(scene.shown("First")).id
        try await scene.rename(first.rawValue, to: "Renamed")
        scene.reads.gone.withLock { $0 = [first.rawValue] }
        scene.caughtUp()
        try await scene.wait("the note gone") { $0.snapshot?.items.contains { $0.id == first } == false }
        await finish(scene)
    }

    @Test func anEdgeRemovedWithItsItemLeavesBoth() async throws {
        let scene = try await makeScene()
        let parent = try await scene.note("Parent")
        let child = try await scene.note("Child")
        _ = try await scene.copy.edges.create(from: parent, to: child, type: MarfaMapping.parentEdge)
        scene.caughtUp()
        // A `parent-of` is held by the child.
        try await scene.wait("the link") { $0.item(titled: "Child")?.edgesOut.isEmpty == false }
        let edge = try #require(await scene.copy.edges.from(parent).first).id

        // As a purge the server made: the copy names the child and its edge as removed.
        scene.reads.gone.withLock { $0 = [child, edge] }
        scene.reads.rewrite.withLock { rewrite in
            rewrite = { answer in .named(ChangedRows(removedItems: [child], removedEdges: [edge]), next: answer.next) }
        }
        scene.caughtUp()
        try await scene.wait("the child gone") { $0.item(titled: "Child") == nil }
        #expect(await scene.source.engine.edges.edges(touching: parent).isEmpty, "the edge left with its item")
        await finish(scene)
    }

    @Test func aFillingCopyKeepsItsCursorAndIsReadByWhatChangedOnceWhole() async throws {
        let scene = try await makeScene()
        let cursor = await scene.source.engine.cursor
        scene.reads.filling.withLock { $0 = true }
        _ = try await scene.note("Second")
        scene.caughtUp()
        await scene.source.engineTook()
        #expect(await scene.source.engine.cursor == cursor, "a read of a copy still filling is not whole")

        let whole = scene.reads.whole
        scene.reads.filling.withLock { $0 = false }
        _ = try await scene.note("Third")
        scene.source.hear(Change(origin: .refreshed(.hydrated), itemId: nil, edgeId: nil))
        try await scene.wait("both notes") { $0.item(titled: "Second") != nil && $0.item(titled: "Third") != nil }
        #expect(scene.reads.whole == whole, "named from the cursor kept through the fill")
        #expect(await scene.source.engine.cursor != cursor)
        await finish(scene)
    }

    @Test func changesHeardDuringARereadAreReadOnceAfterIt() async throws {
        let scene = try await makeScene()
        let whole = scene.reads.whole
        _ = try await scene.note("Second")
        scene.reads.hold()
        scene.caughtUp()
        try #require(await eventually { scene.reads.holding > 0 }, "the engine never reached the held read")
        _ = try await scene.note("Third")
        scene.caughtUp()
        _ = try await scene.note("Fourth")
        scene.caughtUp()
        scene.reads.letGo()
        try await scene.wait("every note") {
            $0.item(titled: "Second") != nil && $0.item(titled: "Third") != nil && $0.item(titled: "Fourth") != nil
        }
        await scene.source.engineTook()
        #expect(scene.reads.named == 2, "one read for the first change and one for the two heard while it ran")
        #expect(scene.reads.whole == whole)
        await finish(scene)
    }

    @Test func aLinkThatStartsToNameARetitledItemReadsAgain() async throws {
        let scene = try await makeScene()
        let target = try await scene.note("Other")
        let host = try await scene.note("Host", body: "See [[Bee]]")
        _ = try await scene.copy.edges.create(from: host, to: target, type: MarfaMapping.bodyLinkEdge)
        scene.caughtUp()
        try await scene.wait("the host") { $0.item(titled: "Host")?.boundLinks.isEmpty == false }
        #expect(scene.shown("Host")?.boundLinks.first?.resolution != .resolved(ItemID(target)))

        // Only the target is named: its new title is what the host's link names.
        try await scene.rename(target, to: "Bee")
        scene.caughtUp()
        try await scene.wait("the link bound") {
            $0.item(titled: "Host")?.boundLinks.first?.resolution == .resolved(ItemID(target))
        }
        await finish(scene)
    }

    /// A link that names no item is read from its host's own edges or an ID the copy holds, so a retitled item
    /// that is neither leaves it as it was, and a save of one item's text reads no other item's links.
    @Test func aRetitledItemDoesNotReadAnUnrelatedLinkAgain() async throws {
        let scene = try await makeScene()
        let host = try await scene.note("Host", body: "See [[Nowhere]]")
        scene.caughtUp()
        try await scene.wait("the host") { $0.item(titled: "Host")?.boundLinks.isEmpty == false }
        scene.reads.linksAsked.withLock { $0 = [] }

        let first = try #require(scene.shown("First")).id.rawValue
        try await scene.rename(first, to: "Nowhere")
        scene.caughtUp()
        try await scene.wait("the new title") { $0.item(titled: "Nowhere") != nil }
        #expect(!scene.reads.linksAsked.withLock { $0 }.contains(host))
        await finish(scene)
    }
}
