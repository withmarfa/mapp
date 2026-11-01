import Marfa

/// The network steps of a refresh, separated so interruptions and recovery can be exercised without a server.
nonisolated protocol MarfaRefreshing: Sendable {
    func readStatus() async throws -> Status
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport
    func catchUp() async throws
    func fetchKept() async throws -> KeptFetch
    /// What the sync listens to in place of the copy's own updates, which a test sets to control exactly what the
    /// engine is told. `nil` listens to the copy.
    func updates() -> AsyncStream<CopyUpdate>?
}

nonisolated extension MarfaRefreshing {
    func updates() -> AsyncStream<CopyUpdate>? { nil }
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
