import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// The owner's pages' calls over a real test instance, through the package's client: every read the four pages make, a key made,
    /// renamed, narrowed and revoked, and an address change checked without being written. The key must hold the owner's
    /// permissions; the key made is revoked whether the test passes or not.
    @MainActor
    @Suite(.serialized)
    struct OwnerPagesLiveTests {
        private func calls() throws -> ClientOwnerCalls {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let calls = MarfaServerCalls(connection: connection, signIns: ScriptedSignIns([connection.address: try LiveMarfa.key()]))
            return ClientOwnerCalls { try calls.client() }
        }

        @Test(.timeLimit(.minutes(2))) func everyPageReadsWhatTheServerHolds() async throws {
            let calls = try calls()
            let profile = try await calls.profile()
            #expect(profile.username?.isEmpty == false)
            _ = try await calls.passkeys()
            _ = try await calls.browserSignIns()
            _ = try await calls.apps()
            #expect(try await calls.typeNames()["core.note"] != nil)
            let keys = try await calls.keys()
            #expect(!keys.isEmpty)
            let settings = try await calls.addresses()
            #expect(!settings.signIn.isEmpty)
            #expect(settings.addresses.contains(settings.signIn))
            let plan = try await calls.check(signIn: nil, addresses: settings.addresses)
            #expect(plan.consequences.isEmpty, "a check of what is already held changes nothing")
            #expect(!plan.requiresConfirmation)
            let after = try await calls.addresses()
            #expect(after == settings, "a check writes nothing")
        }

        @Test(.timeLimit(.minutes(2))) func aKeyIsMadeRenamedNarrowedAndRevoked() async throws {
            let calls = try calls()
            let tag = UUID().uuidString.prefix(8).lowercased()
            let made = try await calls.create(
                NewKey(label: "MAPPTEST \(tag)", source: "mapptest-\(tag)", tier: .feed, expires: nil, types: ["*": .write], permissions: []))
            var result: Result<Void, any Error> = .success(())
            do {
                #expect(made.secret.hasPrefix("marfa"))
                let renamed = try await calls.change(made.id, KeyChange(label: "MAPPTEST renamed \(tag)"))
                #expect(renamed.label == "MAPPTEST renamed \(tag)")
                #expect(renamed.tier == .feed)
                let narrowed = try await calls.change(made.id, KeyChange(types: ["*": .read]))
                #expect(narrowed.types == ["*": .read])
                await #expect(throws: OwnerFailure.self) {
                    _ = try await calls.change(made.id, KeyChange(types: ["*": .write]))
                }
                let sooner = Date.now.addingTimeInterval(86_400)
                let expiring = try await calls.change(made.id, KeyChange(expires: sooner))
                #expect(abs((expiring.expires ?? .distantPast).timeIntervalSince(sooner)) < 1)
            } catch {
                result = .failure(error)
            }
            try await calls.revoke(made.id)
            await #expect(throws: OwnerFailure.notFound) { try await calls.revoke(made.id) }
            #expect(try await calls.keys().contains { $0.id == made.id } == false)
            try result.get()
        }
    }
}
