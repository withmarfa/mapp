import Marfa
import struct MarfaCore.KeptFetch

/// The network steps of a refresh, separated so interruptions and recovery can be exercised without a server.
nonisolated protocol MarfaRefreshing: Sendable {
    func readStatus() async throws -> Status
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport
    func catchUp() async throws
    func fetchKept() async throws -> KeptFetch
}

nonisolated struct MarfaRefresh: MarfaRefreshing {
    let copy: WorkingCopy

    func readStatus() async throws -> Status { try await copy.status() }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        try await copy.hydrate(types: types, tier: tier, edgeTypes: edgeTypes)
    }
    func catchUp() async throws { _ = try await copy.catchUp() }
    func fetchKept() async throws -> KeptFetch { try await copy.blobs.fetchKept() }
}
