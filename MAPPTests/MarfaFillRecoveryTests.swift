import Foundation
import Marfa
import MarfaTesting
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
        status = Status(sliceTypes: ["*"], sliceTier: .all, hydration: hydration)
    }

    func configure(interrupt: Bool = false, expire: Bool = false, restarted: String? = nil) {
        self.interrupt = interrupt
        self.expire = expire
        self.restarted = restarted
    }

    func readStatus() -> Status { status }
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
    func fetchKept() { calls.append("attachments") }
}

@Suite struct MarfaFillRecoveryTests {
    private func sync(_ server: FillServer) -> MarfaSync {
        MarfaSync(copy: WorkingCopy.fake().copy, hub: MarfaHub(), refreshing: server) { event in
            if case .fillProgress(let done) = event { done.resume() }
            return true
        }
    }

    @Test func fillsOnceThenCatchesUpAndFetchesAttachmentsAfterBoth() async throws {
        let server = FillServer(.never)
        let sync = sync(server)
        try await sync.refreshNow()
        try await sync.refreshNow()
        #expect(await server.calls == ["fill", "attachments", "catchUp", "attachments"])
        #expect(await sync.hydrations == 1)
    }

    @Test func anInterruptedFillResumesTheSameSlice() async throws {
        let server = FillServer(.never)
        let first = sync(server)
        await server.configure(interrupt: true)
        await #expect(throws: MarfaError.self) { try await first.refreshNow() }
        #expect(await server.calls == ["fill"])
        await server.configure()
        let reopened = sync(server)
        try await reopened.refreshNow()
        #expect(await reopened.lastHydration?.resumed == true)
        #expect(await reopened.lastHydration?.pagesTotal == 2)
        #expect(await server.calls == ["fill", "fill", "attachments"])
    }

    @Test func agedOutCursorUsesStatusAndRefillsInPlace() async throws {
        let server = FillServer(.complete)
        let sync = sync(server)
        await server.configure(expire: true)
        await #expect(throws: MarfaError.self) { try await sync.refreshNow() }
        try await sync.refreshNow()
        #expect(await sync.lastHydration?.inPlace == true)
        #expect(await server.calls == ["catchUp", "fill", "attachments"])
    }

    @Test func aRestartReportIsKeptWithoutAnotherFill() async throws {
        let server = FillServer(.inProgress)
        await server.configure(restarted: "head_aged_out")
        let sync = sync(server)
        try await sync.refreshNow()
        #expect(await sync.lastHydration?.restarted == "head_aged_out")
        #expect(await sync.hydrations == 1)
    }
}
