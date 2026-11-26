import Foundation
import Marfa
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// Two test instances, each signed in with a key held in memory: switching from one to the other and back asks for no
    /// approval, and a change left in each copy reaches only its own instance once that Marfa is used again. Needs a second
    /// test instance in `MARFA_OTHER_API_URL`, `MARFA_OTHER_API_KEY` and `MARFA_OTHER_TEST_INSTANCE_ID`.
    @MainActor @Suite(.serialized)
    struct MarfaHostKeptSignInsLiveTests {
        @Test(.timeLimit(.minutes(5)), .enabled(if: LiveMarfa.hasOther, "Needs a second test instance"))
        func switchingBackUsesEachHeldSignInAndEachQueueReachesOnlyItsOwnInstance() async throws {
            let first = try MarfaConnection(address: try LiveMarfa.address())
            let firstKey = try LiveMarfa.key()
            let second = try MarfaConnection(address: try LiveMarfa.otherAddress())
            let secondKey = try LiveMarfa.otherKey()
            #expect(!first.sameServer(as: second))
            let firstInstance = try #require(await Self.instance(at: first.address))
            let secondInstance = try #require(await Self.instance(at: second.address))
            try #require(firstInstance != secondInstance, "the two addresses must be two instances")

            let bench = HostBench()
            bench.signIns.save(firstKey, for: first.address)
            bench.signIns.save(secondKey, for: second.address)
            // A browser sign-in that would fail shows any approval asked for.
            bench.signIns.script(browser: [.failure(SignInError.canceled)])
            let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
            var made: [(ItemID, URL, String)] = []
            do {
                try await host.connect(address: first.address.absoluteString, via: .browser)
                try await Self.settled(host, at: first)
                try await host.changeAddress(to: second.address.absoluteString, via: .browser)
                try await Self.settled(host, at: second)
                #expect(bench.hasCopy(first), "the first Marfa's copy is kept")

                let firstChange = try await Self.queueChange(in: bench.location.store(for: first), naming: "first")
                made.append((firstChange, first.address, firstKey))
                #expect(await Self.status(of: firstChange, at: first.address, key: firstKey) == 404, "it waits while another Marfa is shown")

                try await host.changeAddress(to: first.address.absoluteString, via: .browser)
                try await Self.settled(host, at: first)
                #expect(try await eventuallyAsking(within: .seconds(90)) { await Self.status(of: firstChange, at: first.address, key: firstKey) == 200 })
                #expect(await Self.status(of: firstChange, at: second.address, key: secondKey) == 404, "never sent to the other instance")

                let secondChange = try await Self.queueChange(in: bench.location.store(for: second), naming: "second")
                made.append((secondChange, second.address, secondKey))
                try await host.changeAddress(to: second.address.absoluteString, via: .browser)
                try await Self.settled(host, at: second)
                #expect(try await eventuallyAsking(within: .seconds(90)) { await Self.status(of: secondChange, at: second.address, key: secondKey) == 200 })
                #expect(await Self.status(of: secondChange, at: first.address, key: firstKey) == 404, "never sent to the other instance")

                #expect(!bench.signIns.calls.contains { $0.hasPrefix("browser") || $0.hasPrefix("code") }, "\(bench.signIns.calls)")
                #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") }, "\(bench.signIns.calls)")
                #expect(try bench.signIns.key(for: first.address) == firstKey)
                #expect(try bench.signIns.key(for: second.address) == secondKey)
                print("KEPT-SIGN-INS-LIVE first=\(firstInstance) second=\(secondInstance) firstChange=\(firstChange.rawValue) secondChange=\(secondChange.rawValue) calls=\(bench.signIns.calls)")
            } catch {
                await Self.purge(made)
                throw error
            }
            await Self.purge(made)
            try await discardEverything(host)
            #expect(try bench.signIns.key(for: first.address) == firstKey, "disconnecting the second Marfa leaves the first signed in")
        }

        /// Waits until the copy shown is `connection`'s, the server answers, and nothing waits to be sent.
        private static func settled(_ host: MarfaHost, at connection: MarfaConnection) async throws {
            #expect(host.connection == connection)
            try #require(await eventually(within: .seconds(90)) { host.state == .online }, "\(host.state)")
            try #require(await eventually(within: .seconds(90)) { host.report.queueRead && host.report.changesNotSent == 0 })
        }

        /// Puts one create in the queue of a copy that is not open, as an edit made there before the switch would be.
        private static func queueChange(in store: URL, naming name: String) async throws -> ItemID {
            let copy = try await WorkingCopy.open(store: store)
            do {
                let write = try await copy.items.create(Draft(
                    type: "core.note", properties: ["title": .string("MARFAMACTEST kept sign-ins, \(name)")]))
                await copy.close()
                return ItemID(try #require(write.itemId))
            } catch {
                await copy.close()
                throw error
            }
        }

        private static func status(of id: ItemID, at base: URL, key: String) async -> Int? {
            var request = URLRequest(url: base.appending(path: "items/\(id.rawValue)"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return (try? await URLSession.shared.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        }

        private static func instance(at base: URL) async -> String? {
            guard let (data, _) = try? await URLSession.shared.data(from: base),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object["instance_id"] as? String
        }

        /// Removes only the items this test made, each from the instance it was made in.
        private static func purge(_ made: [(ItemID, URL, String)]) async {
            for (id, base, key) in made {
                for (method, path) in [("DELETE", "items/\(id.rawValue)"), ("POST", "items/\(id.rawValue)/purge")] {
                    var request = URLRequest(url: base.appending(path: path))
                    request.httpMethod = method
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    let status = (try? await URLSession.shared.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
                    if method == "POST", let status, ![200, 204, 404].contains(status) {
                        Issue.record("purging a test item answered \(status)")
                    }
                }
            }
        }
    }
}

nonisolated extension LiveMarfa {
    /// Whether the environment names a second test instance.
    static var hasOther: Bool {
        !(ProcessInfo.processInfo.environment["MARFA_OTHER_API_URL"] ?? "").isEmpty
    }

    /// The second test instance's address, confirmed against `MARFA_OTHER_TEST_INSTANCE_ID` as `address()` is.
    static func otherAddress() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let address = try #require(environment["MARFA_OTHER_API_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines))
        try refuseUnlessTestInstance(at: address, acknowledging: environment["MARFA_OTHER_TEST_INSTANCE_ID"])
        return address
    }

    static func otherKey() throws -> String {
        let key = ProcessInfo.processInfo.environment["MARFA_OTHER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try #require(key.isEmpty ? nil : key, "The second test instance needs MARFA_OTHER_API_KEY")
    }
}
