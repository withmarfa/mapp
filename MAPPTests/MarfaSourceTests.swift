import Foundation
import Marfa
import struct MarfaCore.BinPage
import struct MarfaCore.Edge
import struct MarfaCore.Edit
import struct MarfaCore.Item
import struct MarfaCore.KeptFetch
import struct MarfaCore.ListFilters
import enum MarfaCore.JsonValue
import enum MarfaCore.Tier
import SQLite3
import Synchronization
import Testing
@testable import MAPP

/// Everything a source has told one reader, and the library as that reader would hold it.
nonisolated final class ChangeLog: Sendable {
    nonisolated struct State {
        var changes: [SourceChange] = []
        var snapshot: SourceSnapshot?

        func item(titled title: String) -> MAPP.Item? {
            snapshot?.items.first { $0.title == title }
        }

        func answer(to id: WriteID) -> WriteOutcome? {
            for case .answered(id, let outcome) in changes { return outcome }
            return nil
        }
    }

    private nonisolated final class Box: Sendable {
        let state = Mutex(State())
    }

    private let box: Box
    private let reading: Task<Void, Never>

    init(_ source: MarfaSource) {
        let changes = source.changes()
        let box = Box()
        self.box = box
        reading = Task {
            for await change in changes {
                box.state.withLock { state in
                    state.changes.append(change)
                    if case .loaded(let snapshot) = change { state.snapshot = snapshot } else { state.snapshot?.apply(change) }
                }
            }
        }
    }

    deinit { reading.cancel() }

    var current: State { box.state.withLock { $0 } }

    /// Waits for `condition` to hold, and answers the state that met it, or nil when it never did.
    func wait(for limit: Duration = waitLimit, until condition: (State) -> Bool) async -> State? {
        var met: State?
        _ = await eventually(within: limit) {
            let current = self.current
            if condition(current) { met = current }
            return met != nil
        }
        return met
    }
}

nonisolated func waitForConnection(
    _ source: MarfaSource, until condition: (MarfaConnectionState) -> Bool
) async -> Bool {
    await eventually { condition(source.connectionState) }
}

private func scratch() -> URL {
    URL.temporaryDirectory.appending(path: "MarfaSourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A refresh whose first fill starts and then waits until the test releases it, as a server that never answers does.
private nonisolated final class HeldRefresh: MarfaRefreshing {
    private struct State {
        var filling = false
        var released = false
    }

    private let state = Mutex(State())
    private let held: AsyncStream<Void>
    private let letGo: AsyncStream<Void>.Continuation

    init() { (held, letGo) = AsyncStream<Void>.makeStream() }

    var filling: Bool { state.withLock { $0.filling } }
    var released: Bool { state.withLock { $0.released } }

    func release() {
        state.withLock { $0.released = true }
        letGo.finish()
    }

    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .never)
    }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        state.withLock { $0.filling = true }
        for await _ in held { }
        return HydrateReport(types: types, tier: tier, edgeTypes: edgeTypes, items: 0, edges: 0, pages: 1, pagesTotal: 1,
                             resumed: false, restarted: nil, inPlace: false, cursor: "done")
    }

    func catchUp() async throws {}
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
}

/// A server that refuses every connection, so a copy made for it never hears from it.
@Suite(.serialized, .hangLimit)
struct MarfaSourceOfflineTests {
    @Test
    func aCopyPaintsAndKeepsWritesWithoutTheServer() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)

        let source = try await MarfaSource.open(connection, keys: keys, location: location)
        let log = ChangeLog(source)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        guard case .loaded(let first) = painted.changes.first else { Issue.record("the first change is not loaded"); return }
        #expect(first.items.isEmpty)
        #expect(first.catalogue.itemTypes[TypeID("core.note")] != nil)
        #expect(source.connectionState == .connecting)

        source.refresh()
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })

        let write = WriteID()
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST offline", body: "Kept")), as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MAPPTEST offline") != nil })
        #expect(queued.item(titled: "MAPPTEST offline")?.id == id)
        #expect(queued.item(titled: "MAPPTEST offline")?.sync == .waiting(writes: 1))
        #expect(queued.answer(to: write) == nil)
        await source.flush()
        await source.close()

        let reopened = try await MarfaSource.open(connection, keys: keys, location: location)
        let again = ChangeLog(reopened)
        let repainted = try #require(await again.wait { $0.snapshot != nil })
        let kept = try #require(repainted.item(titled: "MAPPTEST offline"))
        #expect(kept.sync == .waiting(writes: 1))
        #expect(try await reopened.body(of: kept.id).text == "Kept")
        #expect(reopened.connectionState == .connecting)
        await reopened.close()
    }

    /// The copy drains what waited when the server is back, and tells the report. The write is answered, as for a
    /// drain `MarfaSync` ran.
    @Test
    func aDrainTheCopyRunsItselfAnswersTheWrite() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let write = WriteID()
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST follow drain", body: "One")), as: write)
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST follow drain") != nil })
        let queued = try #require(try await source.copy.queue.all().first)

        let answered = Marfa.QueuedWrite(
            id: queued.id, kind: queued.kind, itemId: queued.itemId, idempotencyKey: queued.idempotencyKey,
            verdict: .accepted, queuedAt: queued.queuedAt)
        let report = MarfaSync.report(answeredIn: [answered])
        source.hear(Change(origin: .queueDrained(report), itemId: nil, edgeId: nil))
        _ = try #require(await log.wait { $0.answer(to: write) == .accepted })
        await source.close()
    }

    /// A copy an earlier version made is refused with what it holds that the server has not taken, and nothing in
    /// it is removed.
    @Test
    func aCopyADifferentVersionMadeIsRefusedWithItsUnsentChangesAndKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, keys: keys, location: location)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.submit(.create(id: ItemID.mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST kept", body: "Kept")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST kept") != nil })
        await source.flush()
        await source.close()
        try Self.makeItAnEarlierVersion(location.store(for: connection))

        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, keys: keys, location: location)
        }
        #expect(failure?.kind == .otherVersion(unsent: 1))
        #expect(try Self.count(location.store(for: connection), "SELECT COUNT(*) FROM queue") == 1)
    }

    /// With nothing the server has not taken, a copy is only what the server holds, so it is made again. The
    /// files it downloaded stay, and so does the person's choice of how many to keep.
    @Test
    func aCopyADifferentVersionMadeWithNothingUnsentIsMadeAgainKeepingItsFiles() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, keys: keys, location: location)
        let file = root.appending(path: "kept.txt")
        try Data("kept bytes".utf8).write(to: file)
        let hash = try #require(try await source.copy.blobs.put(file: file).blob)
        _ = try await source.copy.blobs.setBudget(.keepAll)
        await source.close()
        let store = location.store(for: connection)
        // The upload is the only write, and it is dropped so the copy holds nothing unsent.
        try Self.execute(store, "DELETE FROM queue")
        try Self.makeItAnEarlierVersion(store)
        let before = try Self.inode(store)

        let reopened = try await MarfaSource.open(connection, keys: keys, location: location)
        #expect(try Self.inode(store) != before)
        #expect(try await reopened.copy.blobs.isHeld(hash))
        #expect(try await MarfaDownloads(copy: reopened.copy).read().budget == .keepAll)
        let log = ChangeLog(reopened)
        _ = try #require(await log.wait { $0.snapshot != nil })
        await reopened.close()
    }

    /// Without a count, the copy may hold changes only the version that made it can send.
    @Test
    func aCopyADifferentVersionMadeWhoseChangesCantBeCountedIsKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)
        try await MarfaSource.open(connection, keys: keys, location: location).close()
        let store = location.store(for: connection)
        try Self.execute(store, "ALTER TABLE queue RENAME COLUMN depends_on TO depends")
        let before = try Self.inode(store)

        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, keys: keys, location: location)
        }
        #expect(failure?.kind == .otherVersion(unsent: nil))
        #expect(try Self.inode(store) == before)
        #expect(try Self.count(store, "SELECT COUNT(*) FROM pragma_table_info('queue') WHERE name = 'depends'") == 1)
    }

    /// Another copy of the app holding the copy as its writer may still write to it, so it is never replaced. The
    /// lock is held by a different process, as another copy of the app sharing the container would hold it.
    @Test
    func aCopyADifferentVersionMadeThatAnotherProcessHoldsIsKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)
        try await MarfaSource.open(connection, keys: keys, location: location).close()
        let store = location.store(for: connection)
        try Self.makeItAnEarlierVersion(store)
        let before = try Self.inode(store)

        let holder: OtherProcessLock
        do {
            holder = try await OtherProcessLock(store)
        } catch OtherProcessLock.Failure.notStarted(let reason) {
            Issue.record("The test sandbox forbids starting /usr/bin/sqlite3, so another process can't hold the lock here: \(reason)")
            return
        }
        defer { holder.release() }
        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, keys: keys, location: location)
        }
        #expect(failure?.kind == .inUse)
        #expect(try Self.inode(store) == before)

        // Once that process lets go, the copy is replaced.
        holder.release()
        let reopened = try await MarfaSource.open(connection, keys: keys, location: location)
        #expect(try Self.inode(store) != before)
        await reopened.close()
    }

    private static func inode(_ file: URL) throws -> UInt64 {
        try #require(FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? UInt64)
    }

    /// Gives the queue the shape and write kind an earlier build used, as the package's own test does.
    static func makeItAnEarlierVersion(_ store: URL) throws {
        try execute(
            store,
            """
            PRAGMA writable_schema = ON;
            UPDATE sqlite_master SET sql = replace(sql, '''replace_metadata'',', '''replace_metadata'', ''merge_metadata'',')
              WHERE type = 'table' AND name = 'queue';
            """)
        // A new connection, since the first still holds the schema it read.
        try execute(store, "UPDATE queue SET kind = 'merge_metadata'")
    }

    static func execute(_ store: URL, _ statements: String) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(store.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, statements, nil, nil, nil) == SQLITE_OK)
    }

    private static func count(_ store: URL, _ query: String) throws -> Int64 {
        var database: OpaquePointer?
        try #require(sqlite3_open_v2(store.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }

    @Test func aMissingKeyIsDenied() async throws {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, keys: MemoryKeyStore(), location: MarfaStoreLocation(root: scratch()))
        }
    }

    private func open(_ root: URL, at address: String = "http://127.0.0.1:9") async throws -> MarfaSource {
        let connection = try MarfaConnection(address: address)
        return try await MarfaSource.open(
            connection, keys: MemoryKeyStore([connection: "unused"]), location: MarfaStoreLocation(root: root))
    }

    /// A refresh that waits on the server must not hold up a write: the write is queued and shown at once.
    @Test
    func aWriteIsQueuedAtOnceWhileARefreshIsHeld() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let server = HeldRefresh()
        defer { server.release() }
        let source = MarfaSource(copy: copy, connection: SampleLibrary.connection, refreshing: server)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.refresh()
        try #require(await eventually { server.filling })

        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST held", body: "Queued")), as: WriteID())
        await source.queueSubmitted()
        #expect(!server.released, "the write waited for the refresh")
        #expect(try await copy.queue.all().count == 1)
        #expect(await log.wait { $0.item(titled: "MAPPTEST held") != nil } != nil)
        #expect(!server.released)

        server.release()
        await source.close()
    }

    @Test
    func aSecondOpenerOfTheSameCopyIsRefused() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await open(root)
        let failure = await #expect(throws: SourceFailure.self) { _ = try await open(root) }
        #expect(failure?.kind == .inUse)
        await first.close()
        let again = try await open(root)
        await again.close()
    }

    @Test
    func aBodyForATypeWithoutABodyFieldIsRefused() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        let entity = try #require(painted.snapshot?.catalogue.itemTypes[TypeID("core.entity")])
        #expect(entity.bodyField == nil)
        let write = WriteID()
        source.submit(.create(id: .mint(), ItemDraft(type: entity.id, title: "Ada", body: "Typed text")), as: write)
        let answered = try #require(await log.wait { $0.answer(to: write) != nil })
        #expect(answered.answer(to: write) == .refused(SyncProblem(code: "unsupported", message: MarfaEngine.noText, notQueued: true)))
        #expect(try await source.copy.queue.all().isEmpty)
        await source.close()
    }

    /// The child is queued and answered as itself; a parent link that cannot be made is told on its own.
    @Test
    func aCreateIsKeptWhateverBecomesOfItsParentLink() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let write = WriteID()
        let child = ItemID.mint()
        source.submit(
            .create(id: child, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST child", body: "Queued", parent: ItemID("not-an-item"))),
            as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MAPPTEST child") != nil })
        #expect(queued.item(titled: "MAPPTEST child")?.id == child)
        #expect(queued.answer(to: write) == nil)
        let creates = try await source.copy.queue.all().filter { $0.kind == .createItem }
        #expect(creates.map(\.itemId) == [child.rawValue])
        await source.close()
    }

    /// A read that fails says so and keeps what was shown, rather than emptying the library or settling it.
    @Test
    func aReadThatFailsKeepsWhatWasShown() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST kept", body: "Queued")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST kept") != nil })

        await source.copy.close()
        source.hear(Change(origin: .refreshed(.caughtUp), itemId: nil, edgeId: nil))
        let failed = try #require(await log.wait { state in
            state.changes.contains { if case .unavailable = $0 { true } else { false } }
        })
        #expect(failed.item(titled: "MAPPTEST kept")?.sync == .waiting(writes: 1))
        await source.close()
    }

    /// The package takes properties as values: a text edit names the body alone, which the server merges, and a
    /// property taken away is the item's whole properties without it. Both are read back from the queue.
    @Test
    func aTextEditMergesTheBodyAndAPropertyTakenAwayReplacesTheWhole() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let id = ItemID.mint()
        let draft = ItemDraft(
            type: TypeID("core.note"), title: "MAPPTEST edits", body: "First", properties: ["description": .string("Kept")])
        source.submit(.create(id: id, draft), as: WriteID())
        let made = try #require(await log.wait { $0.item(titled: "MAPPTEST edits") != nil })
        let version = try #require(made.item(titled: "MAPPTEST edits")?.version)

        source.submit(.editBody(id, "Second", base: version, merge: .ifUnchanged), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST edits")?.sync == .waiting(writes: 2) })
        let merge = try #require(try await source.copy.queue.all().last { $0.kind == .updateItem })
        #expect(merge.body["properties"]?.object == ["body": "Second"], "only the text is named, so the server merges it")
        #expect(merge.body["properties_mode"] == nil)

        source.submit(.editProperties(id, ["description": nil], base: version, undoing: nil), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST edits")?.sync == .waiting(writes: 3) })
        let replace = try #require(try await source.copy.queue.all().last { $0.kind == .updateItem })
        #expect(replace.body["properties_mode"]?.string == "replace")
        let whole = try #require(replace.body["properties"]?.object)
        #expect(whole["description"] == nil, "the property taken away is not in the whole")
        #expect(whole["body"]?.string == "Second" && whole["title"]?.string == "MAPPTEST edits", "every other keeps its value")
        await source.close()
    }

    private func unavailable(_ state: ChangeLog.State) -> Int {
        state.changes.count { if case .unavailable = $0 { true } else { false } }
    }

    /// A stream the core ended on a fault is followed by `.resumed`, which refreshes the copy so the library leaves
    /// "stopped" once the server answers, and the person is told of the fault once until it has.
    @Test
    func aFaultTheCoreEndedAStreamOnIsToldOnceAndTheNextStreamRefreshes() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let fault = Change(origin: .stopped(.store(message: "the store failed")), itemId: nil, edgeId: nil)

        source.hear(fault)
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(await waitForConnection(source) { if case .unavailable = $0 { true } else { false } })

        source.hear(fault)
        source.hearResumed()
        // The refresh is made against a server nothing answers, so it ends offline: the library left "stopped".
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })
        #expect(unavailable(log.current) == 1, "a fault told again before anything succeeded is not told again")

        // Something succeeded: the next fault is news.
        let report = DrainReport(answered: 1)
        source.hear(Change(origin: .queueDrained(report), itemId: nil, edgeId: nil))
        #expect(await waitForConnection(source) { $0 == .online })
        source.hear(fault)
        _ = try #require(await log.wait { unavailable($0) == 2 })
        await source.close()
    }

    /// A row the copy could not read is replaced only by a hydration, which the sync asks for once for each row.
    @Test
    func aRowTheCopyCouldNotReadIsHydratedForOnceAtMost() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let sync = await source.engine.sync
        #expect(await sync.hydrations == 0)

        await sync.unreadable(["a"])
        #expect(try await eventuallyAsking { await sync.hydrations > 0 })
        #expect(await sync.hydrations == 1)

        // The same row again, as a read after the hydration finds it still unreadable, asks for nothing.
        await sync.unreadable(["a"])
        // Time for a second hydration, which nothing signals when none is asked for.
        try await Task.sleep(for: .milliseconds(500))
        #expect(await sync.hydrations == 1)
        await source.close()
    }

    @Test func aRowIsHydratedForOnlyOnceAndAnotherRowAsksAgain() {
        var asking = MarfaSync.Rehydration()
        #expect(!asking.wanted)
        let none = asking.ask(about: [])
        #expect(!none)
        let first = asking.ask(about: ["a"])
        #expect(first)
        #expect(asking.wanted)
        asking.finished()
        #expect(!asking.wanted)
        let again = asking.ask(about: ["a"])
        #expect(!again, "the row stays unreadable after the hydration: no loop")
        #expect(!asking.wanted)
        let other = asking.ask(about: ["a", "b"])
        #expect(other, "a row not asked about before does")
        #expect(asking.wanted)
    }

    @Test func aHydrationThatDidNotHappenIsStillWanted() {
        var asking = MarfaSync.Rehydration()
        _ = asking.ask(about: ["a"])
        let again = asking.ask(about: ["a"])
        #expect(!again)
        #expect(asking.wanted, "until a hydration succeeds, a retry still hydrates")
    }

    /// The follow stops when the copy expires, and only a new hydration starts it again.
    @Test
    func anExpiredCopyIsHydratedAgain() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        #expect(source.connectionState == .connecting)
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired")
        source.hear(Change(origin: .stopped(expired), itemId: nil, edgeId: nil))
        // Hydrating again against a closed port fails at once, which shows the hydration was tried.
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })
        await source.close()
    }

    private static let note = TypeID("core.note")

    /// Makes a parent and a child under it, queued in a copy no server answers, and waits until the child shows it.
    private func parentAndChild(
        _ source: MarfaSource, _ log: ChangeLog, _ names: String...
    ) async throws -> [ItemID] {
        let ids = names.map { _ in ItemID.mint() }
        for (id, name) in zip(ids, names).dropLast() {
            source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MAPPTEST \(name)", body: "Queued")), as: WriteID())
        }
        let (child, name) = (try #require(ids.last), try #require(names.last))
        source.submit(
            .create(id: child, ItemDraft(type: Self.note, title: "MAPPTEST \(name)", body: "Queued", parent: ids[0])), as: WriteID())
        _ = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.target == .item(ids[0]) } == true
        })
        return ids
    }

    /// A new parent is one queued update of the edge, shown at once and never a delete and a create, so the child
    /// holds a parent the whole time.
    @Test
    func aMovedEdgeIsOneQueuedWriteShownAtItsNewEnd() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let ids = try await parentAndChild(source, log, "parent one", "parent two", "moved child")
        let (first, second, child) = (ids[0], ids[1], ids[2])
        let edge = try #require(try await source.copy.edges.from(first.rawValue).first { $0.edgeType == MarfaMapping.parentEdge })

        let write = WriteID()
        source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: second), as: write)
        let moved = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.target == .item(second) } == true
        })
        let held = try #require(moved.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(!held.contains { $0.target == .item(first) })
        #expect(held.count == 1)
        let kinds = try await source.copy.queue.all().map(\.kind)
        #expect(kinds.filter { $0 == .updateEdge }.count == 1)
        #expect(!kinds.contains(.deleteEdge))
        #expect(moved.answer(to: write) == nil)
        await source.close()
    }

    /// The engine reads again every item a move touches, and the edge it moved is the same edge at its new ends, so
    /// the order the items are read in must not decide whether the child ends up holding it. Moved back and forth,
    /// every order is met.
    @Test
    func aChildMovedBackAndForthAlwaysShowsItsCurrentParent() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let ids = try await parentAndChild(source, log, "parent one", "parent two", "moved child")
        let (first, second, child) = (ids[0], ids[1], ids[2])
        let edge = try #require(try await source.copy.edges.from(first.rawValue).first { $0.edgeType == MarfaMapping.parentEdge })
        for step in 0..<16 {
            let parent = step.isMultiple(of: 2) ? second : first
            source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: parent), as: WriteID())
            let shown = await log.wait { state in
                state.snapshot?.items.first { $0.id == child }?.edgesOut.map(\.target) == [.item(parent)]
            }
            #expect(shown != nil, "after move \(step) the child shows \(parent == second ? "parent two" : "parent one")")
            if shown == nil { break }
        }
        await source.close()
    }

    /// What the package refuses before it queues anything is told in plain words, and nothing is queued.
    @Test
    func aMoveThePackageRefusesIsToldPlainlyAndQueuesNothing() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let ids = try await parentAndChild(source, log, "parent", "other", "child")
        let (parent, other, child) = (ids[0], ids[1], ids[2])
        source.submit(.link(EdgeDraft(type: "references", source: parent, target: other), undoing: nil), as: WriteID())
        let references = try #require(await Self.edge(of: "references", from: parent, in: source))
        let parentOf = try #require(await Self.edge(of: MarfaMapping.parentEdge, from: parent, in: source))

        // A type whose end that stays can hold many has no end to replace.
        let notReplaceable = WriteID()
        source.submit(.moveEdge(EdgeID(references.id), end: .target, to: child), as: notReplaceable)
        // A move that would leave the edge running from an item to itself.
        let selfLoop = WriteID()
        source.submit(.moveEdge(EdgeID(parentOf.id), end: .source, to: child), as: selfLoop)
        let answered = try #require(await log.wait { $0.answer(to: notReplaceable) != nil && $0.answer(to: selfLoop) != nil })
        var validation = try #require(MarfaEngine.moveProblem(.validation(code: "validation_error", message: "")))
        var cycle = try #require(MarfaEngine.moveProblem(.validation(code: "edge_cycle", message: "")))
        // Refused before anything was queued.
        validation.notQueued = true
        cycle.notQueued = true
        #expect(answered.answer(to: notReplaceable) == .refused(validation))
        #expect(answered.answer(to: selfLoop) == .refused(cycle))
        #expect(try await source.copy.queue.all().filter { $0.kind == .updateEdge }.isEmpty)
        // Both links are where they were.
        let held = try #require(answered.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(held.contains { $0.target == .item(parent) })
        await source.close()
    }

    /// A move to the end the edge already holds, as an undo after a refused move makes, is taken at once and
    /// queues nothing, since the server refuses an update that changes nothing.
    @Test
    func aMoveToTheEndTheEdgeHoldsIsTakenAndQueuesNothing() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let ids = try await parentAndChild(source, log, "parent", "child")
        let (parent, child) = (ids[0], ids[1])
        let edge = try #require(await Self.edge(of: MarfaMapping.parentEdge, from: parent, in: source))
        let before = try await source.copy.queue.all()

        let write = WriteID()
        source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: parent), as: write)
        let answered = try #require(await log.wait { $0.answer(to: write) != nil })
        #expect(answered.answer(to: write) == .accepted)
        #expect(try await source.copy.queue.all().map(\.id) == before.map(\.id))
        let held = try #require(answered.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(held.contains { $0.target == .item(parent) })
        await source.close()
    }

    /// An answer moves the person's text on only once its effect is known. One that landed elsewhere needs the
    /// version the copy holds, which an expired copy cannot read, so it stays to be counted again.
    @Test func anAnswerIsCountedOnlyOnceTheVersionItNeedsIsRead() async throws {
        struct Unreadable: Error {}
        func write(_ id: String, _ verdict: Marfa.Verdict) -> Marfa.QueuedWrite {
            Marfa.QueuedWrite(
                id: id, kind: .updateItem, itemId: "item", idempotencyKey: id, verdict: verdict,
                queuedAt: "2026-10-06T00:00:00Z")
        }
        let queue = [write("merged", .merged(fields: ["body"])), write("taken", .accepted)]
        let own = MarfaEngine.OwnText(text: "Mine", on: 3)
        var counted: Set<String> = []
        await #expect(throws: Unreadable.self) {
            _ = try await MarfaEngine.counting(queue, for: ItemID("item"), own: own, counted: &counted, sentAsRead: []) {
                throw Unreadable()
            }
        }
        #expect(counted.isEmpty)

        let moved = await MarfaEngine.counting(queue, for: ItemID("item"), own: own, counted: &counted, sentAsRead: []) {
            9
        }
        #expect(moved.on == 9)
        #expect(counted == ["merged", "taken"])
        // Counted once, the same answers move it no further.
        let again = await MarfaEngine.counting(queue, for: ItemID("item"), own: moved, counted: &counted, sentAsRead: []) {
            12
        }
        #expect(again == moved)
        // Accepted on the version it was sent on, an answer moves the text one version on without reading.
        var fresh: Set<String> = []
        let accepted = try await MarfaEngine.counting(
            [write("taken", .accepted)], for: ItemID("item"), own: own, counted: &fresh, sentAsRead: []
        ) { throw Unreadable() }
        #expect(accepted.on == 4)
    }

    private static func edge(of type: String, from id: ItemID, in source: MarfaSource) async -> Marfa.Edge? {
        _ = await LiveMarfa.until { ((try? await source.copy.edges.from(id.rawValue)) ?? []).contains { $0.edgeType == type } }
        return try? await source.copy.edges.from(id.rawValue).first { $0.edgeType == type }
    }

    /// A source move the server accepts expires the copy as the drain answers it, and the drain throws without its
    /// report. The answers are read from the queue instead, once the copy is hydrated again, so the person's write is
    /// answered and nothing queued is lost.
    @Test
    func aCopyExpiredByAMoveKeepsEveryQueuedWriteAndTheView() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let ids = try await parentAndChild(source, log, "parent one", "parent two", "kept child")
        let (first, second, child) = (ids[0], ids[1], ids[2])
        let edge = try #require(try await source.copy.edges.from(first.rawValue).first { $0.edgeType == MarfaMapping.parentEdge })
        let write = WriteID()
        source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: second), as: write)
        _ = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.target == .item(second) } == true
        })
        let queued = try await source.copy.queue.all()
        let move = try #require(queued.first { $0.kind == .updateEdge })

        // The server's answer, as the queue records it before the drain throws.
        let answered = Marfa.QueuedWrite(
            id: move.id, kind: .updateEdge, itemId: move.itemId, edgeId: edge.id, idempotencyKey: move.idempotencyKey,
            verdict: .accepted, queuedAt: move.queuedAt)
        let report = MarfaSync.report(answeredIn: queued.filter { $0.id != move.id } + [answered])
        #expect(report.verdicts.map(\.id) == [move.id])
        #expect(report.answered == 1)
        await withCheckedContinuation { taken in source.events.yield(.drained(report, taken)) }
        _ = try #require(await log.wait { $0.answer(to: write) == .accepted })

        // Then the copy hydrates again, which this closed port refuses; the queue and the view are as they were.
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired")
        source.hear(Change(origin: .stopped(expired), itemId: nil, edgeId: nil))
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })
        let after = try await source.copy.queue.all()
        #expect(Set(after.map(\.id)) == Set(queued.map(\.id)))
        let shown = try #require(log.current.snapshot?.items.first { $0.id == child })
        #expect(shown.edgesOut.contains { $0.target == .item(second) })
        #expect(shown.sync != .settled)
        await source.close()
    }

    @Test func aDrainThatThrewAfterAnAnswerIsReportedFromTheQueue() {
        func write(_ id: String, verdict: Marfa.Verdict?) -> Marfa.QueuedWrite {
            Marfa.QueuedWrite(
                id: id, kind: .updateEdge, itemId: "item", edgeId: "edge", idempotencyKey: id, verdict: verdict,
                queuedAt: "2026-10-06T00:00:00Z")
        }
        let report = MarfaSync.report(answeredIn: [write("sent", verdict: .accepted), write("waiting", verdict: nil)])
        #expect(report.verdicts.map(\.id) == ["sent"])
        #expect(report.verdicts.first?.kind == .updateEdge)
        #expect(report.verdicts.first?.edgeId == "edge")
        #expect(report.answered == 1)
        #expect(MarfaSync.report(answeredIn: []).verdicts.isEmpty)
    }

    /// The package names the item a conflicted copy was made from, from the copy alone, so the two know each other
    /// without a server and without the verdict that made the copy.
    @Test
    func aConflictedCopyIsShownBesideItsOriginal() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let original = ItemID.mint(), copy = ItemID.mint(), bystander = ItemID.mint()
        for (id, title) in [(original, "original"), (bystander, "bystander")] {
            source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MAPPTEST \(title)", body: "Queued")), as: WriteID())
        }
        source.submit(
            .create(id: copy, ItemDraft(
                type: Self.note, title: "MAPPTEST original (conflicted copy)", body: "Mine", tags: [MarfaProblems.conflictedCopyTag])),
            as: WriteID())
        // Tagged, but not yet linked: no original is known.
        _ = try #require(await log.wait { $0.snapshot?.items.first { $0.id == copy } != nil })
        #expect(log.current.snapshot?.items.first { $0.id == original }?.sync != .conflicted(sibling: copy, fields: []))
        source.submit(.link(EdgeDraft(type: "derived-from", source: copy, target: original), undoing: nil), as: WriteID())
        let linked = try #require(await log.wait { state in
            if case .conflicted(let sibling, _)? = state.snapshot?.items.first(where: { $0.id == original })?.sync {
                sibling == copy
            } else {
                false
            }
        })
        // Another item the copy was not made from is untouched.
        #expect(linked.snapshot?.items.first { $0.id == bystander }?.sync != nil)
        if case .conflicted? = linked.snapshot?.items.first(where: { $0.id == bystander })?.sync {
            Issue.record("an item the copy was not made from shows a conflict")
        }
        #expect(await LiveMarfa.until {
            source.syncReport.problems.contains { entry in
                if case .conflicted(let sibling, let from) = entry.kind { sibling == copy && from == original } else { false }
            }
        })
        #expect(try await source.copy.items.original(ofConflictedCopy: copy.rawValue) == original.rawValue)
        #expect(try await source.copy.items.conflictedCopies(of: original.rawValue).map(\.id) == [copy.rawValue])
        await source.close()
    }

    @Test func aWriteToACopyBeingBroughtUpToDateIsRefusedPlainly() {
        for error in [
            MarfaError.hydrationIncomplete(message: "hydration did not complete; hydrate again before reading"),
            MarfaError.copyExpired(reason: "catchup_too_old", message: "the copy expired")
        ] {
            #expect(MarfaEngine.problem(for: error) == SyncProblem(code: error.code(), message: MarfaEngine.notCurrent))
        }
        let other = MarfaError.validation(code: "invalid_properties", message: "body: Required field is missing")
        #expect(MarfaEngine.problem(for: other) == SyncProblem(code: "invalid_properties", message: other.message))
        // The package's own refusal names the server's code, as a drain's verdict would.
        let reserved = MarfaError.forbidden(code: "type_not_permitted", message: "system.folder is written only through its own operation")
        #expect(MarfaEngine.problem(for: reserved).code == "type_not_permitted")
    }

    @Test func aDrainIsJudgedByWhatItCouldNotSend() {
        #expect(MarfaSync.result(of: DrainReport()) == .idle)
        #expect(MarfaSync.result(of: DrainReport(answered: 2)) == .online)
        // The core answers a refused key `blocked`, which counts as answered, and then parks the queue.
        #expect(MarfaSync.result(of: DrainReport(answered: 1, stopped: "credential_refused")) == .parked("credential_refused"))
        #expect(MarfaSync.result(of: DrainReport(answered: 1, undelivered: 2, unavailable: "network: timeout")) ==
            .offline("network: timeout"))
        #expect(MarfaSync.result(of: DrainReport(undelivered: 1, unavailable: "io: refused")) == .offline("io: refused"))
    }

    @Test func aRetryWaitsLongerAfterEachFailureUpToFiveMinutes() {
        #expect(MarfaSync.delay(after: 1) == .seconds(5))
        #expect(MarfaSync.delay(after: 2) == .seconds(10))
        #expect(MarfaSync.delay(after: 7) == .seconds(300))
        #expect(MarfaSync.delay(after: 100) == .seconds(300))
    }
}

extension LiveMarfaTests {
    /// Against the test instance, in the Live test plan. Every item it makes has a title starting `MAPPTEST ` and is purged when the test ends, passed or not, over HTTP with the key's
    /// `items.purge`, which reaches an item the copy never held or has let go of.
    @Suite(.serialized)
    struct MarfaSourceLiveTests {
        private static let note = TypeID("core.note")

        private func open(_ root: URL) async throws -> MarfaSource {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            return try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]),
                location: MarfaStoreLocation(root: root))
        }

        /// Refreshes a fresh copy and waits until it holds the whole library and the engine has published it.
        private func hydrated(_ source: MarfaSource) async throws {
            source.refresh()
            try #require(await eventually { LiveMarfa.isWhole(source.syncReport) && source.connectionState == .online })
            await source.engineTook()
        }

        /// Runs `body` with a fresh copy, already refreshed, and purges every id it mints, however it ends.
        private func withSource(
            _ body: (MarfaSource, ChangeLog, LiveMarfa.Made) async throws -> Void
        ) async throws {
            let root = scratch()
            let made = LiveMarfa.Made()
            let source = try await open(root)
            let log = ChangeLog(source)
            do {
                try await hydrated(source)
                _ = try #require(await log.wait { $0.snapshot != nil })
                try await body(source, log, made)
            } catch {
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            await source.close()
            await LiveMarfa.purge(made.ids)
            try? FileManager.default.removeItem(at: root)
        }

        @Test(.timeLimit(.minutes(2)))
        func readsTheLibraryAndPaintsItAgainBeforeTheNetwork() async throws {
            let root = scratch()
            let made = LiveMarfa.Made()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                try await readsAndPaintsAgain(root, made)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        private func readsAndPaintsAgain(_ root: URL, _ made: LiveMarfa.Made) async throws {
            let source = try await open(root)
            let log = ChangeLog(source)
            try await hydrated(source)
            let catalogue = try #require(await log.wait { $0.snapshot != nil }?.snapshot?.catalogue)
            #expect(catalogue.itemTypes[Self.note]?.titleField == "title")
            #expect(catalogue.edgeTypes[MarfaMapping.parentEdge]?.reverseName == "child-of")

            // A child holds its parent as `child-of`, and the copy lists it beneath the parent.
            let token = "zp" + UUID().uuidString.prefix(8).lowercased()
            let parent = made.mint(), child = made.mint()
            source.submit(.create(id: parent, ItemDraft(type: Self.note, title: "MAPPTEST parent \(token)", body: "Above.")), as: WriteID())
            source.submit(
                .create(id: child, ItemDraft(type: Self.note, title: "MAPPTEST child \(token)", body: "Below.", parent: parent)),
                as: WriteID())
            await source.flush()
            let filed = try #require(await log.wait { state in
                [parent, child].allSatisfy { id in state.snapshot?.items.first { $0.id == id }?.sync == .settled }
                    && state.snapshot?.items.first { $0.id == child }?.edgesOut.contains {
                        $0.type == "child-of" && $0.target == .item(parent)
                    } == true
            })
            let snapshot = try #require(filed.snapshot)
            #expect(snapshot.items.allSatisfy { !$0.title.isEmpty })
            let beneath = try await source.copy.items.list(ListFilters(beneath: parent.rawValue)).map { ItemID($0.id) }
            #expect(Set(beneath).subtracting([parent]) == [child])

            let parentItem = try #require(snapshot.items.first { $0.id == parent })
            let body = try await source.body(of: parent)
            #expect(body.text == "Above.")
            #expect(body.version == parentItem.version)
            #expect(parentItem.properties.allSatisfy { $0.key != "body" })

            #expect(await LiveMarfa.until {
                (try? await source.search("\(token)", in: .items(ItemQuery(types: [Self.note]))))?.hits.contains(parent) == true
            })
            let found = try await source.search(token, in: .items(ItemQuery(types: [Self.note]))).hits
            #expect(found.allSatisfy { id in snapshot.items.first { $0.id == id }?.type == Self.note })
            let count = try #require(log.current.snapshot?.items.count)
            await source.close()

            let reopened = try await open(root)
            let again = ChangeLog(reopened)
            let repainted = try #require(await again.wait { $0.snapshot != nil })
            #expect(repainted.snapshot?.items.count == count)
            #expect(repainted.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.target == .item(parent) } == true)
            #expect(reopened.connectionState == .connecting)
            await reopened.close()
        }

        @Test(.timeLimit(.minutes(2)))
        func favoritesEditsArchivesAndBinsItsOwnItem() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST favorite \(UUID().uuidString.prefix(8))"
                let created = WriteID()
                let id = made.mint()
                source.submit(
                    .create(id: id, ItemDraft(type: Self.note, title: title, body: "Made by the MAPP tests.", tags: ["mapptest"])),
                    as: created)
                let answered = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
                #expect(answered.answer(to: created) == .accepted)
                let item = try #require(answered.item(titled: title))
                #expect(item.id == id)
                #expect(item.tags == ["mapptest"])
                #expect(item.properties.map(\.key) == ["title"])

                func apply(_ write: ItemWrite) async throws -> ChangeLog.State {
                    let id = WriteID()
                    source.submit(write, as: id)
                    let answered = try #require(await log.wait { $0.answer(to: id) != nil })
                    #expect(answered.answer(to: id) == .accepted, "\(write)")
                    return try #require(await log.wait { $0.item(titled: title)?.sync == .settled })
                }

                var state = try await apply(.tag(item.id, ItemTag.favorite, on: true))
                #expect(state.item(titled: title)?.isFavorite == true)
                let favorites = ItemQuery(tags: [ItemTag.favorite])
                let favorite = try #require(state.item(titled: title))
                #expect(favorites.matches(favorite, catalogue: try #require(state.snapshot?.catalogue)))

                state = try await apply(.editBody(item.id, "Edited by the MAPP tests.", base: favorite.version, merge: .ifUnchanged))
                #expect(try await source.body(of: item.id).text == "Edited by the MAPP tests.")

                state = try await apply(.tag(item.id, ItemTag.favorite, on: false))
                #expect(state.item(titled: title)?.isFavorite == false)

                state = try await apply(.transition(item.id, .archived))
                #expect(state.item(titled: title)?.state == .archived)
                state = try await apply(.transition(item.id, .active))
                #expect(state.item(titled: title)?.state == .active)

                // The tier moves as an edit, and the item stays in the one copy at its new tier.
                let current = try #require(state.item(titled: title))
                state = try await apply(.retier(item.id, .feed, base: current.version))
                #expect(state.item(titled: title)?.tier == .feed)
                state = try await apply(.retier(item.id, .library, base: try #require(state.item(titled: title)).version))
                #expect(state.item(titled: title)?.tier == .library)

                // The server keeps the bin once the delete is sent, and the item stays shown from it.
                let binned = WriteID()
                source.submit(.transition(item.id, .trashed), as: binned)
                let inBin = try #require(await log.wait { $0.answer(to: binned) != nil && $0.item(titled: title)?.state == .trashed })
                #expect(inBin.answer(to: binned) == .accepted)
                #expect(try await source.body(of: item.id).text == "Edited by the MAPP tests.")

                // Restoring an item the copy let go of is made by its id, and the item arrives once it is answered.
                state = try await apply(.transition(item.id, .active))
                #expect(state.item(titled: title)?.state == .active)

                // Delete Permanently destroys an item in the bin, at the version shown, and takes it out of the copy.
                let again = WriteID()
                source.submit(.transition(item.id, .trashed), as: again)
                _ = try #require(await log.wait { $0.answer(to: again) != nil && $0.item(titled: title)?.state == .trashed })
                let shown = try #require(log.current.item(titled: title))
                let purge = WriteID()
                source.submit(.purge(item.id, version: shown.version), as: purge)
                let gone = try #require(await log.wait { $0.answer(to: purge) != nil && $0.item(titled: title) == nil })
                #expect(gone.answer(to: purge) == .accepted)
                #expect(!(try await source.copy.items.bin()).items.contains { $0.id == item.id.rawValue })

                // An item that was never in the bin is refused, and nothing is destroyed.
                let live = made.mint()
                let made2 = WriteID()
                source.submit(.create(id: live, ItemDraft(type: Self.note, title: title + " live", body: "Stays.")), as: made2)
                _ = try #require(await log.wait { $0.answer(to: made2) != nil && $0.item(titled: title + " live")?.sync == .settled })
                let refusedPurge = WriteID()
                source.submit(.purge(live, version: try #require(log.current.item(titled: title + " live")).version), as: refusedPurge)
                let notInBin = try #require(await log.wait { $0.answer(to: refusedPurge) != nil })
                guard case .refused = notInBin.answer(to: refusedPurge) else {
                    Issue.record("a purge of an item outside the bin was not refused: \(String(describing: notInBin.answer(to: refusedPurge)))")
                    return
                }
                #expect(log.current.item(titled: title + " live") != nil)
            }
        }

        /// The copy holds both tiers, so the Inbox, which is the feed, and the rest of the library read from one copy.
        @Test(.timeLimit(.minutes(2)))
        func holdsBothTiersInOneCopy() async throws {
            try await withSource { source, log, made in
                let status = try await source.copy.status()
                #expect(status.sliceTier == .all)
                let token = UUID().uuidString.prefix(8)
                let captured = made.mint(), filed = made.mint()
                source.submit(.create(id: captured, ItemDraft(type: Self.note, title: "MAPPTEST feed \(token)", tier: .feed)), as: WriteID())
                source.submit(.create(id: filed, ItemDraft(type: Self.note, title: "MAPPTEST library \(token)")), as: WriteID())
                await source.flush()
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == captured }?.tier == .feed
                        && state.snapshot?.items.first { $0.id == filed }?.tier == .library
                })
                // The copy's whole feed, the Inbox, is in the one snapshot beside the library's items.
                let feed = Set(try await source.copy.items.list(ListFilters(tier: .feed)).map { ItemID($0.id) })
                #expect(feed.contains(captured) && !feed.contains(filed))
                #expect(await log.wait { state in feed.isSubset(of: Set(state.snapshot?.items.map(\.id) ?? [])) } != nil)
            }
        }

        /// An editor that read the item before another device's edit arrived saves twice from that read: the first is
        /// merged against what it read, and the second follows the first rather than conflicting with it.
        @Test(.timeLimit(.minutes(2)))
        func editsReadBeforeAnotherDevicesEditAreMerged() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST as read \(UUID().uuidString.prefix(8))"
                let id = made.mint()
                let created = WriteID()
                source.submit(.create(id: id, ItemDraft(type: Self.note, title: title, body: "One")), as: created)
                let read = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
                let version = try #require(read.item(titled: title)?.version)

                let otherRoot = scratch()
                defer { try? FileManager.default.removeItem(at: otherRoot) }
                try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
                let address = try #require(URL(string: try LiveMarfa.address()))
                let key = try LiveMarfa.key()
                let other = try await WorkingCopy.open(
                    store: otherRoot.appending(path: "other.sqlite"), server: Server(url: address, key: key))
                _ = try await other.hydrate(types: ["core.*"], tier: .library)
                let row = try #require(try await other.items.get(id.rawValue))
                _ = try await other.items.update(id.rawValue, Edit(properties: ["description": .string("From another device")], baseVersion: row.version))
                _ = try await other.queue.drain()
                await other.close()
                _ = try #require(await log.wait { ($0.item(titled: title)?.version ?? version) > version })

                let first = WriteID(), second = WriteID()
                source.submit(.editBody(id, "Two", base: version, merge: .asRead), as: first)
                source.submit(.editBody(id, "Three", base: version, merge: .following), as: second)
                let answered = try #require(await log.wait {
                    $0.answer(to: first) != nil && $0.answer(to: second) != nil && $0.item(titled: title)?.sync == .settled
                })
                for write in [first, second] {
                    switch answered.answer(to: write) {
                    case .accepted, .merged: break
                    case let other: Issue.record("an edit read earlier was answered \(String(describing: other))")
                    }
                }
                #expect(try await source.body(of: id).text == "Three")
                #expect(answered.item(titled: title)?.value(of: "description") == .string("From another device"))
                source.submit(.transition(id, .trashed), as: WriteID())
                await source.flush()
            }
        }

        /// A conflict answered in an earlier launch, and not yet forgotten, stays shown through later writes.
        @Test(.timeLimit(.minutes(2)))
        func aConflictFromAnEarlierLaunchStaysShown() async throws {
            let root = scratch()
            let made = LiveMarfa.Made()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                try await conflictFromAnEarlierLaunch(root, made)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        private func conflictFromAnEarlierLaunch(_ root: URL, _ made: LiveMarfa.Made) async throws {
            let address = try LiveMarfa.address(), key = try LiveMarfa.key()
            let connection = try MarfaConnection(address: address)
            let location = MarfaStoreLocation(root: root)
            let keys = MemoryKeyStore([connection: key])
            let a = made.mint(), b = made.mint()
            let tag = UUID().uuidString.prefix(8)

            var source = try await MarfaSource.open(connection, keys: keys, location: location)
            var log = ChangeLog(source)
            try await hydrated(source)
            source.submit(.create(id: a, ItemDraft(type: Self.note, title: "MAPPTEST earlier A \(tag)", body: "One")), as: WriteID())
            source.submit(.create(id: b, ItemDraft(type: Self.note, title: "MAPPTEST earlier B \(tag)", body: "One")), as: WriteID())
            let both = try #require(await log.wait { state in
                [a, b].allSatisfy { id in state.snapshot?.items.first { $0.id == id }?.sync == .settled }
            })
            let version = try #require(both.snapshot?.items.first { $0.id == a }?.version)
            await source.close()

            let otherRoot = scratch()
            defer { try? FileManager.default.removeItem(at: otherRoot) }
            try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
            let other = try await WorkingCopy.open(store: otherRoot.appending(path: "other.sqlite"), server: connection.server(key: key))
            _ = try await other.hydrate(types: ["core.*"], tier: .library)
            let row = try #require(try await other.items.get(a.rawValue))
            _ = try await other.items.update(a.rawValue, Edit(properties: ["body": .string("Another device")], baseVersion: row.version))
            _ = try await other.queue.drain()
            await other.close()

            // The app's own store, edited from the version it holds, drained, and closed before it forgot the answer.
            let raw = try await WorkingCopy.open(store: location.store(for: connection), server: connection.server(key: key))
            _ = try await raw.items.update(a.rawValue, Edit(properties: ["body": .string("This device")], baseVersion: version.rawValue))
            let report = try await raw.queue.drain()
            let sibling = report.verdicts.compactMap { answer -> String? in
                if case .conflicted(let sibling, _)? = answer.verdict { sibling } else { nil }
            }.first
            if let sibling { made.add(ItemID(sibling)) }
            await raw.close()
            _ = try #require(sibling)

            source = try await MarfaSource.open(connection, keys: keys, location: location)
            log = ChangeLog(source)
            let reopened = try #require(await log.wait { $0.snapshot != nil })
            guard case .conflicted? = reopened.snapshot?.items.first(where: { $0.id == a })?.sync else {
                Issue.record("the earlier conflict is not shown")
                await source.close()
                return
            }
            source.refresh()
            #expect(await waitForConnection(source) { $0 == .online })
            let tagged = WriteID()
            source.submit(.tag(b, ItemTag.favorite, on: true), as: tagged)
            _ = try #require(await log.wait { $0.answer(to: tagged) != nil })
            await source.flush()
            let after = try #require(await log.wait { state in
                state.snapshot?.items.first { $0.id == b }?.sync == .settled
            })
            guard case .conflicted? = after.snapshot?.items.first(where: { $0.id == a })?.sync else {
                Issue.record("a later write cleared the earlier conflict")
                await source.close()
                return
            }
            await source.close()

            // The answer is forgotten by now; the copy and its original still know each other, from the copy alone.
            let relaunched = try await MarfaSource.open(connection, keys: keys, location: location)
            let relaunchedLog = ChangeLog(relaunched)
            let painted = try #require(await relaunchedLog.wait { $0.snapshot != nil })
            guard case .conflicted(let copy?, _)? = painted.snapshot?.items.first(where: { $0.id == a })?.sync else {
                Issue.record("the original does not show its copy after the answer was forgotten")
                await relaunched.close()
                return
            }
            #expect(copy.rawValue == sibling)
            #expect(try await relaunched.copy.items.original(ofConflictedCopy: copy.rawValue) == a.rawValue)
            #expect(await LiveMarfa.until {
                relaunched.syncReport.problems.contains { entry in
                    if case .conflicted(let shown, let from) = entry.kind { shown == copy && from == a } else { false }
                }
            })
            await relaunched.close()
        }

        /// The drain ends, and a flush returns, only once the engine has taken the answers, so the next drain waits.
        @Test(.timeLimit(.minutes(2)))
        func aDrainWaitsUntilTheLastAnswersAreTaken() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST drains \(UUID().uuidString.prefix(8))"
                let id = made.mint()
                let created = WriteID()
                source.submit(.create(id: id, ItemDraft(type: Self.note, title: title, body: "One")), as: created)
                _ = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })

                let holding = LiveMarfa.Flag()
                await source.engine.whenAnswering {
                    holding.set()
                    // Holds the answers for longer than the check below waits, as a slow engine would.
                    try? await Task.sleep(for: .seconds(2))
                }
                let before = await source.engine.sync.drains
                let tagged = WriteID()
                source.submit(.tag(id, ItemTag.favorite, on: true), as: tagged)
                #expect(await LiveMarfa.until { holding.isSet })
                await source.engine.sync.drain()
                // Time for a second drain, which nothing signals when none is sent. It is shorter than the hold above,
                // so the answers are still held and the count must not have moved.
                try await Task.sleep(for: .milliseconds(800))
                #expect(await source.engine.sync.drains == before + 1)
                await source.engine.whenAnswering(nil)
                _ = try #require(await log.wait { $0.answer(to: tagged) != nil })
                #expect(await LiveMarfa.until { await source.engine.sync.drains == before + 2 })
                source.submit(.transition(id, .trashed), as: WriteID())
                await source.flush()
            }
        }

        /// A new parent is one move the server takes in one write. It changes the copy's read view, so the drain
        /// throws as it answers, and the copy hydrates again: the move is answered, the child is under its new parent,
        /// and a write queued behind the move is sent and answered too.
        @Test(.timeLimit(.minutes(2)))
        func aMovedParentIsAnsweredAndTheCopyHydratesAgainKeepingTheQueue() async throws {
            try await withSource { source, log, made in
                let token = UUID().uuidString.prefix(8)
                let first = made.mint(), second = made.mint(), child = made.mint()
                let creates = [first, second].map { _ in WriteID() }
                for (id, write) in zip([first, second], creates) {
                    source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MAPPTEST parent \(id.rawValue) \(token)", body: "One")), as: write)
                }
                source.submit(
                    .create(id: child, ItemDraft(type: Self.note, title: "MAPPTEST moved \(token)", body: "One", parent: first)),
                    as: WriteID())
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == child }?.sync == .settled
                        && state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.target == .item(first) } == true
                })
                await source.flush()
                let edge = try #require(try await source.copy.edges.from(first.rawValue).first { $0.edgeType == MarfaMapping.parentEdge })

                let move = WriteID(), tagged = WriteID()
                source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: second), as: move)
                source.submit(.tag(child, ItemTag.favorite, on: true), as: tagged)
                let done = try #require(await log.wait { state in
                    state.answer(to: move) != nil && state.answer(to: tagged) != nil
                        && state.snapshot?.items.first { $0.id == child }?.sync == .settled
                })
                #expect(done.answer(to: move) == .accepted)
                #expect(done.answer(to: tagged) == .accepted)
                // The answers are told once the copy is hydrated again, so reading the moved ends fails nowhere.
                let unavailable = done.changes.compactMap { change -> String? in
                    if case .unavailable(let failure) = change { failure.message } else { nil }
                }
                #expect(unavailable.isEmpty, "\(unavailable)")
                let moved = try #require(done.snapshot?.items.first { $0.id == child })
                #expect(moved.edgesOut.contains { $0.target == .item(second) })
                #expect(!moved.edgesOut.contains { $0.target == .item(first) })
                #expect(moved.isFavorite)
                #expect(try await source.copy.edges.from(second.rawValue).contains { $0.targetId == child.rawValue })
                #expect(try await source.copy.queue.all().isEmpty)
                #expect(await waitForConnection(source) { $0 == .online })
            }
        }

        /// A cycle through other edges is the server's to judge: it refuses the move, and the edge is where it was.
        @Test(.timeLimit(.minutes(2)))
        func aMoveThatClosesACycleIsRefusedAndTheEdgeStays() async throws {
            try await withSource { source, log, made in
                let token = UUID().uuidString.prefix(8)
                let a = made.mint(), b = made.mint(), c = made.mint()
                source.submit(.create(id: a, ItemDraft(type: Self.note, title: "MAPPTEST cycle a \(token)", body: "One")), as: WriteID())
                source.submit(.create(id: b, ItemDraft(type: Self.note, title: "MAPPTEST cycle b \(token)", body: "One", parent: a)), as: WriteID())
                source.submit(.create(id: c, ItemDraft(type: Self.note, title: "MAPPTEST cycle c \(token)", body: "One", parent: b)), as: WriteID())
                _ = try #require(await log.wait { state in
                    [b, c].allSatisfy { id in
                        state.snapshot?.items.first { $0.id == id }.map { $0.sync == .settled && !$0.edgesOut.isEmpty } == true
                    }
                })
                await source.flush()
                let edge = try #require(try await source.copy.edges.from(a.rawValue).first { $0.targetId == b.rawValue })
                // `c` is below `b`, so it cannot become `b`'s parent.
                let move = WriteID()
                source.submit(.moveEdge(EdgeID(edge.id), end: .source, to: c), as: move)
                let refused = try #require(await log.wait { $0.answer(to: move) != nil })
                guard case .refused(let problem)? = refused.answer(to: move) else {
                    Issue.record("the move was answered \(String(describing: refused.answer(to: move)))")
                    return
                }
                #expect(problem.code == "edge_cycle")
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == b }?.edgesOut.contains { $0.target == .item(a) } == true
                })
                #expect(try await source.copy.edges.from(a.rawValue).contains { $0.targetId == b.rawValue })
            }
        }

        /// The package refuses a create of a reserved type before queueing it, with the server's own code, so it is
        /// answered at once, nothing waits in the queue, and nothing reaches the server.
        @Test(.timeLimit(.minutes(2)))
        func aWriteThePackageRefusesIsAnsweredAtOnceAndNotQueued() async throws {
            try await withSource { source, log, made in
                let write = WriteID()
                let id = made.mint()
                source.submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: "MAPPTEST refused")), as: write)
                let answered = try #require(await log.wait { $0.answer(to: write) != nil })
                guard case .refused(let problem) = answered.answer(to: write) else {
                    Issue.record("the create was not refused: \(String(describing: answered.answer(to: write)))")
                    return
                }
                #expect(problem.code == "type_not_permitted")
                #expect(problem.notQueued)
                #expect(problem.message?.isEmpty == false)
                #expect(try await source.copy.queue.all().isEmpty)
                #expect(source.syncReport.problems.isEmpty)
                #expect(try await source.copy.items.get(id.rawValue) == nil)
            }
        }
    }
}

/// Every suite that writes to the test instance, one after another, since each reads what the server holds and
/// another's writes would arrive in the middle. Only the Live test plan runs it, with the instance's address and key
/// in `MARFA_API_URL` and `MARFA_API_KEY`; without them each test fails rather than skips.
@Suite(.serialized, .tags(.live))
struct LiveMarfaTests {}

extension Tag {
    /// Tests that need the test instance: the Live test plan runs them and the Unit plan leaves them out.
    @Tag static var live: Self
}

nonisolated enum LiveMarfa {
    /// The test instance's address, from the Live test plan's environment.
    static func address() throws -> String { try setting("MARFA_API_URL") }

    /// A key for the test instance, from the Live test plan's environment.
    static func key() throws -> String { try setting("MARFA_API_KEY") }

    private static func setting(_ name: String) throws -> String {
        let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try #require(value.isEmpty ? nil : value, "The Live test plan needs \(name) for the test instance in the environment")
    }

    /// The ids a test minted, each of which is purged when it ends.
    final class Made: Sendable {
        private let minted = Mutex<[ItemID]>([])

        var ids: [ItemID] { minted.withLock { $0 } }

        func mint() -> ItemID {
            let id = ItemID.mint()
            add(id)
            return id
        }

        func add(_ id: ItemID) {
            minted.withLock { $0.append(id) }
        }
    }

    final class Flag: Sendable {
        private let value = Mutex(false)
        var isSet: Bool { value.withLock { $0 } }
        func set() { value.withLock { $0 = true } }
    }

    /// Whether a copy holds the whole library. A large library is listed in pages, with its relationships and the
    /// feed after its first rows, and a move of an edge's source hydrates it again, so a test that reads what the
    /// server holds, or writes a relationship, waits for this.
    static func isWhole(_ report: SyncReport) -> Bool {
        report.fill?.state == .complete && report.phase == .current
    }

    static func until(_ condition: () async -> Bool) async -> Bool {
        (try? await eventuallyAsking(condition)) ?? false
    }

    /// Bins and then purges each item over HTTP. An item never made answers 404, which is fine.
    static func purge(_ ids: [ItemID]) async {
        guard let address = try? address(), let key = try? key(), let base = URL(string: address) else { return }
        for id in ids {
            for (method, path) in [("DELETE", "items/\(id.rawValue)"), ("POST", "items/\(id.rawValue)/purge")] {
                var request = URLRequest(url: base.appending(path: path))
                request.httpMethod = method
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let status = (try? await URLSession.shared.data(for: request))
                    .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
                if method == "POST", let status, ![200, 204, 404].contains(status) {
                    Issue.record("purging a test item answered \(status)")
                }
            }
        }
    }
}

/// Quitting and closing over a real copy whose server refuses every connection: each test failed on the code
/// before the connect review's fixes.
@Suite(.serialized, .hangLimit)
struct MarfaSourceClosingTests {
    private func open() async throws -> (MarfaSource, MarfaConnection, MemoryKeyStore, MarfaStoreLocation, URL) {
        let root = scratch()
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, keys: keys, location: location)
        return (source, connection, keys, location, root)
    }

    /// A write made the moment before quitting is in the queue once `queueSubmitted` returns, which never waits
    /// for the server, so it is there at the next launch.
    @Test
    func aWriteMadeJustBeforeQuittingIsKept() async throws {
        let (source, connection, keys, location, root) = try await open()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST quit", body: "Typed at once")), as: WriteID())
        await source.queueSubmitted()
        await source.close()

        let reopened = try await MarfaSource.open(connection, keys: keys, location: location)
        let log = ChangeLog(reopened)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        let kept = try #require(painted.item(titled: "MAPPTEST quit"))
        #expect(kept.id == id)
        #expect(try await reopened.body(of: id).text == "Typed at once")
        await reopened.close()
    }

    /// A write that reaches the source after it closed is kept nowhere, and says so rather than vanishing.
    @Test
    func aWriteAfterClosingIsToldItWasNotKept() async throws {
        let (source, _, _, _, root) = try await open()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })

        // Closed, with the stream still taking events, as while a close that read the queue is finishing.
        await withCheckedContinuation { source.events.yield(.close($0)) }
        let late = WriteID()
        #expect(source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Late", body: "")), as: late))
        let told = try #require(await log.wait { $0.answer(to: late) != nil })
        guard case .refused(let problem) = told.answer(to: late) else {
            Issue.record("a late write was answered \(String(describing: told.answer(to: late)))")
            return
        }
        #expect(problem.message == MarfaEngine.notKept)

        source.events.finish()
        #expect(!source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Later", body: "")), as: WriteID()))
    }
}
