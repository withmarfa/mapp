import Marfa

/// The network steps of a refresh, separated so interruptions and recovery can be exercised without a server.
nonisolated protocol MarfaRefreshing: Sendable {
    func readStatus() async throws -> Status
    func hydrate(types: [String], tier: SliceTier) async throws -> HydrateReport
    func catchUp() async throws
    func fetchKept() async throws
}

nonisolated struct MarfaRefresh: MarfaRefreshing {
    let copy: WorkingCopy

    func readStatus() async throws -> Status { try await copy.status() }
    func hydrate(types: [String], tier: SliceTier) async throws -> HydrateReport {
        try await copy.hydrate(types: types, tier: tier)
    }
    func catchUp() async throws { _ = try await copy.catchUp() }
    func fetchKept() async throws { _ = try await copy.blobs.fetchKept() }
}
