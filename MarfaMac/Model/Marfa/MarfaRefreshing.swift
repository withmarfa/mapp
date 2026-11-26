import Marfa

/// The network steps of a refresh, separated so interruptions and recovery can be exercised without a server.
nonisolated protocol MarfaRefreshing: Sendable {
    func readStatus() async throws -> Status
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport
    func catchUp() async throws
    func fetchKept() async throws -> KeptFetch
    /// Declares the app's own type, which a hydration registers where the server lacks it and the sign-in may.
    func declarePreferences() async throws
    /// Chooses the settings tables before hydration. On a hydrated copy, filling a newly chosen table can keep the
    /// follow from restarting (withmarfa/marfa#3606).
    func choosePreferencesTables() async
    /// Whether the server holds the app's own type and what the sign-in's scopes are; nil where either cannot be read.
    func preferencesEvidence() async -> PreferencesReach.Evidence?
}

extension MarfaRefreshing {
    func declarePreferences() async throws {}
    func choosePreferencesTables() async {}
    func preferencesEvidence() async -> PreferencesReach.Evidence? { nil }
}

nonisolated struct MarfaRefresh: MarfaRefreshing {
    let copy: WorkingCopy
    /// The scopes of the sign-in the copy uses, read from the Keychain each time; nil where none can be read.
    var scopes: @Sendable () -> [String]? = { nil }

    func readStatus() async throws -> Status { try await MarfaEngine.asking { try await copy.status() } }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        try await MarfaEngine.asking { try await copy.hydrate(types: types, tier: tier, edgeTypes: edgeTypes) }
    }
    func catchUp() async throws { _ = try await MarfaEngine.asking { try await copy.catchUp() } }
    func fetchKept() async throws -> KeptFetch { try await MarfaEngine.asking { try await copy.blobs.fetchKept() } }

    func declarePreferences() async throws {
        try await MarfaEngine.asking { try await copy.declareTypes([PreferencesType.definition]) }
    }

    /// A copy that never synced holds the declared type, so its tables can be chosen; elsewhere a refusal leaves them to
    /// `WorkingCopyPreferences.readiness()`.
    func choosePreferencesTables() async {
        guard let held = try? await MarfaEngine.asking({ try await copy.tables.held() }) else { return }
        let chosen = Set(held.choices.filter { $0.type == PreferencesType.id }.map(\.table))
        for table in PreferencesTable.allCases.map(\.rawValue) where !chosen.contains(table) {
            _ = try? await MarfaEngine.asking { try await copy.tables.hold(table, ofType: PreferencesType.id) }
        }
    }

    func preferencesEvidence() async -> PreferencesReach.Evidence? {
        guard let scopes = scopes(),
              let catalog = try? await MarfaEngine.asking({ try await copy.catalog.fromServer() })
        else { return nil }
        return PreferencesReach.Evidence(
            typeHeld: catalog.itemTypes.contains { $0.id == PreferencesType.id }, scopes: Set(scopes))
    }
}
