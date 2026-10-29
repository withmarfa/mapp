import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A pull that answers as the test says, and waits at the gate while it is held.
private nonisolated final class ScriptedPull: MarfaRefreshing {
    let failure = Mutex<MarfaError?>(nil)
    let phaseSeen = Mutex<SyncReport.Phase?>(nil)
    private let hub: MarfaHub
    private let held = Mutex(false)

    init(hub: MarfaHub) { self.hub = hub }

    func hold(_ on: Bool) { held.withLock { $0 = on } }

    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        throw MarfaError.network(message: "not used")
    }

    func catchUp() async throws {
        phaseSeen.withLock { $0 = hub.report.value.phase }
        while held.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        if let failure = failure.withLock({ $0 }) { throw failure }
    }

    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
}

/// What counts as a sync, and when the source says it happened.
@Suite(.hangLimit)
struct MarfaLastSyncedTests {
    private func withSync(body: (MarfaSync, MarfaHub, ScriptedPull) async throws -> Void) async throws {
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        let hub = MarfaHub()
        let pull = ScriptedPull(hub: hub)
        let sync = MarfaSync(copy: copy, hub: hub, refreshing: pull) { _ in true }
        do {
            try await body(sync, hub, pull)
        } catch {
            await sync.stop()
            await copy.close()
            throw error
        }
        await sync.stop()
        await copy.close()
    }

    @Test func aPullThatFinishesIsASyncAndIsStampedOnce() async throws {
        try await withSync { sync, hub, _ in
            #expect(hub.report.value.lastSynced == nil)
            let before = Date.now
            try await sync.refreshNow()
            let stamped = try #require(hub.report.value.lastSynced)
            #expect(stamped >= before && stamped <= .now)
            #expect(hub.report.value.phase == .current)
        }
    }

    @Test func aPullThatFailsLeavesTheLastSyncAsItWas() async throws {
        try await withSync { sync, hub, pull in
            try await sync.refreshNow()
            let first = try #require(hub.report.value.lastSynced)
            pull.failure.withLock { $0 = .network(message: "unreachable") }
            await #expect(throws: MarfaError.self) { try await sync.refreshNow() }
            #expect(hub.report.value.lastSynced == first)
            #expect(hub.report.value.phase == .current, "a failed pull is not still under way")
        }
    }

    @Test func aCatchUpShowsAsUpdatingWhileItRuns() async throws {
        try await withSync { sync, hub, pull in
            pull.hold(true)
            let running = Task { try await sync.refreshNow() }
            #expect(await eventually { hub.report.value.phase == .updating })
            #expect(hub.report.value.lastSynced == nil, "not a sync until it finishes")
            pull.hold(false)
            try await running.value
            #expect(hub.report.value.phase == .current)
            #expect(hub.report.value.lastSynced != nil)
        }
    }

    @Test func aServerChangeBeforeAnySyncIsNotOne() async throws {
        try await withSync { sync, hub, _ in
            await sync.heard()
            #expect(hub.report.value.lastSynced == nil)
        }
    }

    @Test func aServerChangeSoonAfterASyncDoesNotRestampIt() async throws {
        try await withSync { sync, hub, _ in
            await sync.refresh()
            await sync.start()
            #expect(await eventually { hub.report.value.lastSynced != nil })
            let first = hub.report.value.lastSynced
            await sync.heard()
            #expect(hub.report.value.lastSynced == first)
        }
    }
}
