import Foundation
import Marfa
import Testing
@testable import MarfaMac

extension LiveMarfaTests {
    /// This app's settings across two Macs on the test instance: two copies, each with a store and defaults of its own. The
    /// key holds the test instance's app key, which reaches `app.marfa-mac.preferences` as its owner made it. Every settings
    /// item is purged before and after each test.
    @MainActor
    @Suite(.serialized)
    final class PreferencesSyncLiveTests {
        /// One Mac: its copy, its defaults and its settings sync.
        final class Mac {
            let source: MarfaSource
            let defaults: UserDefaults
            let sync: PreferencesSync
            let root: URL

            init(source: MarfaSource, defaults: UserDefaults, sync: PreferencesSync, root: URL) {
                self.source = source
                self.defaults = defaults
                self.sync = sync
                self.root = root
            }

            /// Writes what coalesces now and sends the queue.
            func send() async {
                await sync.flush()
                await source.flush()
            }
        }

        private var macs: [Mac] = []
        /// Settings items a test binned itself, which the server's list of items leaves out, purged at the end.
        private var binned: [ItemID] = []
        private let placement = PagePlacements.key

        private func mac() async throws -> Mac {
            let root = URL.temporaryDirectory.appending(path: "PreferencesSyncLive-\(UUID().uuidString)", directoryHint: .isDirectory)
            let connection = try MarfaConnection(address: try LiveMarfa.address())
            let signIns = ScriptedSignIns()
            signIns.save(try LiveMarfa.key(), for: connection.address, scopes: [PreferencesType.vendorScope])
            let source = try await MarfaSource.open(connection, signIns: signIns, location: MarfaStoreLocation(root: root))
            let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferencesLive")
            let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(100)) {}
            let mac = Mac(source: source, defaults: defaults, sync: sync, root: root)
            macs.append(mac)
            return mac
        }

        private func start(_ mac: Mac) async throws {
            mac.sync.attach(WorkingCopyPreferences(copy: mac.source.copy, answers: mac.source.preferenceAnswers), library: "marfa:" + (try LiveMarfa.address()), name: { nil })
            mac.source.refresh()
            try #require(await LiveMarfa.until {
                await mac.sync.flush()
                return mac.sync.standing == .syncing
            }, "the settings never synced: \(mac.sync.standing)")
        }

        private func end() async {
            for mac in macs {
                mac.sync.detach()
                await mac.source.close()
                try? FileManager.default.removeItem(at: mac.root)
            }
            macs = []
            await LiveMarfa.purge(binned)
            binned = []
            await Self.purgeSettings()
        }

        /// Every settings item the instance holds, by the server's own list.
        private static func settingsItems() async -> [ItemID] {
            guard let address = try? LiveMarfa.address(), let key = try? LiveMarfa.key(),
                  var url = URLComponents(string: address + "/items")
            else { return [] }
            url.queryItems = [URLQueryItem(name: "type", value: PreferencesType.id), URLQueryItem(name: "limit", value: "100")]
            var request = URLRequest(url: url.url!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = page["data"] as? [[String: Any]]
            else { return [] }
            return rows.compactMap { ($0["id"] as? String).map { ItemID($0) } }
        }

        private static func purgeSettings() async { await LiveMarfa.purge(await settingsItems()) }

        private func run(_ body: () async throws -> Void) async throws {
            await Self.purgeSettings()
            do { try await body() } catch {
                await end()
                throw error
            }
            await end()
        }

        /// An earlier build kept this Mac's type looks under the address and synced them. The app then opens the Marfa by
        /// its instance: the looks move first, so the Marfa keeps every row it held and takes the part only this Mac had.
        @Test(.timeLimit(.minutes(4)))
        func looksKeptUnderTheAddressReachTheInstanceWithoutRemovingAny() async throws {
            try await run {
                let address = try LiveMarfa.address()
                let older = try await mac()
                let earlier = #"{"marfa:\#(address)":{"core.note":{"date":"created"},"core.task":{"date":"edited"}}}"#
                older.defaults.set(Data(earlier.utf8), forKey: TypeLooks.defaultsKey)
                try await start(older)
                await older.send()
                let item = try #require(await Self.settingsItems().first)
                older.sync.detach()
                await older.source.close()
                // Chosen on that build after its last sync, so only this Mac holds it.
                let later = #"{"marfa:\#(address)":{"core.note":{"date":"created"},"core.task":{"date":"edited"},"core.event":{"date":"created"}}}"#
                older.defaults.set(Data(later.utf8), forKey: TypeLooks.defaultsKey)
                older.defaults.set(address, forKey: MarfaHost.addressKey)

                let root = URL.temporaryDirectory.appending(path: "PreferencesSyncLive-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: root) }
                let signIns = ScriptedSignIns()
                signIns.save(try LiveMarfa.key(), for: try MarfaConnection(address: address).address, scopes: [PreferencesType.vendorScope])
                let host = MarfaHost(defaults: older.defaults, signIns: signIns, location: MarfaStoreLocation(root: root))
                let libraries = Libraries(
                    host: host, defaults: older.defaults, handOverPages: { $0(true) }, syncsPreferences: true,
                    defaultsDomain: older.sync.domain)
                await libraries.launch()
                let source = try #require(host.source as? MarfaSource)
                source.refresh()
                try #require(await Self.syncs(libraries), "the settings never synced: \(libraries.preferences.standing)")
                // A copy that has not said its instance yet names the library by its folder until it next opens.
                let stored = try JSONSerialization.jsonObject(with: try #require(older.defaults.data(forKey: TypeLooks.defaultsKey))) as? [String: Any]
                #expect(stored.map { Array($0.keys) } == [libraries.libraryKey])
                #expect(libraries.libraryKey != "marfa:" + address)
                await libraries.preferences.flush()
                await source.flush()
                libraries.preferences.detach()
                await source.close()

                // Opened again, the copy says its instance, and the library takes that name before it syncs.
                let again = MarfaHost(defaults: older.defaults, signIns: signIns, location: MarfaStoreLocation(root: root))
                let reopened = Libraries(
                    host: again, defaults: older.defaults, handOverPages: { $0(true) }, syncsPreferences: true,
                    defaultsDomain: older.sync.domain)
                await reopened.launch()
                let second = try #require(again.source as? MarfaSource)
                second.refresh()
                try #require(await Self.syncs(reopened), "the settings never synced again: \(reopened.preferences.standing)")
                #expect(reopened.libraryKey == "marfa:" + (try #require(ProcessInfo.processInfo.environment["MARFA_TEST_INSTANCE_ID"])), "\(reopened.libraryKey)")
                #expect(reopened.typeLooks.choices(for: reopened.libraryKey).count == 3)
                await reopened.preferences.flush()
                await second.flush()
                reopened.preferences.detach()
                await second.close()

                let reader = try await mac()
                reader.source.refresh()
                let copy = WorkingCopyPreferences(copy: reader.source.copy, answers: reader.source.preferenceAnswers)
                let look = { (type: String) in PreferenceUnit.row(.types, setting: "look", key: type) }
                let expected: PreferenceUnits = [
                    look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
                    look("core.event"): #"{"date":"created"}"#,
                ]
                let reached = await LiveMarfa.until {
                    let held = (try? await copy.units(of: item.rawValue)) ?? [:]
                    return expected.allSatisfy { held[$0.key] == $0.value }
                }
                let held = (try? await copy.units(of: item.rawValue)) ?? [:]
                #expect(reached, "the Marfa holds \(held.filter { if case .row(.types, "look", _) = $0.key { true } else { false } })")
                #expect(await Self.settingsItems() == [item])
            }
        }

        /// The same, where a look kept under the address can no longer be read, so its store sets it aside as the app
        /// starts. Opened by its folder, the looks wait; opened again by the instance, the Marfa keeps the row this Mac
        /// synced for it and takes the part only this Mac had.
        @Test(.timeLimit(.minutes(4)))
        func aLookItsStoreSetsAsideAtLaunchLeavesTheMarfasRow() async throws {
            try await run {
                let address = try LiveMarfa.address()
                let older = try await mac()
                let earlier = #"{"marfa:\#(address)":{"core.note":{"date":"created"},"core.task":{"date":"edited"}}}"#
                older.defaults.set(Data(earlier.utf8), forKey: TypeLooks.defaultsKey)
                try await start(older)
                await older.send()
                let item = try #require(await Self.settingsItems().first)
                older.sync.detach()
                await older.source.close()
                let later = #"{"marfa:\#(address)":{"core.note":{"date":7},"core.task":{"date":"edited"},"core.event":{"date":"created"}}}"#
                older.defaults.set(Data(later.utf8), forKey: TypeLooks.defaultsKey)
                older.defaults.set(address, forKey: MarfaHost.addressKey)

                let root = URL.temporaryDirectory.appending(path: "PreferencesSyncLive-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: root) }
                let signIns = ScriptedSignIns()
                signIns.save(try LiveMarfa.key(), for: try MarfaConnection(address: address).address, scopes: [PreferencesType.vendorScope])
                for open in 0..<2 {
                    let host = MarfaHost(defaults: older.defaults, signIns: signIns, location: MarfaStoreLocation(root: root))
                    let libraries = Libraries(
                        host: host, defaults: older.defaults, handOverPages: { $0(true) }, syncsPreferences: true,
                        defaultsDomain: older.sync.domain)
                    await libraries.launch()
                    let source = try #require(host.source as? MarfaSource)
                    source.refresh()
                    try #require(await Self.syncs(libraries), "open \(open) never synced: \(libraries.preferences.standing)")
                    #expect(libraries.librarySettings.unsettled.isEmpty == (open == 1), "open \(open): \(libraries.librarySettings.unsettled)")
                    if open == 1 {
                        let choices = libraries.typeLooks.choices(for: libraries.libraryKey)
                        #expect(choices.mapValues(\.date) == [TypeID("core.note"): .created, TypeID("core.task"): .edited, TypeID("core.event"): .created])
                    }
                    await libraries.preferences.flush()
                    await source.flush()
                    libraries.preferences.detach()
                    await source.close()
                }

                let reader = try await mac()
                reader.source.refresh()
                let copy = WorkingCopyPreferences(copy: reader.source.copy, answers: reader.source.preferenceAnswers)
                let look = { (type: String) in PreferenceUnit.row(.types, setting: "look", key: type) }
                let expected: PreferenceUnits = [
                    look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
                    look("core.event"): #"{"date":"created"}"#,
                ]
                let reached = await LiveMarfa.until {
                    let held = (try? await copy.units(of: item.rawValue)) ?? [:]
                    return expected.allSatisfy { held[$0.key] == $0.value }
                }
                let held = (try? await copy.units(of: item.rawValue)) ?? [:]
                #expect(reached, "the Marfa holds \(held.filter { if case .row(.types, "look", _) = $0.key { true } else { false } })")
                #expect(await Self.settingsItems() == [item])
            }
        }

        private static func syncs(_ libraries: Libraries) async -> Bool {
            await LiveMarfa.until {
                await libraries.preferences.flush()
                return libraries.preferences.standing == .syncing
            }
        }

        @Test(.timeLimit(.minutes(3)))
        func aChangeOnOneMacReachesTheOther() async throws {
            try await run {
                let one = try await mac()
                one.defaults.set("dark", forKey: AppearanceKey.theme)
                try await start(one)
                await one.send()
                #expect(await Self.settingsItems().count == 1)
                let two = try await mac()
                try await start(two)
                #expect(two.defaults.string(forKey: AppearanceKey.theme) == "dark")
                one.defaults.set("light", forKey: AppearanceKey.theme)
                await one.send()
                #expect(await LiveMarfa.until { two.defaults.string(forKey: AppearanceKey.theme) == "light" })
                #expect(await Self.settingsItems().count == 1)
            }
        }

        @Test(.timeLimit(.minutes(3)))
        func theLaterRowWinsAndUndoingItPutsTheEarlierBack() async throws {
            try await run {
                let one = try await mac()
                try await start(one)
                await one.send()
                let two = try await mac()
                try await start(two)
                let earlier = #"{"core.note":{"rows":{"due_at":true}}}"#
                let later = #"{"core.note":{"rows":{"due_at":false}}}"#
                one.defaults.set(earlier, forKey: placement)
                await one.send()
                #expect(await LiveMarfa.until { two.defaults.string(forKey: self.placement) == earlier })
                two.defaults.set(later, forKey: placement)
                await two.send()
                #expect(await LiveMarfa.until { one.defaults.string(forKey: self.placement) == later })

                // The table's change log holds the later write as its newest batch.
                let item = try #require(await Self.settingsItems().first)
                let batch = try #require(await Self.newestBatch(of: item, in: .types))
                _ = try await two.source.copy.tables.undo(batch: batch, in: PreferencesTable.types.rawValue, of: item.rawValue)
                await two.source.flush()
                #expect(await LiveMarfa.until { two.defaults.string(forKey: self.placement) == earlier })
                #expect(await LiveMarfa.until { one.defaults.string(forKey: self.placement) == earlier })
            }
        }

        @Test(.timeLimit(.minutes(3)))
        func adoptingFillsTheRowsTheItemLacks() async throws {
            try await run {
                let one = try await mac()
                one.defaults.set(#"{"core.note":{"rows":{"due_at":true}}}"#, forKey: placement)
                try await start(one)
                await one.send()
                let two = try await mac()
                two.defaults.set(#"{"core.task":{"rows":{"priority":true}}}"#, forKey: placement)
                try await start(two)
                await two.send()
                let both = #"{"core.note":{"rows":{"due_at":true}},"core.task":{"rows":{"priority":true}}}"#
                #expect(two.defaults.string(forKey: placement) == both)
                #expect(await LiveMarfa.until { one.defaults.string(forKey: self.placement) == both })
            }
        }

        /// A settings item left in the bin, whose tables the copy never fills, does not hold up the first sync.
        @Test(.timeLimit(.minutes(3)))
        func aBinnedSettingsItemDoesNotStopTheSync() async throws {
            try await run {
                binned.append(try #require(await Self.binnedSettingsItem(), "could not make a binned settings item"))
                let one = try await mac()
                one.defaults.set("dark", forKey: AppearanceKey.theme)
                try await start(one)
                await one.send()
                #expect(await Self.settingsItems().count == 1)
            }
        }

        /// A removal the person asked for with changes waiting is not made while they are discarded, since sending it sends
        /// them; made where they may be sent, the server has taken it and the settings are in the bin.
        @Test(.timeLimit(.minutes(3)))
        func aRemovalNeverSendsWhatWasDiscarded() async throws {
            try await run {
                let one = try await mac()
                try await start(one)
                await one.send()
                let queued = try await one.source.copy.items.create(
                    Draft(type: "core.note", properties: JSONObject([("title", .string("The app live removal test"))])))
                let note = try #require(queued.itemId)
                binned.append(ItemID(note))

                await #expect(throws: PreferencesSync.RemovalError.otherChangesWait) {
                    try await one.sync.remove(confirmed: true, sendsOtherChanges: false)
                }
                #expect(await Self.settingsItems().count == 1, "the settings are still in the Marfa")
                #expect(try await one.source.copy.queue.all().contains { $0.id == queued.id && $0.verdict == nil }, "the change was not sent")

                try await one.sync.remove(confirmed: true, sendsOtherChanges: true)
                #expect(await Self.settingsItems().isEmpty, "the server has taken the removal")
                #expect(one.sync.standing == .off(.removed))
            }
        }

        /// Makes a settings item over HTTP and moves it to the bin.
        private static func binnedSettingsItem() async -> ItemID? {
            guard let address = try? LiveMarfa.address(), let key = try? LiveMarfa.key(), let base = URL(string: address) else { return nil }
            var create = URLRequest(url: base.appending(path: "items"))
            create.httpMethod = "POST"
            create.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            create.httpBody = try? JSONSerialization.data(withJSONObject: ["type": PreferencesType.id, "properties": [String: Any]()])
            guard let (data, _) = try? await URLSession.shared.data(for: create),
                  let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (answer["item"] as? [String: Any])?["id"] as? String
            else { return nil }
            var bin = URLRequest(url: base.appending(path: "items/\(id)"))
            bin.httpMethod = "DELETE"
            bin.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let (_, response) = try? await URLSession.shared.data(for: bin),
                  let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
            else { return nil }
            return ItemID(id)
        }

        private static func newestBatch(of item: ItemID, in table: PreferencesTable) async -> String? {
            guard let address = try? LiveMarfa.address(), let key = try? LiveMarfa.key(),
                  let url = URL(string: address + "/items/\(item.rawValue)/tables/\(table.rawValue)/batches")
            else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let batches = page["data"] as? [[String: Any]]
            else { return nil }
            return batches.first?["id"] as? String
        }
    }
}
