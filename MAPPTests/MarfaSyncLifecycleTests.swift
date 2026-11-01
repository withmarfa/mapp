import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A refresh that says what its status is, counts the hydrations and catch-ups it is asked for, and can hold a
/// hydration until the test lets it go, as a large library's first fill is held by the server. With a complete
/// status it also stands in for the refresh of a test copy that has no server to hydrate from.
nonisolated final class ScriptedRefresh: MarfaRefreshing {
    private struct State {
        var hydrations = 0
        var catchUps = 0
        var holding: Bool
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state: Mutex<State>
    let status: Status
    /// Whether the sync listens to the copy's own updates, in place of one quiet first update.
    let listensToCopy: Bool

    init(status: Status, holding: Bool = false, listensToCopy: Bool = false) {
        self.status = status
        self.listensToCopy = listensToCopy
        state = Mutex(State(holding: holding))
    }

    static func complete(slice: [String] = MarfaSync.slice) -> Status {
        Status(sliceTypes: slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    var hydrations: Int { state.withLock { $0.hydrations } }
    var catchUps: Int { state.withLock { $0.catchUps } }

    func letGo() {
        let waiting = state.withLock { state in
            state.holding = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for waiter in waiting { waiter.resume() }
    }

    func readStatus() async throws -> Status { status }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        state.withLock { $0.hydrations += 1 }
        await withCheckedContinuation { continuation in
            let resume = state.withLock { state in
                if !state.holding { return true }
                state.waiting.append(continuation)
                return false
            }
            if resume { continuation.resume() }
        }
        return HydrateReport(types: types, tier: tier, edgeTypes: edgeTypes, items: 0, edges: 0, pages: 1, pagesTotal: 1,
                             resumed: false, restarted: nil, inPlace: false, cursor: "done")
    }

    func catchUp() async throws { state.withLock { $0.catchUps += 1 } }
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
    func updates() -> AsyncStream<CopyUpdate>? { listensToCopy ? nil : quietUpdates() }
}

/// The copy's reads, counting how often its status is read.
private nonisolated final class StatusCounting: MarfaReading {
    private let read: MarfaRead
    private let counted = Mutex(0)

    init(copy: WorkingCopy) { read = MarfaRead(copy: copy) }

    var statusReads: Int { counted.withLock { $0 } }

    func status() async throws -> Status {
        counted.withLock { $0 += 1 }
        return try await read.status()
    }

    func items() async throws -> Rows<Marfa.Item> { try await read.items() }
    func items(_ ids: [String]) async throws -> Rows<Marfa.Item> { try await read.items(ids) }
    func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] { try await read.edges(ofTypes: types) }
    func edges(touching id: String) async throws -> [Marfa.Edge] { try await read.edges(touching: id) }
    func edges(_ ids: [String]) async throws -> [Marfa.Edge] { try await read.edges(ids) }
    func views() async throws -> Rows<LibraryView> { try await read.views() }
    func items(inView id: String) async throws -> [Marfa.Item] { try await read.items(inView: id) }
    func links(in ids: [String]) async throws -> [String: BodyLinks] { try await read.links(in: ids) }
    func links(in id: String) async throws -> BodyLinks { try await read.links(in: id) }
    func changes(since cursor: ChangeCursor?, most: Int) async throws -> CopyChanges {
        try await read.changes(since: cursor, most: most)
    }
}

/// How the sync follows the package's lifecycle: what it asks of the copy once, and what it tells once.
@Suite(.serialized, .hangLimit)
struct MarfaSyncLifecycleTests {
    private func open(
        _ refresh: ScriptedRefresh, reading: (any MarfaReading)? = nil, store: TemporaryMarfaCopy
    ) async throws -> (MarfaSource, ChangeLog) {
        let copy = try await store.open()
        let source = MarfaSource(
            copy: copy, connection: SampleLibrary.connection, reading: reading ?? MarfaRead(copy: copy), refreshing: refresh)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        return (source, log)
    }

    private func unavailable(_ state: ChangeLog.State) -> Int {
        state.changes.count { if case .unavailable = $0 { true } else { false } }
    }

    private func progress(_ listed: UInt64) -> CopyUpdate {
        CopyUpdate(reread: .parts(Reread.Parts()), connection: .needsHydration(nil), fill: FillProgress(listed: listed, expected: 5000))
    }

    // MARK: A hydration runs once

    @Test func progressUpdatesDuringAHydrationCauseExactlyOneHydration() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let refresh = ScriptedRefresh(status: Status(hydration: .never), holding: true)
        let (source, _) = try await open(refresh, store: store)
        let sync = await source.engine.sync

        await sync.take(progress(0))
        try #require(await eventually { refresh.hydrations == 1 })
        for listed in 1...4 { await sync.take(progress(UInt64(listed) * 500)) }
        refresh.letGo()
        // Time for a second fill, which nothing signals when none is asked for.
        try await Task.sleep(for: .milliseconds(400))
        #expect(refresh.hydrations == 1)
        await source.close()
    }

    @Test func aCopyThatNeedsHydrationAgainAfterFollowingHydratesAgain() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (source, _) = try await open(refresh, store: store)
        let sync = await source.engine.sync
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired")

        await sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .needsHydration(expired)))
        try #require(await eventually { refresh.hydrations == 1 })
        await sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .following))
        await sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .needsHydration(expired)))
        #expect(try await eventuallyAsking { refresh.hydrations == 2 })
        await source.close()
    }

    // MARK: Launch

    @Test func aCopyWhoseSliceThisBuildChangedIsFilledAtLaunch() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete(slice: ["*"]))
        let (source, _) = try await open(refresh, store: store)
        #expect(try await eventuallyAsking { refresh.hydrations == 1 })
        await source.close()
    }

    @Test func aCopyOfTheSliceThisBuildWantsIsNotFilledAtLaunch() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (source, _) = try await open(refresh, store: store)
        await source.engine.sync.drain()
        try await Task.sleep(for: .milliseconds(300))
        #expect(refresh.hydrations == 0)
        await source.close()
    }

    // MARK: Told once

    @Test func repeatedIdenticalStoppedUpdatesAreReportedAndToldOnce() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let (source, log) = try await open(ScriptedRefresh(status: ScriptedRefresh.complete()), store: store)
        let sync = await source.engine.sync
        let stopped = CopyUpdate(reread: .parts(Reread.Parts()), connection: .stopped(.store(message: "the store failed")))

        for _ in 0..<4 { await sync.take(stopped) }
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(sync.hooks.stops == 1)
        #expect(unavailable(log.current) == 1)

        // Following again and stopping again is a new stop.
        await sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .following))
        await sync.take(stopped)
        #expect(sync.hooks.stops == 2)
        await source.close()
    }

    @Test func aDrainThatFailsForAnUnclassifiedReasonIsToldOnceUntilADrainSucceeds() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        // A copy with a server that refuses every connection, so a drain the test does not fail ends without a fault.
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let copy = try await WorkingCopy.open(
            store: store.root.appending(path: "store.sqlite"), server: connection.server(key: "unused"))
        let source = MarfaSource(
            copy: copy, connection: connection, refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let sync = await source.engine.sync
        sync.hooks.faulting.set { step in step == .drain ? .store(message: "the store failed") : nil }

        await sync.flush()
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(sync.hooks.drains == 1)
        await sync.flush()
        await sync.flush()
        #expect(sync.hooks.drains == 3)
        #expect(unavailable(log.current) == 1, "a failing drain told again before one succeeds")

        // A drain that works clears it, so the next failure is told.
        sync.hooks.faulting.set(nil)
        await sync.flush()
        sync.hooks.faulting.set { step in step == .drain ? .store(message: "the store failed") : nil }
        await sync.flush()
        _ = try #require(await log.wait { unavailable($0) == 2 })
        await source.close()
    }

    @Test(arguments: [
        MarfaError.network(message: "offline"),
        MarfaError.server(status: 503, code: "unavailable", message: "The server is busy."),
        MarfaError.canceled(message: "the call was canceled"),
    ])
    func aDrainThePackageRetriesIsNotTold(_ error: MarfaError) async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let (source, log) = try await open(ScriptedRefresh(status: ScriptedRefresh.complete()), store: store)
        let sync = await source.engine.sync
        sync.hooks.faulting.set { step in step == .drain ? error : nil }
        await sync.flush()
        #expect(sync.hooks.drains == 1)
        #expect(unavailable(log.current) == 0)
        await source.close()
    }

    // MARK: The bin

    @Test func aBinReadTheServerRefusesAsInvalidIsToldButOneForAKeyChangeIsNot() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let (source, log) = try await open(ScriptedRefresh(status: ScriptedRefresh.complete()), store: store)
        let sync = await source.engine.sync

        sync.hooks.faulting.set { step in step == .bin ? .keyChanging(message: "The key is changing.") : nil }
        await sync.refresh()
        try #require(await eventually { sync.hooks.binReads == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(unavailable(log.current) == 0)

        sync.hooks.faulting.set { step in step == .bin ? .invalid(message: "The request is invalid.") : nil }
        await sync.refresh()
        _ = try #require(await log.wait { unavailable($0) == 1 })
        await source.close()
    }

    // MARK: Reading the status

    @Test func theCopysStatusIsReadAgainOnlyWhenAFillEndsOrTheConnectionChanges() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let reads = StatusCounting(copy: copy)
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let source = MarfaSource(copy: copy, connection: SampleLibrary.connection, reading: reads, refreshing: refresh)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let sync = await source.engine.sync
        func update(_ connection: CopyConnection, fill: FillProgress? = nil) -> CopyUpdate {
            CopyUpdate(reread: .parts(Reread.Parts(queue: true)), connection: connection, fill: fill)
        }

        await sync.take(update(.following))
        let afterConnecting = reads.statusReads
        for _ in 0..<5 { await sync.take(update(.following)) }
        #expect(reads.statusReads == afterConnecting, "a local write's update read the status")

        await sync.take(update(.following, fill: FillProgress(listed: 1, expected: 9)))
        await sync.take(update(.following))
        #expect(reads.statusReads == afterConnecting + 1, "the end of a fill did not read the status once")
        await source.close()
    }
}
