import Foundation
import Marfa
import MarfaTesting
import SQLite3
import Synchronization
import Testing
@testable import MarfaMac

/// Everything a source has told one reader, and the library as that reader would hold it.
nonisolated final class ChangeLog: Sendable {
    nonisolated struct State {
        var changes: [SourceChange] = []
        var snapshot: SourceSnapshot?

        /// The first snapshot the source told, which a later change can have taken an item from before a poll sees it.
        var painted: SourceSnapshot? {
            for case .loaded(let snapshot) in changes { return snapshot }
            return nil
        }

        func item(titled title: String) -> MarfaMac.Item? {
            snapshot?.items.first { $0.title == title }
        }

        func answer(to id: WriteID) -> WriteOutcome? {
            for case .answered(id, let outcome, _) in changes { return outcome }
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

/// A complete copy that counts the hydrations it is asked for and says nothing by itself.
private nonisolated final class CountingRefresh: MarfaRefreshing {
    private let count = Mutex(0)
    var hydrations: Int { count.withLock { $0 } }

    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        count.withLock { $0 += 1 }
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
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)

        let source = try await MarfaSource.open(connection, signIns: keys, location: location)
        let log = ChangeLog(source)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        guard case .loaded(let first) = painted.changes.first else { Issue.record("the first change is not loaded"); return }
        #expect(first.items.isEmpty)
        #expect(first.catalogue.itemTypes[TypeID("core.note")] != nil)
        #expect(source.connectionState != .online, "a copy is not online before the server has answered")

        // The first fill cannot reach the server. The package shows the copy offline and asks for a hydration again
        // when its wait ends, so it is shown neither online nor as a fault.
        source.refresh()
        try #require(await eventuallyAsking { await source.engine.sync.hooks.hydrations >= 1 })
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })
        if case .unavailable = source.connectionState { Issue.record("an unreachable server was shown as a fault") }

        let write = WriteID()
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST offline", body: "Kept")), as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MARFAMACTEST offline") != nil })
        #expect(queued.item(titled: "MARFAMACTEST offline")?.id == id)
        #expect(queued.item(titled: "MARFAMACTEST offline")?.sync == .waiting(writes: 1))
        #expect(queued.answer(to: write) == nil)
        await source.flush()
        await source.close()

        let reopened = try await MarfaSource.open(connection, signIns: keys, location: location)
        let again = ChangeLog(reopened)
        let repainted = try #require(await again.wait { $0.snapshot != nil })
        let kept = try #require(repainted.item(titled: "MARFAMACTEST offline"))
        #expect(kept.sync == .waiting(writes: 1))
        #expect(try await reopened.body(of: kept.id).text == "Kept")
        #expect(reopened.connectionState != .online, "a copy is not online before the server has answered")
        await reopened.close()
    }

    /// The copy drains what waited when the server is back and records the answers. The engine takes them from the
    /// queue, as for a drain `MarfaSync` ran.
    @Test
    func aDrainTheCopyRunsItselfAnswersTheWrite() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let write = WriteID()
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST follow drain", body: "One")), as: write)
        _ = try #require(await log.wait { $0.item(titled: "MARFAMACTEST follow drain") != nil })
        let queued = try #require(try await source.copy.queue.all().first)

        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        try MarfaDrainAnswersTests.recordAccepted(queued.id, at: MarfaStoreLocation(root: root).store(for: connection))
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: write) == .accepted })
        await source.close()
    }

    /// The engine queues a state or tier write only while the copy shows the item as the step left it, and skips
    /// one it would make no change with, so nothing follows a write that was never taken.
    @Test
    func aStateOrTierWriteTheCopyNoLongerFitsIsSkippedNotTaken() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST judged", body: "One")), as: WriteID())
        let item = try #require(await log.wait { $0.item(titled: "MARFAMACTEST judged") != nil }?.item(titled: "MARFAMACTEST judged"))

        let skipped = MarfaEngine.skipped(.changedSince).problem
        for write in [ItemWrite.restore(id), .transition(id, .active, from: .archived), .retier(id, .library, base: item.version)] {
            let sent = WriteID()
            source.submit(write, as: sent)
            let answered = try #require(await log.wait { $0.answer(to: sent) != nil })
            guard case .refused(let problem) = answered.answer(to: sent) else {
                Issue.record("\(write) was answered \(String(describing: answered.answer(to: sent)))")
                continue
            }
            #expect(problem.code == skipped.code, "\(write)")
        }

        // One that fits is queued, and the next is judged against the copy with it.
        let archived = WriteID()
        source.submit(.transition(id, .archived, from: .active), as: archived)
        let unarchived = WriteID()
        source.submit(.transition(id, .active, from: .archived), as: unarchived)
        let taken = try #require(await log.wait { state in
            state.changes.contains { if case .taken(unarchived) = $0 { true } else { false } }
        })
        #expect(taken.answer(to: archived) == nil)

        // An item the copy shows in Recently Deleted is judged as there, never as one the copy does not hold.
        source.submit(.transition(id, .trashed, from: .active), as: WriteID())
        let inBin = MarfaEngine.skipped(.inBin).problem
        for write in [ItemWrite.transition(id, .archived, from: .active), .retier(id, .feed, base: item.version)] {
            let sent = WriteID()
            source.submit(write, as: sent)
            let answered = try #require(await log.wait { $0.answer(to: sent) != nil })
            guard case .refused(let problem) = answered.answer(to: sent) else {
                Issue.record("\(write) was answered \(String(describing: answered.answer(to: sent)))")
                continue
            }
            #expect(problem.code == inBin.code, "\(write)")
        }
        await source.close()
    }

    /// A copy an earlier version made is refused with what it holds that the server has not taken, and nothing in
    /// it is removed.
    @Test
    func aCopyADifferentVersionMadeIsRefusedWithItsUnsentChangesAndKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, signIns: keys, location: location)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.submit(.create(id: ItemID.mint(), ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST kept", body: "Kept")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MARFAMACTEST kept") != nil })
        await source.flush()
        await source.close()
        try Self.makeItAnEarlierVersion(location.store(for: connection))

        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, signIns: keys, location: location)
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
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, signIns: keys, location: location)
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

        let reopened = try await MarfaSource.open(connection, signIns: keys, location: location)
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
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)
        try await MarfaSource.open(connection, signIns: keys, location: location).close()
        let store = location.store(for: connection)
        try Self.execute(store, "PRAGMA user_version = 5; ALTER TABLE queue RENAME COLUMN depends_on TO depends")
        let before = try Self.inode(store)

        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, signIns: keys, location: location)
        }
        #expect(failure?.kind == .otherVersion(unsent: nil))
        #expect(try Self.inode(store) == before)
        #expect(try Self.count(store, "SELECT COUNT(*) FROM pragma_table_info('queue') WHERE name = 'depends'") == 1)
    }

    /// Another copy of the app holding the copy as its writer may still write to it, so it is never replaced. The
    /// lock is held by a different process, as another copy of the app would hold it.
    @Test
    func aCopyADifferentVersionMadeThatAnotherProcessHoldsIsKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)
        try await MarfaSource.open(connection, signIns: keys, location: location).close()
        let store = location.store(for: connection)
        try Self.makeItAnEarlierVersion(store)
        let before = try Self.inode(store)

        let holder = try await OtherProcessLock(store)
        defer { holder.release() }
        let failure = await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, signIns: keys, location: location)
        }
        #expect(failure?.kind == .inUse)
        #expect(try Self.inode(store) == before)

        // Once that process lets go, the copy is replaced.
        holder.release()
        let reopened = try await MarfaSource.open(connection, signIns: keys, location: location)
        #expect(try Self.inode(store) != before)
        await reopened.close()
    }

    private static func inode(_ file: URL) throws -> UInt64 {
        try #require(FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? UInt64)
    }

    /// Gives the store the schema version and the queue the write kind an earlier build used, as the package's own
    /// test does.
    static func makeItAnEarlierVersion(_ store: URL) throws {
        try execute(
            store,
            """
            PRAGMA user_version = 5;
            PRAGMA writable_schema = ON;
            UPDATE sqlite_master SET sql = replace(sql, '''undo_rows''', '''undo_rows'', ''merge_metadata''')
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
            _ = try await MarfaSource.open(connection, signIns: ScriptedSignIns(), location: MarfaStoreLocation(root: scratch()))
        }
    }

    private func open(_ root: URL, at address: String = "http://127.0.0.1:9") async throws -> MarfaSource {
        let connection = try MarfaConnection(address: address)
        return try await MarfaSource.open(
            connection, signIns: ScriptedSignIns([connection.address: "unused"]), location: MarfaStoreLocation(root: root))
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

        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST held", body: "Queued")), as: WriteID())
        await source.queueSubmitted()
        #expect(!server.released, "the write waited for the refresh")
        #expect(try await copy.queue.all().count == 1)
        #expect(await log.wait { $0.item(titled: "MARFAMACTEST held") != nil } != nil)
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

    /// The package's own sentence for a busy store names the store, not what the person can do about it.
    @Test func aStoreAnotherProgramHoldsIsToldAsInUse() {
        let busy = MarfaSource.failure(opening: .storeBusy(message: "database is locked"))
        #expect(busy == SourceFailure(kind: .inUse, message: Words.inUse))
        #expect(MarfaSource.failure(opening: .readingHandle(message: "reader")) == busy)
        #expect(MarfaSource.failure(opening: .storageFull(message: "full")).kind == .failed)
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
    @Test @MainActor
    func aCreateIsKeptWhateverBecomesOfItsParentLink() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.isLoaded })
        let write = WriteID()
        let child = ItemID.mint()
        source.submit(
            .create(id: child, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST child", body: "Queued", parent: ItemID("not-an-item"))),
            as: write)
        let told = await eventually {
            library.notices.waiting.contains {
                $0.title == "Can’t Put Item Under Its Parent" && $0.message.contains("couldn’t be put under its parent")
            }
        }
        #expect(told, "told: \(library.notices.waiting.map(\.message))")
        #expect(library.item(child)?.title == "MARFAMACTEST child")
        // The create waits for the server, neither answered nor refused by the link that failed beside it. The source
        // tells a write it queued taken once the link was tried, and answers one it refused in its place.
        await source.queueSubmitted()
        let settled = try #require(await log.wait { $0.changes.contains(.taken(write)) || $0.answer(to: write) != nil })
        #expect(settled.answer(to: write) == nil)
        let creates = try await source.copy.queue.all().filter { $0.kind == .createItem }
        #expect(creates.map(\.itemId) == [child.rawValue])
        #expect(creates.first?.verdict == nil)
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
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST kept", body: "Queued")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MARFAMACTEST kept") != nil })

        await source.copy.close()
        await source.hear(Change(origin: .refreshed(.caughtUp), itemId: nil, edgeId: nil))
        let failed = try #require(await log.wait { state in
            state.changes.contains { if case .unavailable = $0 { true } else { false } }
        })
        #expect(failed.item(titled: "MARFAMACTEST kept")?.sync == .waiting(writes: 1))
        await source.close()
    }

    /// The package takes properties as values: a text edit names the body alone, which the server merges, and a
    /// property taken away is named alone in `clear_properties`. Both are read back from the queue.
    @Test
    func aTextEditMergesTheBodyAndAPropertyTakenAwayIsNamedAlone() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let id = ItemID.mint()
        let draft = ItemDraft(
            type: TypeID("core.note"), title: "MARFAMACTEST edits", body: "First", properties: ["description": .string("Kept")])
        source.submit(.create(id: id, draft), as: WriteID())
        let made = try #require(await log.wait { $0.item(titled: "MARFAMACTEST edits") != nil })
        let version = try #require(made.item(titled: "MARFAMACTEST edits")?.version)

        source.submit(.editBody(id, "Second", base: version, merge: .ifUnchanged), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MARFAMACTEST edits")?.sync == .waiting(writes: 2) })
        let merge = try #require(try await source.copy.queue.all().last { $0.kind == .updateItem })
        #expect(merge.body["properties"]?.object == ["body": "Second"], "only the text is named, so the server merges it")
        #expect(merge.body["properties_mode"] == nil)

        source.submit(.editProperties(id, ["description": nil], base: version), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MARFAMACTEST edits")?.sync == .waiting(writes: 3) })
        let clearing = try #require(try await source.copy.queue.all().last { $0.kind == .updateItem })
        #expect(clearing.body["properties_mode"] == nil, "nothing is replaced: the edit names only what it clears")
        #expect(clearing.body["properties"]?.object?.isEmpty ?? true, "and sends no value it does not change")
        #expect(clearing.body["clear_properties"]?.array?.compactMap(\.string) == ["description"])
        let held = try #require(try await source.copy.items.get(id.rawValue))
        #expect(held.properties["description"] == nil, "the property taken away is gone")
        #expect(held.properties["body"]?.string == "Second" && held.properties["title"]?.string == "MARFAMACTEST edits", "every other keeps its value")
        await source.close()
    }

    /// A row the copy could not read is replaced only by a hydration, which the sync asks for once for each row.
    @Test
    func aRowTheCopyCouldNotReadIsHydratedForOnceAtMost() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let server = CountingRefresh()
        let source = MarfaSource(copy: copy, connection: SampleLibrary.connection, refreshing: server)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let sync = await source.engine.sync
        #expect(server.hydrations == 0)

        await sync.unreadable(["a"])
        #expect(try await eventuallyAsking { server.hydrations > 0 })
        #expect(server.hydrations == 1)

        // The same row again, as a read after the hydration finds it still unreadable, asks for nothing.
        await sync.unreadable(["a"])
        // Time for a second hydration, which nothing signals when none is asked for.
        try await Task.sleep(for: .milliseconds(500))
        #expect(server.hydrations == 1)
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

    /// The package reports a copy that expired as one that needs a hydration, and the sync hydrates it.
    @Test
    func anExpiredCopyIsHydratedAgain() async throws {
        let server = CountingRefresh()
        let (fake, source, _) = try await scriptedSource(refreshing: server)
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired", server: nil)
        fake.sendUpdate(CopyUpdate(reread: .everything, connection: .needsHydration(expired)))
        #expect(try await eventuallyAsking { server.hydrations == 1 })
        await source.close()
    }

    private static let note = TypeID("core.note")

    /// Makes a parent and a child under it, queued in a copy no server answers, and waits until the child shows it.
    private func parentAndChild(
        _ source: MarfaSource, _ log: ChangeLog, _ names: String...
    ) async throws -> [ItemID] {
        let ids = names.map { _ in ItemID.mint() }
        for (id, name) in zip(ids, names).dropLast() {
            source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MARFAMACTEST \(name)", body: "Queued")), as: WriteID())
        }
        let (child, name) = (try #require(ids.last), try #require(names.last))
        source.submit(
            .create(id: child, ItemDraft(type: Self.note, title: "MARFAMACTEST \(name)", body: "Queued", parent: ids[0])), as: WriteID())
        _ = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.to == .item(ids[0]) } == true
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
        source.submit(.moveEdge(EdgeID(edge.id), end: .from, to: second, from: first), as: write)
        let moved = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.to == .item(second) } == true
        })
        let held = try #require(moved.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(!held.contains { $0.to == .item(first) })
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
            source.submit(.moveEdge(EdgeID(edge.id), end: .from, to: parent, from: parent == second ? first : second), as: WriteID())
            let shown = await log.wait { state in
                state.snapshot?.items.first { $0.id == child }?.edgesOut.map(\.to) == [.item(parent)]
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
        source.submit(.link(EdgeDraft(type: "references", from: parent, to: other)), as: WriteID())
        let references = try #require(await Self.edge(of: "references", from: parent, in: source))
        let parentOf = try #require(await Self.edge(of: MarfaMapping.parentEdge, from: parent, in: source))

        // A type whose end that stays can hold many has no end to replace.
        let notReplaceable = WriteID()
        source.submit(.moveEdge(EdgeID(references.id), end: .to, to: child, from: other), as: notReplaceable)
        // A move that would leave the edge running from an item to itself.
        let selfLoop = WriteID()
        source.submit(.moveEdge(EdgeID(parentOf.id), end: .from, to: child, from: parent), as: selfLoop)
        let answered = try #require(await log.wait { $0.answer(to: notReplaceable) != nil && $0.answer(to: selfLoop) != nil })
        var validation = try #require(MarfaEngine.moveProblem(.validation(code: "validation_error", message: "", details: nil, server: nil)))
        var cycle = try #require(MarfaEngine.moveProblem(.validation(code: "edge_cycle", message: "", details: nil, server: nil)))
        // Refused before anything was queued.
        validation.notQueued = true
        cycle.notQueued = true
        #expect(answered.answer(to: notReplaceable) == .refused(validation))
        #expect(answered.answer(to: selfLoop) == .refused(cycle))
        #expect(try await source.copy.queue.all().filter { $0.kind == .updateEdge }.isEmpty)
        // Both links are where they were.
        let held = try #require(answered.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(held.contains { $0.to == .item(parent) })
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
        source.submit(.moveEdge(EdgeID(edge.id), end: .from, to: parent, from: parent), as: write)
        let answered = try #require(await log.wait { $0.answer(to: write) != nil })
        #expect(answered.answer(to: write) == .accepted)
        #expect(try await source.copy.queue.all().map(\.id) == before.map(\.id))
        let held = try #require(answered.snapshot?.items.first { $0.id == child }?.edgesOut)
        #expect(held.contains { $0.to == .item(parent) })
        await source.close()
    }

    /// An answer to a write of the item, as the server sends it: the item at `version`, holding `body` in `field`. The
    /// write carried `sent` in that field, or no text where `sent` is nil.
    private static func answered(
        _ id: String, _ verdict: Marfa.Verdict? = nil, kind: Marfa.WriteKind = .updateItem, carrying sent: String? = nil,
        made version: Int64? = nil, holding body: String? = nil, in field: String = "body"
    ) -> Marfa.QueuedWrite {
        let properties: JSONObject = body.map { [field: .string($0)] } ?? [:]
        return Marfa.QueuedWrite(
            id: id, kind: kind, itemId: "item", idempotencyKey: id, verdict: verdict,
            body: sent.map { ["properties": .object([field: .string($0)])] } ?? [:],
            answer: version.map {
                .object(["item": .object(["version": .integer($0), "type": .string("core.note"), "properties": .object(properties)])])
            },
            queuedAt: "2026-10-06T00:00:00Z")
    }

    /// The version the person's text, last saved as `text` on `on`, follows once `queue`'s answers are counted against
    /// a copy holding `held`.
    private static func following(
        _ queue: [Marfa.QueuedWrite], text: String = "Mine", on: Int64 = 3, held: Int64, counted: inout Set<String>
    ) async -> Int64 {
        await MarfaEngine.counting(
            queue, for: ItemID("item"), own: MarfaEngine.OwnText(text: text, field: "body", on: on), counted: &counted,
            held: { held }
        ).on
    }

    private static func following(
        _ queue: [Marfa.QueuedWrite], text: String = "Mine", on: Int64 = 3, held: Int64
    ) async -> Int64 {
        var counted: Set<String> = []
        return await following(queue, text: text, on: on, held: held, counted: &counted)
    }

    /// An answer moves the person's text on only once its effect is known. A version it proves needs the version the
    /// copy holds, which an expired copy cannot read, so it stays to be counted again; counted once, it moves the
    /// text no further.
    @Test func anAnswerIsCountedOnlyOnceTheVersionItNeedsIsRead() async throws {
        struct Unreadable: Error {}
        let queue = [Self.answered("merged", .merged(fields: ["title"]), made: 7, holding: "Mine"), Self.answered("taken", .accepted)]
        var counted: Set<String> = []
        await #expect(throws: Unreadable.self) {
            _ = try await MarfaEngine.counting(
                queue, for: ItemID("item"), own: MarfaEngine.OwnText(text: "Mine", field: "body", on: 3),
                counted: &counted, held: { throw Unreadable() })
        }
        #expect(counted.isEmpty)
        #expect(await Self.following(queue, held: 12, counted: &counted) == 7)
        #expect(counted == ["merged", "taken"])
        #expect(await Self.following(queue, on: 7, held: 12, counted: &counted) == 7)
        // A refused or conflicted write left the server's text, so its answer is counted and moves nothing.
        #expect(await Self.following([Self.answered("conflicted", .conflicted(siblingId: "copy", fields: ["body"]), made: 8, holding: "Mine")], held: 12) == 3)
    }

    /// A write that did not carry the text, such as a title change, is answered with whatever text the server held,
    /// which can be another device's. Only an answer holding the person's own text moves it on.
    @Test func aSaveFollowsOnlyAnAnswerHoldingThePersonsText() async throws {
        // Saved at version 2; another device wrote the text at 3; the title change was answered at 4 with theirs.
        let save = Self.answered("save", .accepted, carrying: "Mine", made: 2, holding: "Mine")
        let title = Self.answered("title", .merged(fields: ["title"]), made: 4, holding: "Theirs")
        #expect(await Self.following([save, title], on: 1, held: 4) == 2)
        #expect(await Self.following([title, save], on: 1, held: 4) == 2)
        // The version an answer holding the person's text names is followed, whichever write it answers.
        let titleOverMine = Self.answered("title", .accepted, made: 4, holding: "Mine")
        #expect(await Self.following([save, titleOverMine], on: 1, held: 4) == 4)
        // The person's text in another property proves nothing of the one the text is in.
        let elsewhere = Self.answered("save", .accepted, carrying: "Mine", made: 4, holding: "Mine", in: "summary")
        #expect(await Self.following([elsewhere], on: 1, held: 4) == 1)
        // A merge that changed the text leaves it where it was, so the next save is merged too.
        #expect(await Self.following([Self.answered("save", .merged(fields: ["body"]), carrying: "Mine", made: 5, holding: "Mine, theirs")], held: 5) == 3)
    }

    /// The person's own create made version 1, whatever version the item has reached when the answer comes, as for
    /// a create whose answer was lost and that is answered as a repeat after another device wrote.
    @Test func aCreateIsCountedAtTheVersionItMade() async throws {
        let create = Self.answered("create", .accepted, kind: .createItem, made: 2, holding: "Theirs")
        #expect(await Self.following([create], on: 0, held: 2) == 1)
        #expect(MarfaEngine.version(read: 1, holding: 2) == 1)
        #expect(await Self.following([Self.answered("create", .accepted, kind: .createItem)], on: 0, held: 1) == 1)
        let save = Self.answered("save", .accepted, carrying: "Mine", made: 3, holding: "Mine")
        #expect(await Self.following([save, create], on: 0, held: 3) == 3)
        #expect(await Self.following([create, save], on: 0, held: 3) == 3)
    }

    /// An answer that names no version proves no version holds the person's text, so the text stays where it was,
    /// whatever order the answers are read in.
    @Test func anAnswerWithNoVersionLeavesTheTextWhereItWas() async throws {
        let named = Self.answered("named", .accepted, made: 7, holding: "Mine")
        let plain = Self.answered("plain", .accepted)
        #expect(await Self.following([named, plain], held: 9) == 7)
        #expect(await Self.following([plain, named], held: 9) == 7)
        #expect(await Self.following([plain], held: 9) == 3)
        #expect(await Self.following([Self.answered("merged", .merged(fields: ["body"]))], held: 9) == 3)
    }

    /// The copy can record an answer before it reads the item back. An answer at a version the copy does not hold yet
    /// waits uncounted, the text staying where it was, and moves it once the copy holds that version.
    @Test func anAnswerAheadOfTheCopyWaitsForTheReadBack() async throws {
        let queue = [Self.answered("save", .accepted, carrying: "Mine", made: 7, holding: "Mine")]
        var counted: Set<String> = []
        #expect(await Self.following(queue, held: 6, counted: &counted) == 3)
        #expect(counted.isEmpty)
        #expect(await Self.following(queue, held: 7, counted: &counted) == 7)
        #expect(counted == ["save"])
    }

    /// On a slow link, saves the cap sends go out before the ones ahead are answered. Each answer holding the text its
    /// own write carried is a version of the person's text, so the next save follows the latest, never the version
    /// they all started from, where the server would set the person's text against itself.
    @Test func aSaveFollowsTheLatestOfTheEarlierSavesAnswered() async throws {
        let first = Self.answered("A", .accepted, carrying: "A", made: 2, holding: "A")
        let second = Self.answered("AB", .accepted, carrying: "AB", made: 3, holding: "AB")
        let third = Self.answered("ABC", carrying: "ABC")
        #expect(await Self.following([first, second, third], text: "ABC", on: 1, held: 3) == 3)
        #expect(await Self.following([third, second, first], text: "ABC", on: 1, held: 3) == 3)
        #expect(await Self.following([first, third], text: "ABC", on: 1, held: 2) == 2)
    }

    /// Another device restores the text the person started from between two of their saves, and the second conflicts.
    /// The next save follows the first save's answer, so the server sees the restore and the person's text both
    /// change it and keeps both. On the version they all started from, the restore would match it, and the person's
    /// text would replace the restore.
    @Test func aSaveAfterAConflictedOneFollowsTheLastAnswerHoldingTheText() async throws {
        let first = Self.answered("A", .accepted, carrying: "A", made: 2, holding: "A")
        let second = Self.answered("AB", .conflicted(siblingId: "copy", fields: ["body"]), carrying: "AB", made: 3, holding: "Base")
        #expect(await Self.following([first, second], text: "AB", on: 1, held: 3) == 2)
        #expect(await Self.following([second, first], text: "AB", on: 1, held: 3) == 2)
    }

    /// The server keeps text byte for byte, so two spellings of one character Swift calls equal are different text,
    /// and an answer holding the other spelling proves nothing.
    @Test func anAnswerProvesTheTextOnlyByteForByte() async throws {
        let composed = "Caf\u{00E9}"
        let decomposed = "Cafe\u{0301}"
        try #require(composed == decomposed)
        let save = Self.answered("save", .accepted, carrying: composed, made: 4, holding: decomposed)
        #expect(await Self.following([save], text: composed, held: 4) == 3)
        let title = Self.answered("title", .accepted, made: 4, holding: decomposed)
        #expect(await Self.following([title], text: composed, held: 4) == 3)
        let same = Self.answered("save", .accepted, carrying: decomposed, made: 4, holding: decomposed)
        #expect(await Self.following([same], text: decomposed, held: 4) == 4)
    }

    /// A type change can carry text the app put together, such as the title as a first line, so its answer proves
    /// its version only where it holds the person's own text.
    @Test func aTypeChangeProvesOnlyThePersonsOwnText() async throws {
        var retype = Self.answered("retype", .accepted, carrying: "Item\n\nMine", made: 4, holding: "Item\n\nMine")
        retype.body["retype"] = .bool(true)
        #expect(await Self.following([retype], text: "Mine", held: 4) == 3)
        var kept = Self.answered("retype", .accepted, made: 4, holding: "Mine")
        kept.body["retype"] = .bool(true)
        #expect(await Self.following([kept], text: "Mine", held: 4) == 4)
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
        source.submit(.moveEdge(EdgeID(edge.id), end: .from, to: second, from: first), as: write)
        _ = try #require(await log.wait { state in
            state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.to == .item(second) } == true
        })
        let queued = try await source.copy.queue.all()
        let move = try #require(queued.first { $0.kind == .updateEdge })

        // The server's answer, as the queue records it before the drain throws.
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        try MarfaDrainAnswersTests.recordAccepted(move.id, at: MarfaStoreLocation(root: root).store(for: connection))
        await source.tellAnswers()
        _ = try #require(await log.wait { $0.answer(to: write) == .accepted })

        // Then the copy hydrates again, which this closed port refuses; the queue and the view are as they were. The
        // engine is told as the sync would tell it, since a copy with a store cannot be made to expire.
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired", server: nil)
        await source.tell(CopyUpdate(reread: .everything, connection: .needsHydration(expired)))
        await source.engineTook()
        let after = try await source.copy.queue.all()
        #expect(Set(after.map(\.id)) == Set(queued.filter { $0.id != move.id }.map(\.id)), "only the answered write left the queue")
        let shown = try #require(log.current.snapshot?.items.first { $0.id == child })
        #expect(shown.edgesOut.contains { $0.to == .item(second) })
        #expect(shown.sync != .settled)
        await source.close()
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
            source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MARFAMACTEST \(title)", body: "Queued")), as: WriteID())
        }
        source.submit(
            .create(id: copy, ItemDraft(
                type: Self.note, title: "MARFAMACTEST original (conflicted copy)", body: "Mine", tags: [MarfaProblems.conflictedCopyTag])),
            as: WriteID())
        // Tagged, but not yet linked: no original is known.
        _ = try #require(await log.wait { $0.snapshot?.items.first { $0.id == copy } != nil })
        #expect(log.current.snapshot?.items.first { $0.id == original }?.sync != .conflicted(sibling: copy, fields: []))
        source.submit(.link(EdgeDraft(type: "derived-from", from: copy, to: original)), as: WriteID())
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
            MarfaError.copyExpired(reason: "catchup_too_old", message: "the copy expired", server: nil)
        ] {
            #expect(MarfaEngine.problem(for: error) == SyncProblem(code: error.code(), message: MarfaEngine.notCurrent))
        }
        let other = MarfaError.validation(code: "invalid_properties", message: "body: Required field is missing", details: nil, server: nil)
        #expect(MarfaEngine.problem(for: other) == SyncProblem(code: "invalid_properties", message: other.message))
        // The package's own refusal names the server's code, as a drain's verdict would.
        let reserved = MarfaError.forbidden(code: "type_not_permitted", message: "system.folder is written only through its own operation", server: nil)
        #expect(MarfaEngine.problem(for: reserved).code == "type_not_permitted")
    }
}

extension LiveMarfaTests {
    /// Against the test instance, in the Live test plan. Every item it makes has a title starting `MARFAMACTEST ` and is purged when the test ends, passed or not, over HTTP with the key's
    /// `items.purge`, which reaches an item the copy never held or has let go of.
    @Suite(.serialized)
    struct MarfaSourceLiveTests {
        private static let note = TypeID("core.note")

        private func open(_ root: URL) async throws -> MarfaSource {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            return try await MarfaSource.open(
                connection, signIns: ScriptedSignIns([connection.address: try LiveMarfa.key()]),
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
            source.submit(.create(id: parent, ItemDraft(type: Self.note, title: "MARFAMACTEST parent \(token)", body: "Above.")), as: WriteID())
            source.submit(
                .create(id: child, ItemDraft(type: Self.note, title: "MARFAMACTEST child \(token)", body: "Below.", parent: parent)),
                as: WriteID())
            await source.flush()
            let filed = try #require(await log.wait { state in
                [parent, child].allSatisfy { id in state.snapshot?.items.first { $0.id == id }?.sync == .settled }
                    && state.snapshot?.items.first { $0.id == child }?.edgesOut.contains {
                        $0.type == "child-of" && $0.to == .item(parent)
                    } == true
            })
            let snapshot = try #require(filed.snapshot)
            // A library may hold untitled notes, so what is read back is the titles of the notes made here.
            #expect(snapshot.items.first { $0.id == parent }?.title == "MARFAMACTEST parent \(token)")
            #expect(snapshot.items.first { $0.id == child }?.title == "MARFAMACTEST child \(token)")
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
            // Read before the server can have answered, since a fast one follows within milliseconds.
            let atOpen = reopened.connectionState
            let again = ChangeLog(reopened)
            let repainted = try #require(await again.wait { $0.painted != nil })
            #expect(repainted.painted?.items.count == count)
            #expect(repainted.painted?.items.first { $0.id == child }?.edgesOut.contains { $0.to == .item(parent) } == true)
            #expect(atOpen != .online, "a copy is not online before the server has answered")
            await reopened.close()
        }

        @Test(.timeLimit(.minutes(2)))
        func favoritesEditsArchivesAndBinsItsOwnItem() async throws {
            try await withSource { source, log, made in
                let title = "MARFAMACTEST favorite \(UUID().uuidString.prefix(8))"
                let created = WriteID()
                let id = made.mint()
                source.submit(
                    .create(id: id, ItemDraft(type: Self.note, title: title, body: "Made by the app tests.", tags: ["marfamactest"])),
                    as: created)
                let answered = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
                #expect(answered.answer(to: created) == .accepted)
                let item = try #require(answered.item(titled: title))
                #expect(item.id == id)
                #expect(item.tags == ["marfamactest"])
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
                let favorite = try #require(state.item(titled: title))

                state = try await apply(.editBody(item.id, "Edited by the app tests.", base: favorite.version, merge: .ifUnchanged))
                #expect(try await source.body(of: item.id).text == "Edited by the app tests.")

                state = try await apply(.tag(item.id, ItemTag.favorite, on: false))
                #expect(state.item(titled: title)?.isFavorite == false)

                state = try await apply(.transition(item.id, .archived, from: .active))
                #expect(state.item(titled: title)?.state == .archived)
                state = try await apply(.transition(item.id, .active, from: .archived))
                #expect(state.item(titled: title)?.state == .active)

                // The tier moves as an edit, and the item stays in the one copy at its new tier.
                let current = try #require(state.item(titled: title))
                state = try await apply(.retier(item.id, .feed, base: current.version))
                #expect(state.item(titled: title)?.tier == .feed)
                state = try await apply(.retier(item.id, .library, base: try #require(state.item(titled: title)).version))
                #expect(state.item(titled: title)?.tier == .library)

                // The server keeps the bin once the delete is sent, and the item stays shown from it.
                let binned = WriteID()
                source.submit(.transition(item.id, .trashed, from: .active), as: binned)
                let inBin = try #require(await log.wait { $0.answer(to: binned) != nil && $0.item(titled: title)?.state == .trashed })
                #expect(inBin.answer(to: binned) == .accepted)
                #expect(try await source.body(of: item.id).text == "Edited by the app tests.")

                // Restoring an item the copy let go of is made by its id, and the item arrives once it is answered.
                state = try await apply(.restore(item.id))
                #expect(state.item(titled: title)?.state == .active)

                // Permanently Delete destroys an item in the bin, at the version shown, and takes it out of the copy.
                let again = WriteID()
                source.submit(.transition(item.id, .trashed, from: .active), as: again)
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
                source.submit(.create(id: captured, ItemDraft(type: Self.note, title: "MARFAMACTEST feed \(token)", tier: .feed)), as: WriteID())
                source.submit(.create(id: filed, ItemDraft(type: Self.note, title: "MARFAMACTEST library \(token)")), as: WriteID())
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
                let title = "MARFAMACTEST as read \(UUID().uuidString.prefix(8))"
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
                    store: otherRoot.appending(path: "other.sqlite"), server: try Server(url: address, key: key))
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
                source.submit(.transition(id, .trashed, from: .active), as: WriteID())
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
            let keys = ScriptedSignIns([connection.address: key])
            let a = made.mint(), b = made.mint()
            let tag = UUID().uuidString.prefix(8)

            var source = try await MarfaSource.open(connection, signIns: keys, location: location)
            var log = ChangeLog(source)
            try await hydrated(source)
            source.submit(.create(id: a, ItemDraft(type: Self.note, title: "MARFAMACTEST earlier A \(tag)", body: "One")), as: WriteID())
            source.submit(.create(id: b, ItemDraft(type: Self.note, title: "MARFAMACTEST earlier B \(tag)", body: "One")), as: WriteID())
            let both = try #require(await log.wait { state in
                [a, b].allSatisfy { id in state.snapshot?.items.first { $0.id == id }?.sync == .settled }
            })
            let version = try #require(both.snapshot?.items.first { $0.id == a }?.version)
            await source.close()

            let otherRoot = scratch()
            defer { try? FileManager.default.removeItem(at: otherRoot) }
            try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
            let other = try await WorkingCopy.open(store: otherRoot.appending(path: "other.sqlite"), server: try connection.server(key: key))
            _ = try await other.hydrate(types: ["core.*"], tier: .library)
            let row = try #require(try await other.items.get(a.rawValue))
            _ = try await other.items.update(a.rawValue, Edit(properties: ["body": .string("Another device")], baseVersion: row.version))
            _ = try await other.queue.drain()
            await other.close()

            // The app's own store, edited from the version it holds, drained, and closed before it forgot the answer.
            let raw = try await WorkingCopy.open(store: location.store(for: connection), server: try connection.server(key: key))
            _ = try await raw.items.update(a.rawValue, Edit(properties: ["body": .string("This device")], baseVersion: version.rawValue))
            let report = try await raw.queue.drain()
            let sibling = report.verdicts.compactMap { answer -> String? in
                if case .conflicted(let sibling?, _, _)? = answer.verdict { sibling } else { nil }
            }.first
            if let sibling { made.add(ItemID(sibling)) }
            await raw.close()
            _ = try #require(sibling)

            source = try await MarfaSource.open(connection, signIns: keys, location: location)
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
            let relaunched = try await MarfaSource.open(connection, signIns: keys, location: location)
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
                let title = "MARFAMACTEST drains \(UUID().uuidString.prefix(8))"
                let id = made.mint()
                let created = WriteID()
                source.submit(.create(id: id, ItemDraft(type: Self.note, title: title, body: "One")), as: created)
                _ = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })

                let holding = LiveMarfa.Flag()
                source.engine.hooks.answering.set {
                    holding.set()
                    // Holds the answers for longer than the check below waits, as a slow engine would.
                    try? await Task.sleep(for: .seconds(2))
                }
                let before = await source.engine.sync.hooks.drains
                let tagged = WriteID()
                source.submit(.tag(id, ItemTag.favorite, on: true), as: tagged)
                #expect(await LiveMarfa.until { holding.isSet })
                await source.engine.sync.drain()
                // Time for a second drain, which nothing signals when none is sent. It is shorter than the hold above,
                // so the answers are still held and the count must not have moved.
                try await Task.sleep(for: .milliseconds(800))
                #expect(await source.engine.sync.hooks.drains == before + 1)
                source.engine.hooks.answering.set(nil)
                _ = try #require(await log.wait { $0.answer(to: tagged) != nil })
                #expect(await LiveMarfa.until { await source.engine.sync.hooks.drains == before + 2 })
                source.submit(.transition(id, .trashed, from: .active), as: WriteID())
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
                    source.submit(.create(id: id, ItemDraft(type: Self.note, title: "MARFAMACTEST parent \(id.rawValue) \(token)", body: "One")), as: write)
                }
                source.submit(
                    .create(id: child, ItemDraft(type: Self.note, title: "MARFAMACTEST moved \(token)", body: "One", parent: first)),
                    as: WriteID())
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == child }?.sync == .settled
                        && state.snapshot?.items.first { $0.id == child }?.edgesOut.contains { $0.to == .item(first) } == true
                })
                await source.flush()
                // A read while the copy fills again is refused as incomplete, so it is asked until it answers.
                var held: String?
                _ = await LiveMarfa.until {
                    held = (try? await source.copy.edges.from(first.rawValue))?.first { $0.edgeType == MarfaMapping.parentEdge }?.id
                    return held != nil
                }
                let edge = try #require(held)

                let move = WriteID(), tagged = WriteID()
                source.submit(.moveEdge(EdgeID(edge), end: .from, to: second, from: first), as: move)
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
                #expect(moved.edgesOut.contains { $0.to == .item(second) })
                #expect(!moved.edgesOut.contains { $0.to == .item(first) })
                #expect(moved.isFavorite)
                // The copy fills again after the move is answered, and a read made meanwhile is refused as incomplete.
                #expect(await LiveMarfa.until {
                    (try? await source.copy.edges.from(second.rawValue))?.contains { $0.toId == child.rawValue } == true
                })
                #expect(await LiveMarfa.until { (try? await source.copy.queue.all())?.isEmpty == true })
                #expect(await waitForConnection(source) { $0 == .online })
            }
        }

        /// A cycle through other edges is the server's to judge: it refuses the move, and the edge is where it was.
        @Test(.timeLimit(.minutes(2)))
        func aMoveThatClosesACycleIsRefusedAndTheEdgeStays() async throws {
            try await withSource { source, log, made in
                let token = UUID().uuidString.prefix(8)
                let a = made.mint(), b = made.mint(), c = made.mint()
                source.submit(.create(id: a, ItemDraft(type: Self.note, title: "MARFAMACTEST cycle a \(token)", body: "One")), as: WriteID())
                source.submit(.create(id: b, ItemDraft(type: Self.note, title: "MARFAMACTEST cycle b \(token)", body: "One", parent: a)), as: WriteID())
                source.submit(.create(id: c, ItemDraft(type: Self.note, title: "MARFAMACTEST cycle c \(token)", body: "One", parent: b)), as: WriteID())
                _ = try #require(await log.wait { state in
                    [b, c].allSatisfy { id in
                        state.snapshot?.items.first { $0.id == id }.map { $0.sync == .settled && !$0.edgesOut.isEmpty } == true
                    }
                })
                await source.flush()
                let edge = try #require(try await source.copy.edges.from(a.rawValue).first { $0.toId == b.rawValue })
                // `c` is below `b`, so it cannot become `b`'s parent.
                let move = WriteID()
                source.submit(.moveEdge(EdgeID(edge.id), end: .from, to: c, from: a), as: move)
                let refused = try #require(await log.wait { $0.answer(to: move) != nil })
                guard case .refused(let problem)? = refused.answer(to: move) else {
                    Issue.record("the move was answered \(String(describing: refused.answer(to: move)))")
                    return
                }
                #expect(problem.code == "edge_cycle")
                _ = try #require(await log.wait { state in
                    state.snapshot?.items.first { $0.id == b }?.edgesOut.contains { $0.to == .item(a) } == true
                })
                #expect(try await source.copy.edges.from(a.rawValue).contains { $0.toId == b.rawValue })
            }
        }

        /// The package refuses a create of a reserved type before queueing it, with the server's own code, so it is
        /// answered at once, nothing waits in the queue, and nothing reaches the server.
        @Test(.timeLimit(.minutes(2)))
        func aWriteThePackageRefusesIsAnsweredAtOnceAndNotQueued() async throws {
            try await withSource { source, log, made in
                let write = WriteID()
                let id = made.mint()
                source.submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: "MARFAMACTEST refused")), as: write)
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
/// in `MARFA_API_URL` and `MARFA_API_KEY`, with `MARFA_TEST_INSTANCE_ID` as the acknowledgement that the server is a test instance (see `LiveMarfa.address()`); without them each test fails rather than skips.
@Suite(.serialized, .tags(.live))
struct LiveMarfaTests {}

extension Tag {
    /// Tests that need the test instance: the Live test plan runs them and the Unit plan leaves them out.
    @Tag static var live: Self
}

nonisolated enum LiveMarfa {
    /// The test instance's address, from the Live test plan's environment. A run writes to this server, so the address
    /// is used only when `MARFA_TEST_INSTANCE_ID` holds the `instance_id` the server itself reports at its root
    /// (`GET /`). Reading that id from the server and typing it is the acknowledgement that this is a test instance,
    /// and an id left over from another server does not match.
    static func address() throws -> String {
        let address = try setting("MARFA_API_URL")
        try confirmedTestInstance.get()
        return address
    }

    /// Asked once a run, since the environment does not change during one and each ask can hold a thread for the
    /// request's whole timeout.
    private static let confirmedTestInstance = Result<Void, any Error> {
        let address = ProcessInfo.processInfo.environment["MARFA_API_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try refuseUnlessTestInstance(at: address, acknowledging: ProcessInfo.processInfo.environment["MARFA_TEST_INSTANCE_ID"])
    }

    struct NotATestInstance: Error, CustomStringConvertible {
        let description: String
    }

    static func refuseUnlessTestInstance(at address: String, acknowledging acknowledged: String?) throws {
        let given = acknowledged?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !given.isEmpty else {
            throw NotATestInstance(description: "Live and Measure runs write to the server at MARFA_API_URL. Set MARFA_TEST_INSTANCE_ID to the instance_id that \(address) reports at its root, to say it is a test instance and holds no one's data.")
        }
        guard let url = URL(string: address), let reported = reportedInstanceID(of: url) else {
            throw NotATestInstance(description: "The server at \(address) did not report an instance_id at its root, so it can not be confirmed as a test instance.")
        }
        guard reported == given else {
            throw NotATestInstance(description: "MARFA_TEST_INSTANCE_ID does not match the instance_id the server at \(address) reports, so this run will not write to it.")
        }
    }

    private static func reportedInstanceID(of address: URL) -> String? {
        var request = URLRequest(url: address, timeoutInterval: 10)
        request.httpMethod = "GET"
        let reply = Mutex<Data?>(nil)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            reply.withLock { $0 = data }
            done.signal()
        }.resume()
        done.wait()
        guard let data = reply.withLock({ $0 }), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["instance_id"] as? String
    }

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
    /// feed after its first rows, and a move of an edge's source or a retype hydrates it again, so a test that reads
    /// what the server holds, or writes a relationship, waits for this.
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
    private func open() async throws -> (MarfaSource, MarfaConnection, ScriptedSignIns, MarfaStoreLocation, URL) {
        let root = scratch()
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = ScriptedSignIns([connection.address: "unused"])
        let location = MarfaStoreLocation(root: root)
        let source = try await MarfaSource.open(connection, signIns: keys, location: location)
        return (source, connection, keys, location, root)
    }

    /// A write made the moment before quitting is in the queue once `queueSubmitted` returns, which never waits
    /// for the server, so it is there at the next launch.
    @Test
    func aWriteMadeJustBeforeQuittingIsKept() async throws {
        let (source, connection, keys, location, root) = try await open()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MARFAMACTEST quit", body: "Typed at once")), as: WriteID())
        await source.queueSubmitted()
        await source.close()

        let reopened = try await MarfaSource.open(connection, signIns: keys, location: location)
        let log = ChangeLog(reopened)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        let kept = try #require(painted.item(titled: "MARFAMACTEST quit"))
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
