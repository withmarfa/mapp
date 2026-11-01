import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MAPP

private actor FillServer: MarfaRefreshing {
    var status: Status
    var calls: [String] = []
    var interrupt = false
    var expire = false
    var resumed = false
    var restarted: String?

    init(_ hydration: Hydration) {
        status = Status(
            sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: hydration)
    }

    func configure(interrupt: Bool = false, expire: Bool = false, restarted: String? = nil) {
        self.interrupt = interrupt
        self.expire = expire
        self.restarted = restarted
    }

    func readStatus() -> Status { status }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) throws -> HydrateReport {
        #expect(types == MarfaSync.slice)
        #expect(tier == .all)
        #expect(edgeTypes == MarfaSync.sliceEdgeTypes)
        calls.append("fill")
        let inPlace = status.hydration == .stale
        if interrupt {
            status.hydration = .inProgress
            resumed = true
            throw MarfaError.network(message: "interrupted")
        }
        status.hydration = .complete
        return HydrateReport(types: types, tier: tier, edgeTypes: edgeTypes, items: 10, edges: 0,
                             pages: 1, pagesTotal: resumed ? 2 : 1, resumed: resumed && restarted == nil,
                             restarted: restarted, inPlace: inPlace, cursor: "done")
    }
    func catchUp() throws {
        calls.append("catchUp")
        if expire {
            status.hydration = .stale
            throw MarfaError.copyExpired(reason: "The event log no longer reaches this cursor", message: "expired")
        }
    }
    private var heldFetch: AsyncStream<Void>?
    private var releaseFetch: AsyncStream<Void>.Continuation?
    private(set) var canceledFetches = 0
    private var fetchReport = KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil)
    private var fetchError: MarfaError?

    func holdFetch() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        heldFetch = stream
        releaseFetch = continuation
    }

    func release() {
        releaseFetch?.finish()
        releaseFetch = nil
        heldFetch = nil
    }

    func report(_ report: KeptFetch, error: MarfaError? = nil) {
        fetchReport = report
        fetchError = error
    }

    func fetchKept() async throws -> KeptFetch {
        calls.append("attachments")
        if let heldFetch {
            for await _ in heldFetch { }
        }
        if Task.isCancelled {
            canceledFetches += 1
            throw CancellationError()
        }
        if let fetchError { throw fetchError }
        return fetchReport
    }
}

@Suite(.hangLimit) struct MarfaFillRecoveryTests {
    /// How many updates the engine was told, which says how many the sync has taken.
    private final class Told: Sendable {
        let count = Mutex(0)
    }

    private func withSync(_ server: FillServer, body: (MarfaSync, FakeCopy, Told) async throws -> Void) async throws {
        let fake = WorkingCopy.fake()
        let copy = fake.copy
        let told = Told()
        let sync = MarfaSync(copy: copy, hub: MarfaHub(), refreshing: server) { event in
            switch event {
            case .update(_, let done):
                told.count.withLock { $0 += 1 }
                done.resume()
            case .answers(let done): done.resume()
            default: break
            }
            return true
        }
        do {
            try await body(sync, fake, told)
        } catch {
            await sync.stop()
            await server.release()
            await copy.close()
            throw error
        }
        await sync.stop()
        await server.release()
        await copy.close()
    }

    private func wait(until condition: () async -> Bool) async throws {
        try #require(try await eventuallyAsking(condition))
    }

    @Test func fillsOnceThenCatchesUpAndFetchesAttachmentsAfterBoth() async throws {
        let server = FillServer(.never)
        try await withSync(server) { sync, _, _ in
            try await sync.refreshNow()
            try await wait { await server.calls.count == 2 }
            try await sync.refreshNow()
            try await wait { await server.calls.count == 4 }
            #expect(await server.calls == ["fill", "attachments", "catchUp", "attachments"])
            #expect(sync.hooks.hydrations == 1)
        }
    }

    @Test func anInterruptedFillResumesTheSameSlice() async throws {
        let server = FillServer(.never)
        try await withSync(server) { first, _, _ in
            await server.configure(interrupt: true)
            await #expect(throws: MarfaError.self) { try await first.refreshNow() }
            #expect(await server.calls == ["fill"])
        }
        await server.configure()
        try await withSync(server) { reopened, _, _ in
            try await reopened.refreshNow()
            try await wait { await server.calls.count == 3 }
            #expect(reopened.hooks.lastHydration?.resumed == true)
            #expect(reopened.hooks.lastHydration?.pagesTotal == 2)
            #expect(await server.calls == ["fill", "fill", "attachments"])
        }
    }

    @Test func agedOutCursorUsesStatusAndRefillsInPlace() async throws {
        let server = FillServer(.complete)
        try await withSync(server) { sync, _, _ in
            await server.configure(expire: true)
            await #expect(throws: MarfaError.self) { try await sync.refreshNow() }
            try await sync.refreshNow()
            try await wait { await server.calls.count == 3 }
            #expect(sync.hooks.lastHydration?.inPlace == true)
            #expect(await server.calls == ["catchUp", "fill", "attachments"])
        }
    }

    @Test func aRestartReportIsKeptWithoutAnotherFill() async throws {
        let server = FillServer(.inProgress)
        await server.configure(restarted: "head_aged_out")
        try await withSync(server) { sync, _, _ in
            try await sync.refreshNow()
            #expect(sync.hooks.lastHydration?.restarted == "head_aged_out")
            #expect(sync.hooks.hydrations == 1)
        }
    }

    @Test func aFlushCompletesWhileAnAttachmentFetchIsHeld() async throws {
        let server = FillServer(.never)
        await server.holdFetch()
        try await withSync(server) { sync, _, _ in
            await sync.refresh()
            await sync.start()
            try await wait { await server.calls.contains("attachments") }
            let flushed = Mutex(false)
            let flush = Task {
                await sync.flush()
                flushed.withLock { $0 = true }
            }
            defer { flush.cancel() }
            try await wait { flushed.withLock { $0 } }
            #expect(sync.hooks.drains > 0)
            #expect(sync.hooks.lastKeptFetch == nil)
            #expect(await server.canceledFetches == 0)
            await sync.stop()
            try await wait { await server.canceledFetches == 1 }
        }
    }

    /// The package reports the return of the server as a connection; MAPP sends what waited and asks again for the files.
    private func reconnect(_ fake: FakeCopy, _ told: Told) async throws {
        let target = told.count.withLock { $0 } + 2
        fake.sendUpdate(CopyUpdate(reread: .parts(Reread.Parts()), connection: .offline(.network(message: "offline"))))
        fake.sendUpdate(CopyUpdate(reread: .parts(Reread.Parts()), connection: .following))
        try await wait { told.count.withLock { $0 } >= target }
    }

    @Test func anIncompleteFetchIsKeptAndRetriedOnReconnectionWithoutAnotherDrain() async throws {
        let server = FillServer(.never)
        let incomplete = KeptFetch(fetched: 1, fetchedBytes: 10, attachments: KeptAttachments(
            held: 1, heldBytes: 10, partialBytes: 3, notHeld: 1, notHeldBytes: 20, notHeldByReason: []))
        let complete = KeptFetch(fetched: 1, fetchedBytes: 20, attachments: KeptAttachments(
            held: 2, heldBytes: 30, partialBytes: 0, notHeld: 0, notHeldBytes: 0, notHeldByReason: []))
        await server.report(incomplete)
        try await withSync(server) { sync, fake, told in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { sync.hooks.lastKeptFetch == incomplete }
            await server.report(complete)
            try await reconnect(fake, told)
            try await wait { sync.hooks.lastKeptFetch == complete }
            #expect(await server.calls == ["fill", "attachments", "attachments"])
        }
    }

    @Test func aThrownFetchKeepsThePreviousReportAndRetriesOnReconnection() async throws {
        let server = FillServer(.never)
        let report = KeptFetch(fetched: 2, fetchedBytes: 30, attachments: nil)
        await server.report(report)
        try await withSync(server) { sync, fake, told in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { sync.hooks.lastKeptFetch == report }
            await server.report(report, error: .network(message: "offline"))
            try await reconnect(fake, told)
            try await wait { await server.calls.count == 3 }
            #expect(sync.hooks.lastKeptFetch == report)
            await server.report(KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil))
            try await reconnect(fake, told)
            try await wait { sync.hooks.lastKeptFetch?.fetched == 0 }
            #expect(await server.calls == ["fill", "attachments", "attachments", "attachments"])
        }
    }

    @Test func aReconnectDuringAFetchSchedulesOneMorePass() async throws {
        let server = FillServer(.never)
        await server.holdFetch()
        try await withSync(server) { sync, fake, told in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { await server.calls.count == 2 }
            try await reconnect(fake, told)
            try await reconnect(fake, told)
            #expect(await server.calls.count == 2)
            await server.release()
            try await wait { await server.calls.count == 3 }
            #expect(await server.calls == ["fill", "attachments", "attachments"])
        }
    }

    @Test func anAttachmentArrivingThroughReplayIsFetchedWithoutAnotherDrain() async throws {
        let server = FillServer(.complete)
        try await withSync(server) { sync, fake, told in
            await sync.start()
            await sync.refresh()
            await sync.flush()
            try await wait { await server.calls.count == 2 }
            try await reconnect(fake, told)
            try await wait { await server.calls.count == 3 }
            await sync.flush()
            let drains = sync.hooks.drains

            // The early retry has finished. Replay now adds a file and its relationship to a held note.
            let target = told.count.withLock { $0 } + 1
            fake.sendUpdate(CopyUpdate(
                reread: .parts(Reread.Parts(rows: ChangedRows(edges: ["replayed"]))), connection: .following))
            try await wait { told.count.withLock { $0 } >= target }
            try await wait { await server.calls.count == 4 }
            #expect(sync.hooks.drains == drains)
            #expect(await server.calls == ["catchUp", "attachments", "attachments", "attachments"])
        }
    }
}
