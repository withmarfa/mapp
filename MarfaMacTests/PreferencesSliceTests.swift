import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

/// A server that answers whether it holds the app's type and what the sign-in holds, and refuses a hydration that takes the
/// type where told to, as the core refuses a slice naming a type the sign-in cannot read.
private actor SliceServer: MarfaRefreshing {
    var evidence: PreferencesReach.Evidence?
    var holds: [String]
    var refusal: MarfaError?
    private(set) var hydrated: [[String]] = []
    private(set) var declared = 0
    /// Each step in the order it was asked.
    private(set) var steps: [String] = []

    init(evidence: PreferencesReach.Evidence?, holds: [String] = MarfaSync.slice, refusal: MarfaError? = nil) {
        self.evidence = evidence
        self.holds = holds
        self.refusal = refusal
    }

    func readStatus() -> Status {
        Status(sliceTypes: holds, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) throws -> HydrateReport {
        hydrated.append(types)
        steps.append("hydrate")
        if types.contains(PreferencesType.id), let refusal { throw refusal }
        holds = types
        return HydrateReport(types: types, tier: tier, edgeTypes: edgeTypes, items: 0, edges: 0, pages: 1, cursor: "done")
    }

    func catchUp() {}
    func fetchKept() -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
    func declarePreferences() { declared += 1 }
    func choosePreferencesTables() { steps.append("tables") }
    func preferencesEvidence() -> PreferencesReach.Evidence? { evidence }
}

@Suite(.hangLimit) struct PreferencesSliceTests {
    private func hydrating(_ server: SliceServer) async throws {
        let fake = WorkingCopy.fake()
        let sync = MarfaSync(copy: fake.copy, hub: MarfaHub(), refreshing: server) { event in
            switch event {
            case .update(_, let done), .answers(let done): done.resume()
            default: break
            }
            return true
        }
        do {
            try await sync.refreshNow(hydrating: true)
        } catch {
            await sync.stop()
            await fake.copy.close()
            throw error
        }
        await sync.stop()
        await fake.copy.close()
    }

    @Test func aSignInThatNamesTheVendorTakesTheType() async throws {
        let server = SliceServer(evidence: .init(typeHeld: true, scopes: [PreferencesType.vendorScope]))
        try await hydrating(server)
        #expect(await server.hydrated == [MarfaSync.preferencesSlice])
        #expect(await server.declared == 1)
    }

    /// A table chosen once the copy is whole is filled under the copy's stream, and the core refuses the follow that
    /// starts meanwhile, which then misses another Mac's changes. A copy that never synced takes the choice before.
    @Test func theSettingsTablesAreChosenBeforeTheHydrationThatTakesThem() async throws {
        let server = SliceServer(evidence: .init(typeHeld: true, scopes: [PreferencesType.vendorScope]))
        try await hydrating(server)
        #expect(await server.steps == ["tables", "hydrate"])

        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: directory.appending(path: "copy.sqlite"))
        let refresh = MarfaRefresh(copy: copy)
        try await refresh.declarePreferences()
        await refresh.choosePreferencesTables()
        let chosen = try await copy.tables.held().choices.filter { $0.type == PreferencesType.id }.map(\.table)
        await copy.close()
        #expect(Set(chosen) == Set(PreferencesTable.allCases.map(\.rawValue)))
    }

    @Test func aSignInWithoutTheVendorKeepsTheSliceItHad() async throws {
        let server = SliceServer(evidence: .init(typeHeld: true, scopes: ["*:write"]))
        try await hydrating(server)
        #expect(await server.hydrated == [MarfaSync.slice])
        #expect(await server.steps == ["hydrate"])
    }

    @Test func theFirstMacTakesTheTypeWhereItMayRegisterIt() async throws {
        let server = SliceServer(evidence: .init(typeHeld: false, scopes: [PreferencesType.registeringScope]))
        try await hydrating(server)
        #expect(await server.hydrated == [MarfaSync.preferencesSlice])
    }

    @Test func aRefusedHydrationIsMadeAgainWithoutTheType() async throws {
        let refusal = MarfaError.forbidden(code: "type_not_permitted", message: "no", server: nil)
        let server = SliceServer(evidence: .init(typeHeld: true, scopes: [PreferencesType.vendorScope]), refusal: refusal)
        try await hydrating(server)
        #expect(await server.hydrated == [MarfaSync.preferencesSlice, MarfaSync.slice])
    }

    @Test func withoutEvidenceTheCopyKeepsWhatItHolds() async throws {
        let server = SliceServer(evidence: nil, holds: MarfaSync.preferencesSlice)
        try await hydrating(server)
        #expect(await server.hydrated == [MarfaSync.preferencesSlice])
    }

    @Test func theReachRule() {
        let vendor: Set<String> = [PreferencesType.vendorScope]
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: vendor), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: ["app.*:write"]), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: true, scopes: []), holdsTypeNow: true))
        #expect(!PreferencesReach.includes(.init(typeHeld: true, scopes: ["*:write", PreferencesType.registeringScope]), holdsTypeNow: false))
        #expect(!PreferencesReach.includes(.init(typeHeld: false, scopes: vendor), holdsTypeNow: false))
        #expect(PreferencesReach.includes(.init(typeHeld: false, scopes: [PreferencesType.registeringScope]), holdsTypeNow: false))
    }

    @Test func anAppsOwnRowsAndTypesAreNoPartOfTheLibrary() {
        #expect(TypeID("app.marfa-mac.preferences").isHidden)
        #expect(TypeID("system.view").isHidden)
        #expect(!TypeID("core.note").isHidden)
        #expect(!TypeID("application.thing").isHidden)
    }
}
