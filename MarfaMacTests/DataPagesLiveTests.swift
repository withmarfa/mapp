import Foundation
import Marfa
import MarfaTesting
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// The Overview, History, File Storage and Sources pages' calls over a real test instance. The key must hold the owner's
    /// permissions. Every setting changed is put back as it was, or removed if it was unset, whether the test passes or not.
    @MainActor
    @Suite(.serialized)
    struct DataPagesLiveTests {
        private func connection() throws -> (MarfaConnection, MarfaServerCalls) {
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            return (connection, MarfaServerCalls(connection: connection, signIns: ScriptedSignIns([connection.address: try LiveMarfa.key()])))
        }

        @Test(.timeLimit(.minutes(2))) func theOverviewFileStorageAndSourceLimitAreRead() async throws {
            let (_, server) = try connection()
            let calls = ClientOwnerCalls { try server.client() }
            _ = try await calls.attention()
            let metrics = try await calls.instanceMetrics()
            #expect(!metrics.version.isEmpty)
            #expect((metrics.databaseBytes ?? 0) > 0)
            let update = try await calls.updateStatus()
            let profile = try await calls.profile()
            #expect(!update.running.isEmpty)
            #expect(profile.username?.isEmpty == false)
            let stores = try await calls.fileStores()
            #expect(stores.stores.contains { $0.kind == .disk })
            let enforcement = try await calls.enforcement()
            #expect(enforcement.instanceID?.isEmpty == false)
        }

        @Test(.timeLimit(.minutes(3))) func theHistoryAndFileStorageSettingsAreChangedOneAtATimeAndPutBack() async throws {
            let (connection, source) = try connection()
            let model = InstanceSettingsModel { .init(id: connection.address.absoluteString, source: source) }
            await model.load()
            let before = try #require(model.loaded, "the key can read the settings: \(String(describing: model.failure))")
            var result: Result<Void, any Error> = .success(())
            do {
                let changes: [(InstanceSetting, String, InstanceValue)] = [
                    (.auditRetentionDays, "91", .number(91)), (.enrichmentOcrEnabled, "false", .flag(false)), (.mcpFetchMaxMegabytes, "40", .number(40)),
                    (.diskReserveMegabytes, "64", .number(64)), (.blobCleanupGraceSeconds, "3600", .number(3_600)),
                ]
                for (setting, text, value) in changes {
                    model.draft[setting] = text
                    await model.save([setting])
                    // Shortening retention or lowering the disk reserve can ask for confirmation.
                    if let pending = model.pending {
                        #expect(setting == .auditRetentionDays || setting == .diskReserveMegabytes, "\(setting) asked first")
                        #expect(pending.shortenings.map(\.setting) == [setting])
                        await model.confirm(pending)
                    }
                    #expect(model.failure == nil, "\(setting): \(String(describing: model.failure))")
                    #expect(try await source.read().values[setting] == value, "\(setting) was kept as sent")
                }
                // Nothing else moved.
                let after = try await source.read()
                for setting in InstanceSetting.allCases where !changes.contains(where: { $0.0 == setting }) {
                    #expect(after.values[setting] == before.values[setting], "\(setting) changed by another page's save")
                }
            } catch {
                result = .failure(error)
            }
            var restore = InstanceConfigPatch()
            for setting in InstanceSetting.allCases where setting != .name {
                if let value = before.values[setting] { restore.values[setting] = value } else { restore.clear.insert(setting) }
            }
            let restored = try await source.update(restore, expecting: before.instanceID)
            for setting in InstanceSetting.allCases where setting != .name { #expect(restored.values[setting] == before.values[setting]) }
            try result.get()
        }

        @Test(.timeLimit(.minutes(2))) func aSourceLimitIsWrittenWithTheOtherLeversAndTurnedOff() async throws {
            let (_, server) = try connection()
            let calls = ClientOwnerCalls { try server.client() }
            let before = try await calls.enforcement()
            var result: Result<Void, any Error> = .success(())
            do {
                var limited = before
                limited.filter = .init(types: ["core.bookmark"], sources: ["demo-seed"])
                let written = try await calls.setEnforcement(limited)
                #expect(written.filter == limited.filter)
                #expect(written.strictTypes == before.strictTypes, "the levers not changed went back as they were")
                #expect(written.allowlist == before.allowlist)
                var off = written
                off.filter = nil
                #expect(try await calls.setEnforcement(off).filter == nil)
            } catch {
                result = .failure(error)
            }
            var now = try await calls.enforcement()
            now.filter = before.filter
            _ = try await calls.setEnforcement(now)
            try result.get()
        }
    }
}
