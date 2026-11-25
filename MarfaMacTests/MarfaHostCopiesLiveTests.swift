import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// The test instance typed two ways, each with a copy an older build made holding a change not yet sent.
    @MainActor @Suite(.serialized)
    struct MarfaHostCopiesLiveTests {
        @Test(.timeLimit(.minutes(4)))
        func theBareHostAndTheDefaultPortOpenOneCopyAndEachQueuedChangeReachesItsInstance() async throws {
            let address = try LiveMarfa.address()
            let key = try LiveMarfa.key()
            let base = try #require(URL(string: address))
            let hostName = try #require(base.host())
            // Typed as a person would, through the parser the Address field uses.
            let bare = try MarfaConnection(address: base.port.map { "\(hostName):\($0)" } ?? hostName)
            let explicit = try MarfaConnection(address: "https://\(hostName):\(base.port ?? 443)")
            #expect(bare.address.absoluteString == "https://\(hostName)" + (base.port.map { ":\($0)" } ?? ""))
            #expect(bare.sameServer(as: explicit))

            let bench = HostBench()
            // As an older build named them: one folder for each spelling.
            let bareFolder = Self.folder(of: bare)
            let explicitFolder = Self.folder(of: explicit)
            #expect(bareFolder != explicitFolder)
            let made = LiveMarfa.Made()
            do {
                for (folder, connection) in [(bareFolder, bare), (explicitFolder, explicit)] {
                    made.add(try await Self.queueChange(in: bench.location.store(in: folder), from: connection, key: key))
                }
                try await check(bench, bare: bare, explicit: explicit, folders: (bareFolder, explicitFolder), made: made.ids, base: base, key: key)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        private func check(
            _ bench: HostBench, bare: MarfaConnection, explicit: MarfaConnection, folders: (String, String), made: [ItemID],
            base: URL, key: String
        ) async throws {
            let (bareFolder, explicitFolder) = folders
            #expect(bench.location.directory(for: bare).lastPathComponent == bareFolder)

            let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
            bench.signIns.save(key, for: bare.address)
            try await host.connect(address: bare.address.absoluteString, key: key)
            let source = try #require(host.source as? MarfaSource)
            #expect(bench.location.store(for: bare) == bench.location.store(in: bareFolder))
            #expect(bench.location.directory(for: explicit).lastPathComponent == bareFolder, "either spelling now opens the same copy")
            let instance = try #require(await source.instanceID())
            #expect(host.libraryKey(for: bare) == "marfa:\(instance)")
            #expect(host.libraryKey(for: explicit) == host.libraryKey(for: bare))

            // The open copy sends its own change, and the other spelling's copy is sent from its own store, then goes.
            #expect(await eventually(within: .seconds(90)) { host.state == .online }, "\(host.state)")
            #expect(await eventually(within: .seconds(90)) {
                !FileManager.default.fileExists(atPath: bench.location.directory(named: explicitFolder).path)
            }, "the other spelling's copy was sent and removed")
            #expect(await eventually(within: .seconds(90)) { host.report.changesNotSent == 0 })
            for id in made {
                #expect(await Self.held(id, at: base, key: key), "\(id.rawValue) reached the test instance")
            }
            #expect(await Self.instance(at: base) == instance)

            // The other spelling while connected is the same copy: a sign in again, never another library.
            try await host.changeAddress(to: explicit.address.absoluteString, key: key)
            #expect(host.source === source)
            #expect(bench.location.folders() == [bareFolder])
            try await discardEverything(host)
        }

        /// Makes a hydrated copy in `store` for `connection` holding one create the server has not taken.
        private static func queueChange(in store: URL, from connection: MarfaConnection, key: String) async throws -> ItemID {
            try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copy = try await WorkingCopy.open(store: store, server: try connection.server(key: key))
            do {
                _ = try await copy.hydrate(types: ["core.note"], tier: .library)
                let write = try await copy.items.create(Draft(
                    type: "core.note", properties: ["title": .string("MARFAMACTEST typed as \(connection.address.absoluteString)")]))
                await copy.close()
                return ItemID(try #require(write.itemId))
            } catch {
                await copy.close()
                throw error
            }
        }

        private static func folder(of connection: MarfaConnection) -> String {
            MarfaStoreLocation(root: URL.temporaryDirectory.appending(path: UUID().uuidString)).directory(for: connection).lastPathComponent
        }

        private static func held(_ id: ItemID, at base: URL, key: String) async -> Bool {
            var request = URLRequest(url: base.appending(path: "items/\(id.rawValue)"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let status = (try? await URLSession.shared.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            return status == 200
        }

        private static func instance(at base: URL) async -> String? {
            guard let (data, _) = try? await URLSession.shared.data(from: base),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object["instance_id"] as? String
        }
    }
}
