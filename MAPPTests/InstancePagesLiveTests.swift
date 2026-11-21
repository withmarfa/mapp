import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// Activity, Monitoring, Limits and Start-Up over a real test instance: the audit log read a page at a time, the stored settings
    /// and the start-up settings listed, a limit changed and put back, a limit out of range refused, and a secret set and cleared
    /// without its value ever coming back. The key must hold the owner's permissions.
    @MainActor
    @Suite(.serialized)
    struct InstancePagesLiveTests {
        private func calls() throws -> ClientInstanceCalls {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let calls = MarfaServerCalls(connection: connection, signIns: ScriptedSignIns([connection.address: try LiveMarfa.key()]))
            return ClientInstanceCalls { try calls.client() }
        }

        @Test(.timeLimit(.minutes(2))) func theAuditLogIsReadAPageAtATime() async throws {
            let calls = try calls()
            let first = try await calls.activity(ActivityQuery(limit: 5))
            #expect(first.entries.count <= 5)
            if let next = first.next {
                let second = try await calls.activity(ActivityQuery(limit: 5, cursor: next))
                #expect(Set(first.entries.map(\.id)).isDisjoint(with: second.entries.map(\.id)), "an older page repeats nothing")
            }
            let access = try await calls.activity(ActivityQuery(kind: .access, limit: 5))
            #expect(access.entries.allSatisfy { ActivityWording.what($0.action) != "" })
            let none = try await calls.activity(ActivityQuery(search: "no such thing \(UUID().uuidString)"))
            #expect(none.entries.isEmpty && none.next == nil)
        }

        @Test(.timeLimit(.minutes(2))) func theSettingsAreListedAndTheirSecretsHoldNoValue() async throws {
            let snapshot = try await calls().storedSettings()
            #expect(snapshot.instanceID?.isEmpty == false)
            for limit in LimitSetting.all { #expect(snapshot.setting(limit.key)?.value?.int != nil, "\(limit.key) is listed with a number") }
            for secret in MonitoringSecret.allCases {
                let setting = try #require(snapshot.setting(secret.key))
                #expect(setting.isSecret && setting.value == nil, "\(secret.key) is never shown")
            }
            #expect(snapshot.startUp.contains { $0.name == "MARFA_PORT" })
            for name in snapshot.startUp.map(\.name) { #expect(StartUpWording.what(name) != "", "\(name) has words") }
        }

        @Test(.timeLimit(.minutes(2))) func aLimitIsChangedAndPutBackAndOneOutOfRangeIsRefused() async throws {
            let calls = try calls()
            let before = try await calls.storedSettings()
            let key = "enrichment_max_attempts"
            let held = try #require(before.setting(key))
            var result: Result<Void, any Error> = .success(())
            do {
                try await calls.change([key: .set(.int(4))], instanceID: before.instanceID)
                let changed = try await calls.storedSettings()
                #expect(changed.setting(key)?.value?.int == 4)
                await #expect(throws: OwnerFailure.self) { try await calls.change([key: .set(.int(500))], instanceID: before.instanceID) }
                #expect(try await calls.storedSettings().setting(key)?.value?.int == 4, "a refused change writes nothing")
                await #expect(throws: OwnerFailure.conflict) { try await calls.change([key: .set(.int(5))], instanceID: "01900000-0000-7000-8000-000000000000") }
            } catch {
                result = .failure(error)
            }
            try await calls.change([key: held.isStored ? .set(held.value ?? .int(3)) : .clear], instanceID: before.instanceID)
            #expect(try await calls.storedSettings().setting(key)?.value == held.value)
            try result.get()
        }

        @Test(.timeLimit(.minutes(2))) func aSecretIsSetAndClearedAndNeverComesBack() async throws {
            let calls = try calls()
            let before = try await calls.storedSettings()
            let key = "otel_exporter_otlp_headers"
            guard before.setting(key)?.isSet == false else { return }
            var result: Result<Void, any Error> = .success(())
            do {
                try await calls.change([key: .set(.text("x-mapptest=1"))], instanceID: before.instanceID)
                let set = try #require(try await calls.storedSettings().setting(key))
                #expect(set.isSet && set.value == nil)
            } catch {
                result = .failure(error)
            }
            try await calls.change([key: .clear], instanceID: before.instanceID)
            #expect(try await calls.storedSettings().setting(key)?.isSet == false)
            try result.get()
        }
    }
}
