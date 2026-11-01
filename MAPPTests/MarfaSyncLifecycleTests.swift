import Foundation
import Marfa
import MarfaTesting
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
        var failure: MarfaError?
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state: Mutex<State>
    let status: Status

    init(status: Status, holding: Bool = false) {
        self.status = status
        state = Mutex(State(holding: holding))
    }

    static func complete(slice: [String] = MarfaSync.slice) -> Status {
        Status(sliceTypes: slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    var hydrations: Int { state.withLock { $0.hydrations } }
    var catchUps: Int { state.withLock { $0.catchUps } }

    /// Makes the next catch-ups and hydrations throw this error, or none.
    func fail(with error: MarfaError?) { state.withLock { $0.failure = error } }

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
        if let failure = state.withLock({ $0.failure }) { throw failure }
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

    func catchUp() async throws {
        state.withLock { $0.catchUps += 1 }
        if let failure = state.withLock({ $0.failure }) { throw failure }
    }
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
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

/// How the sync follows the package's lifecycle: what it asks of the copy once, and what it tells once. Each test
/// sends the updates the package would send through the fake copy's own stream.
@Suite(.serialized, .hangLimit)
struct MarfaSyncLifecycleTests {
    private func unavailable(_ state: ChangeLog.State) -> Int {
        state.changes.count { if case .unavailable = $0 { true } else { false } }
    }

    private func update(_ connection: CopyConnection, fill: FillProgress? = nil) -> CopyUpdate {
        CopyUpdate(reread: .parts(Reread.Parts()), connection: connection, fill: fill)
    }

    private func progress(_ listed: UInt64) -> CopyUpdate {
        update(.needsHydration(nil), fill: FillProgress(listed: listed, expected: 5000))
    }

    // MARK: A hydration runs once

    @Test func progressUpdatesDuringAHydrationCauseExactlyOneHydration() async throws {
        let refresh = ScriptedRefresh(status: Status(hydration: .never), holding: true)
        let (fake, source, _) = try await scriptedSource(refreshing: refresh)
        try #require(await eventually { refresh.hydrations == 1 }, "the fill the launch asks for")

        fake.sendUpdate(progress(0))
        for listed in 1...4 { fake.sendUpdate(progress(UInt64(listed) * 500)) }
        // The fill ends only after the sync has taken every progress update, as the package's does.
        try #require(await eventually { source.syncReport.fill?.listed == 2000 })
        refresh.letGo()
        // Time for a second fill, which nothing signals when none is asked for.
        try await Task.sleep(for: .milliseconds(400))
        #expect(refresh.hydrations == 1)
        await source.close()
    }

    @Test func aCopyThatNeedsHydrationAgainAfterFollowingHydratesAgain() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (fake, source, _) = try await scriptedSource(refreshing: refresh)
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired")

        fake.sendUpdate(update(.needsHydration(expired)))
        try #require(await eventually { refresh.hydrations == 1 })
        fake.sendUpdate(update(.following))
        fake.sendUpdate(update(.needsHydration(expired)))
        #expect(try await eventuallyAsking { refresh.hydrations == 2 })
        await source.close()
    }

    /// A hydration the app has started is catching up before the package reports its first page, as when it waits
    /// for a catch-up or another fill to end, so an Undo held meanwhile waits for it (`MarfaEngine.expire`).
    @Test func aHydrationIsCatchingUpBeforeThePackageReportsItsProgress() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete(), holding: true)
        let (fake, source, _) = try await scriptedSource(refreshing: refresh)
        let expired = MarfaError.copyExpired(reason: "reach_changed", message: "the copy expired")

        fake.sendUpdate(update(.needsHydration(expired)))
        try #require(await eventually { refresh.hydrations == 1 })
        #expect(await eventually { source.syncReport.phase == .catchingUp }, "\(source.syncReport.phase)")
        refresh.letGo()
        #expect(await eventually { source.syncReport.phase == .current }, "\(source.syncReport.phase)")
        await source.close()
    }

    /// The package reports following before the app's hydration call returns. A drain then would meet the copy
    /// changing under its pull (`streamIncomplete`, `local_copy_changed`) or not yet whole (`hydrationIncomplete`),
    /// shown as a stop or answered with a second hydration that empties the lists again, so it waits for the
    /// hydration and a flush returns after it.
    @Test func nothingIsSentWhileTheAppsHydrationIsUnderWay() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete(), holding: true)
        let (fake, source, log) = try await scriptedSource(refreshing: refresh)
        let sync = await source.engine.sync

        fake.sendUpdate(update(.needsHydration(nil)))
        try #require(await eventually { refresh.hydrations == 1 })
        fake.sendUpdate(update(.following))
        let flushed = TestTally(false)
        let flush = Task {
            await sync.flush()
            flushed.update { $0 = true }
        }
        // Long enough for the following update to be taken and a drain to start, were one allowed.
        try await Task.sleep(for: .milliseconds(300))
        #expect(sync.hooks.drains == 0)
        #expect(!flushed.current)

        refresh.letGo()
        await flush.value
        #expect(sync.hooks.drains >= 1)
        #expect(refresh.hydrations == 1)
        #expect(unavailable(log.current) == 0)
        await source.close()
    }

    /// A first fill that fails transiently shows the copy offline; when the package's wait ends it says the copy needs
    /// hydration again, which is a new turn, so the copy is hydrated again and is not shown following meanwhile.
    @Test func aFirstFillThatFailedTransientlyShowsOfflineAndHydratesAgainWhenAsked() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (fake, source, _) = try await scriptedSource(refreshing: refresh)

        fake.sendUpdate(update(.needsHydration(nil)))
        try #require(await eventually { refresh.hydrations == 1 })
        fake.sendUpdate(update(.offline(.network(message: "the network is down"))))
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })
        try await Task.sleep(for: .milliseconds(300))
        #expect(refresh.hydrations == 1, "nothing is asked again while the package waits")

        fake.sendUpdate(update(.needsHydration(nil)))
        #expect(try await eventuallyAsking { refresh.hydrations == 2 })
        #expect(source.connectionState != .online)
        await source.close()
    }

    /// The package waits for a person's Refresh after a fault in the first fill, rather than trying it again.
    @Test func aFirstFillThatFailedOnAFaultIsNotFilledAgainByItself() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (fake, source, _) = try await scriptedSource(refreshing: refresh)
        let refused = MarfaError.server(status: 400, code: "bad_request", message: "The server refused the fill.")

        fake.sendUpdate(update(.needsHydration(nil)))
        try #require(await eventually { refresh.hydrations == 1 })
        fake.sendUpdate(update(.needsHydration(refused)))
        fake.sendUpdate(update(.needsHydration(refused)))
        try await Task.sleep(for: .milliseconds(400))
        #expect(refresh.hydrations == 1)
        await source.close()
    }

    // MARK: Launch

    @Test func aCopyWhoseSliceThisBuildChangedIsFilledAtLaunch() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete(slice: ["*"]))
        let (_, source, _) = try await scriptedSource(refreshing: refresh)
        #expect(try await eventuallyAsking { refresh.hydrations == 1 })
        await source.close()
    }

    @Test func aCopyOfTheSliceThisBuildWantsIsNotFilledAtLaunch() async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        let (_, source, _) = try await scriptedSource(refreshing: refresh)
        await source.engine.sync.drain()
        try await Task.sleep(for: .milliseconds(300))
        #expect(refresh.hydrations == 0)
        await source.close()
    }

    // MARK: Told once

    @Test func repeatedIdenticalStoppedUpdatesAreReportedAndToldOnce() async throws {
        let (fake, source, log) = try await scriptedSource(refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        let sync = await source.engine.sync
        let stopped = update(.stopped(.store(message: "the store failed")))

        for _ in 0..<4 { fake.sendUpdate(stopped) }
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(sync.hooks.stops == 1)
        #expect(unavailable(log.current) == 1)

        // Following again and stopping again is a new stop.
        fake.sendUpdate(update(.following))
        fake.sendUpdate(stopped)
        #expect(try await eventuallyAsking { sync.hooks.stops == 2 })
        await source.close()
    }

    /// A fault the app's call met on a copy that has not hydrated is told the same way, once.
    @Test func aFaultOfTheFirstFillIsReportedAndToldOnceAsAStoppedLibraryIs() async throws {
        let (fake, source, log) = try await scriptedSource(refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        let sync = await source.engine.sync
        let fault = update(.needsHydration(.store(message: "the store failed")))

        for _ in 0..<4 { fake.sendUpdate(fault) }
        _ = try #require(await log.wait { unavailable($0) == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(sync.hooks.stops == 1)
        #expect(unavailable(log.current) == 1)
        await source.close()
    }

    @Test func aDrainThatFailsForAnUnclassifiedReasonIsToldOnceUntilADrainSucceeds() async throws {
        let (_, source, log) = try await scriptedSource(refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
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

    /// The package leaves the connection following when a drain fails on a fault, so the updates that follow must
    /// not show the library online while writes wait.
    @Test func aDrainFaultStaysShownThroughFollowingUpdatesUntilADrainSucceeds() async throws {
        let (fake, source, log) = try await scriptedSource(refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        let sync = await source.engine.sync
        sync.hooks.faulting.set { step in step == .drain ? .store(message: "the store failed") : nil }
        fake.sendUpdate(update(.following))
        try #require(await eventually { sync.hooks.drains >= 1 })
        await sync.flush()
        _ = try #require(await log.wait { unavailable($0) == 1 })
        let drains = sync.hooks.drains

        fake.sendUpdate(update(.following))
        fake.sendUpdate(update(.following))
        try await Task.sleep(for: .milliseconds(200))
        #expect(source.connectionState != .online, "a following update showed a library with queued writes online")
        #expect(unavailable(log.current) == 1)

        sync.hooks.faulting.set(nil)
        await sync.flush()
        #expect(sync.hooks.drains > drains)
        #expect(source.connectionState == .online)
        await source.close()
    }

    @Test(arguments: [
        MarfaError.unknownType(message: "No such type."),
        MarfaError.invalid(message: "The request is invalid."),
    ])
    func aRefreshRefusedForTheAppsOwnRequestIsShownUnavailableAndToldOnce(_ error: MarfaError) async throws {
        let refresh = ScriptedRefresh(status: ScriptedRefresh.complete())
        refresh.fail(with: error)
        let (_, source, log) = try await scriptedSource(refreshing: refresh)
        let sync = await source.engine.sync

        await sync.refresh()
        _ = try #require(await log.wait { unavailable($0) == 1 })
        await sync.refresh()
        try await Task.sleep(for: .milliseconds(200))
        #expect(unavailable(log.current) == 1)
        #expect(source.connectionState == .unavailable(message: error.message))
        await source.close()
    }

    @Test(arguments: [
        MarfaError.network(message: "offline"),
        MarfaError.server(status: 503, code: "unavailable", message: "The server is busy."),
        MarfaError.canceled(message: "the call was canceled"),
        MarfaError.keyChanging(message: "The key is changing."),
        MarfaError.copyExpired(reason: "read_view_changed", message: "The copy expired."),
    ])
    func aDrainThePackageRetriesOrAnswersIsNotTold(_ error: MarfaError) async throws {
        let (_, source, log) = try await scriptedSource(refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()))
        let sync = await source.engine.sync
        sync.hooks.faulting.set { step in step == .drain ? error : nil }
        await sync.flush()
        #expect(sync.hooks.drains == 1)
        #expect(unavailable(log.current) == 0)
        await source.close()
    }

    // MARK: Reading the status

    @Test func theCopysStatusIsReadAgainOnlyWhenAFillEndsOrTheConnectionChanges() async throws {
        let fake = WorkingCopy.fake()
        let reads = StatusCounting(copy: fake.copy)
        let (_, source, _) = try await scriptedSource(
            fake, refreshing: ScriptedRefresh(status: ScriptedRefresh.complete()), reading: reads)
        let sync = await source.engine.sync
        func update(_ connection: CopyConnection, fill: FillProgress? = nil) -> CopyUpdate {
            CopyUpdate(reread: .parts(Reread.Parts(queue: true)), connection: connection, fill: fill)
        }

        fake.sendUpdate(update(.following))
        // Following sends what waited, which is the first sign that the update has been taken.
        try #require(await eventually { sync.hooks.drains >= 1 })
        let afterConnecting = reads.statusReads
        for _ in 0..<5 { fake.sendUpdate(update(.following)) }

        fake.sendUpdate(update(.following, fill: FillProgress(listed: 1, expected: 9)))
        fake.sendUpdate(update(.following))
        try #require(await eventually { reads.statusReads > afterConnecting })
        try await Task.sleep(for: .milliseconds(300))
        #expect(reads.statusReads == afterConnecting + 1, "the end of a fill did not read the status once, or a local write's update did")
        await source.close()
    }
}
