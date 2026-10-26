import Foundation
import Testing
@testable import MAPP

extension LiveMarfaTests {
    /// This Marfa over a real test instance: the settings `MarfaServerConfig` reads, and a rename sent as a patch
    /// of the name alone. It never touches a retention, which a live instance would apply. The name is put back as
    /// it was, or removed if it was unset, whether the test passes or not. The key must hold `config.manage`, which an
    /// app's key usually lacks; with one that doesn't, the test fails on the server's 403.
    @MainActor
    @Suite(.serialized)
    struct MarfaInstanceSettingsLiveTests {
        @Test(.timeLimit(.minutes(2))) func theNameIsReadChangedAndPutBack() async throws {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let source = MarfaServerConfig(connection: connection, keys: MemoryKeyStore([connection: try LiveMarfa.key()]))
            let model = InstanceSettingsModel { .init(id: connection.address.absoluteString, source: source) }

            await model.load()
            let before = try #require(model.loaded, "the key can read the settings: \(String(describing: model.failure))")
            let temporary = "MAPPTEST name \(UUID().uuidString.prefix(8).lowercased())"
            var result: Result<Void, any Error> = .success(())
            do {
                model.draft[.name] = temporary
                #expect(model.patch == InstanceConfigPatch(values: [.name: .text(temporary)]))
                await model.save()
                #expect(model.failure == nil)
                #expect(model.saved == ["Name: \(temporary)"])
                #expect(try await source.read().name == temporary)
                // Nothing but the name changed.
                for setting in InstanceSetting.allCases where setting != .name {
                    #expect(model.loaded?.values[setting] == before.values[setting])
                }
            } catch {
                result = .failure(error)
            }
            // Put back: the earlier name, or no name so the default applies.
            var restore = InstanceConfigPatch()
            if let name = before.name { restore.values[.name] = .text(name) } else { restore.clear.insert(.name) }
            // Addressed to the instance that was read, as the app sends it.
            let restored = try await source.update(restore, expecting: before.instanceID)
            #expect(restored.values[.name] == before.values[.name])
            try result.get()
        }
    }
}
