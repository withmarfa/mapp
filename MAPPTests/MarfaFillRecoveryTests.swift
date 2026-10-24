import Foundation
import Marfa
import struct MarfaCore.Attachments
import struct MarfaCore.KeptFetch
import struct MarfaCore.Draft
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
    var attachmentCopy: WorkingCopy?
    private(set) var fetchedAttachments: [String] = []

    init(_ hydration: Hydration) {
        status = Status(sliceTypes: ["*"], sliceTier: .all, hydration: hydration)
    }

    func configure(interrupt: Bool = false, expire: Bool = false, restarted: String? = nil) {
        self.interrupt = interrupt
        self.expire = expire
        self.restarted = restarted
    }

    func readStatus() -> Status { status }
    func observeAttachments(in copy: WorkingCopy) { attachmentCopy = copy }
    func hydrate(types: [String], tier: SliceTier) throws -> HydrateReport {
        #expect(types == ["*"])
        #expect(tier == .all)
        calls.append("fill")
        let inPlace = status.hydration == .stale
        if interrupt {
            status.hydration = .inProgress
            resumed = true
            throw MarfaError.network(message: "interrupted")
        }
        status.hydration = .complete
        return HydrateReport(types: types, tier: tier, edgeTypes: [], items: 10, edges: 0,
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
        if let attachmentCopy {
            fetchedAttachments = try await attachmentCopy.edges.ofType(MarfaMapping.attachmentEdge).map(\.sourceId)
        }
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

@Suite struct MarfaFillRecoveryTests {
    private func withSync(_ server: FillServer, body: (MarfaSync) async throws -> Void) async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let sync = MarfaSync(copy: copy, hub: MarfaHub(), refreshing: server) { event in
            if case .fillProgress(let done) = event { done.resume() }
            return true
        }
        do {
            try await body(sync)
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
        let clock = ContinuousClock()
        let end = clock.now + .seconds(5)
        while !(await condition()), clock.now < end {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await condition())
    }

    @Test func fillsOnceThenCatchesUpAndFetchesAttachmentsAfterBoth() async throws {
        let server = FillServer(.never)
        try await withSync(server) { sync in
            try await sync.refreshNow()
            try await wait { await server.calls.count == 2 }
            try await sync.refreshNow()
            try await wait { await server.calls.count == 4 }
            #expect(await server.calls == ["fill", "attachments", "catchUp", "attachments"])
            #expect(await sync.hydrations == 1)
        }
    }

    @Test func anInterruptedFillResumesTheSameSlice() async throws {
        let server = FillServer(.never)
        try await withSync(server) { first in
            await server.configure(interrupt: true)
            await #expect(throws: MarfaError.self) { try await first.refreshNow() }
            #expect(await server.calls == ["fill"])
        }
        await server.configure()
        try await withSync(server) { reopened in
            try await reopened.refreshNow()
            try await wait { await server.calls.count == 3 }
            #expect(await reopened.lastHydration?.resumed == true)
            #expect(await reopened.lastHydration?.pagesTotal == 2)
            #expect(await server.calls == ["fill", "fill", "attachments"])
        }
    }

    @Test func agedOutCursorUsesStatusAndRefillsInPlace() async throws {
        let server = FillServer(.complete)
        try await withSync(server) { sync in
            await server.configure(expire: true)
            await #expect(throws: MarfaError.self) { try await sync.refreshNow() }
            try await sync.refreshNow()
            try await wait { await server.calls.count == 3 }
            #expect(await sync.lastHydration?.inPlace == true)
            #expect(await server.calls == ["catchUp", "fill", "attachments"])
        }
    }

    @Test func aRestartReportIsKeptWithoutAnotherFill() async throws {
        let server = FillServer(.inProgress)
        await server.configure(restarted: "head_aged_out")
        try await withSync(server) { sync in
            try await sync.refreshNow()
            #expect(await sync.lastHydration?.restarted == "head_aged_out")
            #expect(await sync.hydrations == 1)
        }
    }

    @Test func aFlushCompletesWhileAnAttachmentFetchIsHeld() async throws {
        let server = FillServer(.never)
        await server.holdFetch()
        try await withSync(server) { sync in
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
            #expect(await sync.drains > 0)
            #expect(await sync.lastKeptFetch == nil)
            #expect(await server.canceledFetches == 0)
            await sync.stop()
            try await wait { await server.canceledFetches == 1 }
        }
    }

    @Test func anIncompleteFetchIsKeptAndRetriedOnReconnectionWithoutAnotherDrain() async throws {
        let server = FillServer(.never)
        let incomplete = KeptFetch(fetched: 1, fetchedBytes: 10, attachments: Attachments(
            held: 1, heldBytes: 10, partialBytes: 3, notHeld: 1, notHeldBytes: 20, notHeldByReason: []))
        let complete = KeptFetch(fetched: 1, fetchedBytes: 20, attachments: Attachments(
            held: 2, heldBytes: 30, partialBytes: 0, notHeld: 0, notHeldBytes: 0, notHeldByReason: []))
        await server.report(incomplete)
        try await withSync(server) { sync in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { await sync.lastKeptFetch == incomplete }
            let drains = await sync.drains
            #expect(drains > 0)
            await sync.unreachable("offline")
            await server.report(complete)
            await server.holdFetch()
            await sync.reachable()
            try await wait { await server.calls.count == 3 }
            #expect(await sync.lastKeptFetch == incomplete)
            // The SDK reports its own reconnect drain while the attachment retry is still waiting.
            await sync.drainedByFollow(DrainReport(answered: 0, verdicts: []))
            await server.release()
            try await wait { await sync.lastKeptFetch == complete }
            #expect(await sync.drains == drains)
            #expect(await server.calls == ["fill", "attachments", "attachments"])
            #expect(await sync.hydrations == 1)
        }
    }

    @Test func aThrownFetchKeepsThePreviousReportAndRetriesOnReconnection() async throws {
        let server = FillServer(.never)
        let report = KeptFetch(fetched: 2, fetchedBytes: 30, attachments: nil)
        await server.report(report)
        try await withSync(server) { sync in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { await sync.lastKeptFetch == report }
            await server.report(report, error: .network(message: "offline"))
            await sync.reachable()
            try await wait { await server.calls.count == 3 }
            #expect(await sync.lastKeptFetch == report)
            await server.report(KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil))
            await sync.reachable()
            try await wait { await sync.lastKeptFetch?.fetched == 0 }
            #expect(await server.calls == ["fill", "attachments", "attachments", "attachments"])
        }
    }

    @Test func aReconnectDuringAFetchSchedulesOneMorePass() async throws {
        let server = FillServer(.never)
        await server.holdFetch()
        try await withSync(server) { sync in
            await sync.refresh()
            await sync.start()
            await sync.flush()
            try await wait { await server.calls.count == 2 }
            await sync.reachable()
            await sync.reachable()
            #expect(await server.calls.count == 2)
            await server.release()
            try await wait { await server.calls.count == 3 }
            #expect(await server.calls == ["fill", "attachments", "attachments"])
        }
    }

    @Test func anAttachmentArrivingThroughReplayIsFetchedWithoutAnotherDrain() async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let note = try await copy.items.create(Draft(type: "core.note", properties: ["title": "Held", "body": "Text"]))
        let noteID = try #require(note.itemId)
        let server = FillServer(.complete)
        await server.observeAttachments(in: copy)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "https://example.test"), refreshing: server)
        source.events.yield(.paint)
        await source.queueSubmitted()
        await source.engine.sync.refresh()
        await source.engine.sync.flush()
        try await wait { await server.calls.count == 2 }
        let drains = await source.engine.sync.drains

        let earlyFetch = KeptFetch(fetched: 0, fetchedBytes: 0, attachments: Attachments(
            held: 0, heldBytes: 0, partialBytes: 0, notHeld: 0, notHeldBytes: 0, notHeldByReason: []))
        await server.report(earlyFetch)
        source.events.yield(.change(Change(origin: .serverUnreachable(.network(message: "offline")), itemId: nil, edgeId: nil)))
        source.events.yield(.change(Change(origin: .serverReachable, itemId: nil, edgeId: nil)))
        await source.queueSubmitted()
        try await wait { await source.engine.sync.lastKeptFetch == earlyFetch }
        #expect(await server.fetchedAttachments.isEmpty)

        // The early retry has finished. Replay now adds a file and its relationship to the held note.
        let file = store.root.appending(path: "replayed.txt")
        try Data("From another device".utf8).write(to: file)
        let attached = try await copy.items.attach(to: noteID, file: file)
        let fileID = try #require(attached.item.itemId)
        let edgeID = try #require(attached.edge.edgeId)
        source.events.yield(.change(Change(origin: .server(event: "edge.created", cursor: "replayed"),
                                          itemId: nil, edgeId: edgeID)))
        await source.queueSubmitted()
        try await wait { await server.fetchedAttachments == [fileID] }
        #expect(await source.engine.sync.drains == drains)
        #expect(await server.calls == ["catchUp", "attachments", "attachments", "attachments"])
        await source.close()
    }
}
