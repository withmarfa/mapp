import Foundation
import Marfa
import MarfaAPI
import MarfaTesting
import OpenAPIRuntime
import Testing
@testable import MarfaMac

/// How the calls to the server itself are made and how their failures are told. None reaches a server: the package's
/// `Server` takes no transport that a test can replace, so what goes over the wire (the `PATCH`, the instance header,
/// the paging query) is the package's own tests' to show, and the live plan runs these calls against a test instance.
@Suite(.hangLimit) struct MarfaServerCallsTests {
    private func calls(_ keys: any SignIns) throws -> MarfaServerCalls {
        MarfaServerCalls(connection: try MarfaConnection(address: "https://marfa.test"), signIns: keys)
    }

    // MARK: What is sent

    @Test func theChangeNamesOnlyTheChangedSettingsAndClearRemovesOne() {
        let patch = InstanceConfigPatch(values: [.name: .text("Home"), .versionMaxVersions: .number(200)], clear: [.trashRetentionDays])
        let change = MarfaServerCalls.patch(patch)
        #expect(change.name == .value("Home"))
        #expect(change.versionMaxVersions == .value(200))
        #expect(change.trashRetentionDays == .null)
        #expect(change.versionRecentDays == nil)
        #expect(change.versionDailySnapshotDays == nil)
        #expect(change.versionWeeklySnapshotDays == nil)
        // Settings This Marfa does not show are never sent.
        #expect(change.grantInactivityDays == nil)
        #expect(change.enrichmentEnabled == nil)
        #expect(change.heartbeatEnabled == nil)
    }

    @Test func aChangeWithNothingChangedSendsNothing() {
        #expect(MarfaServerCalls.patch(InstanceConfigPatch(values: [:], clear: [])) == Operations.UpdateConfig.Input.Body.JsonPayload())
    }

    // MARK: The sign-in

    @Test func anUnreadableSignInIsToldAsUnreadableAndNothingIsSent() async throws {
        let signIns = ScriptedSignIns()
        signIns.makeUnreadable(try MarfaConnection(address: "https://marfa.test"))
        let calls = try calls(signIns)
        let unreadable = Words.signInUnreadable
        await #expect(throws: ItemHistoryFailure.failed(unreadable)) { _ = try await calls.page(of: ItemID("a"), after: nil, limit: 50) }
        await #expect(throws: InstanceConfigFailure.failed(unreadable)) { _ = try await calls.read() }
        await #expect(throws: InstanceConfigFailure.failed(unreadable)) {
            _ = try await calls.update(MarfaMac.InstanceConfigPatch(values: [.name: .text("New")], clear: []), expecting: "i-1")
        }
        await #expect(throws: TypeIconFailure.failed(unreadable)) { _ = try await calls.setIcon("lucide:book", ofType: TypeID("core.note")) }
    }

    @Test func noSignInIsToldAsARefusedOneAndNothingIsSent() async throws {
        let calls = try calls(ScriptedSignIns())
        await #expect(throws: ItemHistoryFailure.keyRefused) { _ = try await calls.page(of: ItemID("a"), after: nil, limit: 50) }
        await #expect(throws: InstanceConfigFailure.keyRefused) { _ = try await calls.read() }
        await #expect(throws: TypeIconFailure.keyRefused) { _ = try await calls.setIcon(nil, ofType: TypeID("core.note")) }
    }

    // MARK: The package's error meanings

    @Test func aServerThatIsAwayIsToldAsAwayForEveryCall() {
        for error in [MarfaError.noConnection(message: "offline"), .network(message: "no answer")] {
            let ending = MarfaServerCalls.ending(error)
            #expect(ending == .unreachable)
            #expect(MarfaServerCalls.historyFailure(ending) == .unreachable)
            #expect(MarfaServerCalls.configFailure(ending) == .unreachable)
            #expect(MarfaServerCalls.iconFailure(ending) == .unreachable)
        }
    }

    @Test func aRefusedKeyIsNotAMissingPermissionOrAnAwayServer() {
        let refused = MarfaServerCalls.ending(MarfaError.unauthorized(code: "invalid_key", message: "no", server: nil))
        #expect(refused == .keyRefused)
        #expect(MarfaServerCalls.configFailure(refused) == .keyRefused)
        let forbidden = MarfaServerCalls.ending(MarfaError.forbidden(code: "forbidden", message: "no", server: nil))
        #expect(forbidden == .notPermitted)
        #expect(MarfaServerCalls.historyFailure(forbidden) == .notPermitted)
        #expect(MarfaServerCalls.iconFailure(forbidden) == .notPermitted)
    }

    @Test func anotherInstanceAtTheAddressIsRefusedAndTheDraftIsLeftToTheModel() {
        let ending = MarfaServerCalls.ending(MarfaError.instanceChanged(message: "other", server: nil))
        #expect(MarfaServerCalls.configFailure(ending) == .instanceChanged)
        #expect(MarfaServerCalls.configFailure(MarfaServerCalls.ending(MarfaError.versionConflict(message: "stale", server: nil))) == .failed(Words.syncFailed))
    }

    @Test func anItemTheServerHoldsNoHistoryForIsUnavailable() {
        let ending = MarfaServerCalls.ending(MarfaError.notFound(code: "not_found", message: "gone", server: nil))
        #expect(MarfaServerCalls.historyFailure(ending) == .unavailable)
        #expect(MarfaServerCalls.iconFailure(ending) == .failed(Words.syncFailed))
    }
}
