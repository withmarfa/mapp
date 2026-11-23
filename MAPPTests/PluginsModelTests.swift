import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MAPP

/// A server and a release with every answer scripted.
final class FakePluginCalls: PluginCalls, @unchecked Sendable {
    struct State {
        var installed: [InstalledPlugin] = []
        var typeInfo: [String: PluginTypeInfo] = [:]
        var release: [ReleasePlugin] = []
        var releaseFailure: PluginFailure?
        var bundles: [String: ReleaseBundle] = [:]
        var installRefusal: PluginFailure?
        var sent: [Data] = []
        var removeRefusal: OwnerFailure?
        var removals: [String] = []
        var removalAnswer: PluginRemoval?
        var hostNames: [String: String] = [:]
    }

    let state = Mutex(State())

    func installed() async throws(OwnerFailure) -> [InstalledPlugin] { state.withLock { $0.installed } }

    func plugin(_ name: String) async throws(OwnerFailure) -> InstalledPlugin {
        guard let plugin = state.withLock({ $0.installed.first { $0.name == name } }) else { throw .notFound }
        return plugin
    }

    func typeInfo() async throws(OwnerFailure) -> [String: PluginTypeInfo] { state.withLock { $0.typeInfo } }

    func hostName(_ id: String) async throws(OwnerFailure) -> String {
        guard let name = state.withLock({ $0.hostNames[id] }) else { throw .notFound }
        return name
    }

    func release() async throws(PluginFailure) -> [ReleasePlugin] {
        if let failure = state.withLock({ $0.releaseFailure }) { throw failure }
        return state.withLock { $0.release }
    }

    func bundle(of plugin: ReleasePlugin) async throws(PluginFailure) -> ReleaseBundle {
        guard let bundle = state.withLock({ $0.bundles[plugin.name] }) else { throw .releaseUnreadable("missing") }
        return bundle
    }

    func install(_ bundle: Data) async throws(PluginFailure) -> PluginInstallAnswer {
        if let refusal = state.withLock({ $0.installRefusal }) { throw refusal }
        state.withLock { $0.sent.append(bundle) }
        return PluginInstallAnswer(name: "tickets", version: "0.0.14", outcome: .updated, fingerprint: "ab")
    }

    func remove(_ name: String) async throws(OwnerFailure) -> PluginRemoval {
        if let refusal = state.withLock({ $0.removeRefusal }) { throw refusal }
        state.withLock { $0.removals.append(name) }
        return state.withLock { $0.removalAnswer }
            ?? PluginRemoval(name: name, version: "1", removedConnector: false, keptTypes: [], keptEdgeTypes: [])
    }
}

private func installed(
    _ name: String, _ title: String, version: String, types: [String] = [], connector: Bool = false, host: String? = nil
) -> InstalledPlugin {
    InstalledPlugin(
        name: name, title: title, description: "\(title) plugin", mark: "lucide:ticket", maker: "Marfa", marfa: "0.0.90", version: version,
        types: types, edgeTypes: [], connector: connector ? .init(source: name, sourceName: title) : nil, host: host, fingerprint: "ff",
        installedAt: nil, installedBy: nil)
}

private func listed(_ name: String, _ title: String, version: String) -> ReleasePlugin {
    ReleasePlugin(
        name: name, title: title, description: "\(title) plugin", mark: "lucide:ticket", maker: "Marfa", marfa: PluginVersion("0.0.90")!,
        version: PluginVersion(version)!, sha256: String(repeating: "a", count: 64))
}

private func bundle(
    _ plugin: ReleasePlugin, types: [(id: String, guidance: Bool)] = [], connector: Bool = false
) -> ReleaseBundle {
    ReleaseBundle(
        plugin: plugin, bytes: Data("{\"name\":\"\(plugin.name)\"}".utf8),
        types: types.map { .init(id: $0.id, label: $0.id, description: nil, icon: nil, hasGuidance: $0.guidance) },
        edgeTypes: [],
        connector: connector ? .init(sourceName: plugin.title, kinds: []) : nil)
}

@MainActor
@Suite(.hangLimit) struct PluginsModelTests {
    private func model(
        _ calls: FakePluginCalls, items: [String: Int] = [:], file: PluginFileChoice? = nil, grants: Set<InstancePermission> = [.schemaWrite]
    ) -> PluginsModel {
        let access = PluginsAccess(ownItems: { items[$0] ?? 0 }, chooseBundle: { file })
        return PluginsModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { grants }), calls: calls, access: access)
    }

    @Test func aNewerReleaseIsAnUpdateAndAPluginNotInstalledIsAvailable() async {
        let calls = FakePluginCalls()
        let tickets = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13"), installed("rss", "RSS", version: "0.0.13")]
            $0.release = [tickets, listed("rss", "RSS", version: "0.0.13"), listed("github", "GitHub", version: "0.0.13")]
            $0.bundles["tickets"] = bundle(tickets, types: [(id: "common.ticket", guidance: false)])
        }
        let model = model(calls)
        await model.load()
        #expect(model.updates.map(\.id) == ["tickets"], "the same version is not an update")
        #expect(model.available.map(\.name) == ["github"])
    }

    @Test func aReleaseThatCannotBeReadLeavesTheInstalledPluginsAndSaysSo() async {
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13")]
            $0.releaseFailure = .releaseUnreadable("offline")
        }
        let model = model(calls)
        await model.load()
        #expect(model.installed.map(\.name) == ["tickets"])
        #expect(model.release == .unreadable(.releaseUnreadable("offline")))
        #expect(model.updates.isEmpty && model.available.isEmpty)
        #expect(model.failure == nil)
    }

    @Test func anUpdateSaysWhatItAddsAndNeverThatAnythingIsRemoved() async {
        let calls = FakePluginCalls()
        let spikes = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13", types: ["common.ticket"])]
            $0.release = [spikes]
            $0.bundles["tickets"] = bundle(spikes, types: [(id: "common.ticket", guidance: false), (id: "common.spike", guidance: false)])
        }
        let model = model(calls)
        await model.load()
        let update = try! #require(model.update(for: "tickets"))
        #expect(PluginWording.updateLine(adds: model.adds(update)) == "Adds the type common.spike. Nothing is removed.")
    }

    @Test func installingSendsTheBundleBytesUnchangedAndReadsThePluginsAgain() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        let released = bundle(entry, types: [(id: "common.ticket", guidance: false)])
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = released
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(calls.state.withLock { $0.sent } == [released.bytes], "the release's bytes, so the fingerprint is the release's digest")
        #expect(model.notice?.line == "Updated tickets to 0.0.14.")
        #expect(model.problem == nil)
    }

    @Test func aPluginWhoseTypesCarryGuidanceIsNotSentAndTheCommandIsGiven() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry, types: [(id: "common.ticket", guidance: true)])
        }
        let model = model(calls)
        await model.load()
        await model.readBundle(of: entry)
        #expect(model.heldCommand("tickets") == "marfa plugins install tickets")
        await model.install(entry)
        #expect(calls.state.withLock { $0.sent }.isEmpty, "Marfa refuses an app installing guidance, so none is sent")
    }

    @Test func aServerRefusalForGuidanceGivesTheSameCommand() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry, types: [(id: "common.ticket", guidance: false)])
            $0.installRefusal = .carriesGuidance
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(model.heldCommand("tickets") == "marfa plugins install tickets")
        #expect(model.problem == nil, "it is an answer, not a failure")
    }

    @Test func aNewerMarfaIsToldWithBothReleases() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry)
            $0.installRefusal = .needsNewerServer(marfa: "0.0.102", server: "0.0.101")
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        let problem = try! #require(model.problem)
        #expect(PluginWording.line(problem.failure, title: "Tickets") == "Tickets needs Marfa 0.0.102 or later. This server runs 0.0.101.")
    }

    @Test func aBundleFileIsSentAsItIsAndAGuidanceRefusalGivesTheCommandWithItsPath() async {
        let calls = FakePluginCalls()
        let bytes = Data("{ \"name\" : \"tickets\" }".utf8)
        let model = model(calls, file: .file(name: "tickets.plugin.json", path: "/Users/me/It's here/tickets.plugin.json", data: bytes))
        await model.installFile()
        #expect(calls.state.withLock { $0.sent } == [bytes], "the file's bytes, not a copy that was read and written again")

        calls.state.withLock { $0.installRefusal = .carriesGuidance }
        await model.installFile()
        #expect(model.commands[""] == "marfa plugins install '/Users/me/It'\\''s here/tickets.plugin.json'")
    }

    @Test func aFileThatCannotBeReadIsToldAndNothingIsSent() async {
        let calls = FakePluginCalls()
        let model = model(calls, file: .unreadable(name: "big.json"))
        await model.installFile()
        #expect(calls.state.withLock { $0.sent }.isEmpty)
        #expect(model.problem?.title == "Not Installed From a File")
    }

    @Test func removingAsksWithTheItemsEachTypeHoldsThenShowsWhatTheServerAnswered() async {
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [installed("github", "GitHub", version: "0.0.13", types: ["common.issue", "common.pull"], connector: true)]
            $0.typeInfo = ["common.issue": PluginTypeInfo(label: "Issue", plural: "Issues", parent: "core.task")]
            $0.removalAnswer = PluginRemoval(
                name: "github", version: "0.0.13", removedConnector: true, keptTypes: ["common.issue", "common.pull"], keptEdgeTypes: [])
        }
        let model = model(calls, items: ["common.issue": 1_840, "common.pull": 212])
        await model.load()
        model.askToRemove(model.installed[0])
        #expect(model.removal?.types.map(\.title) == ["Issues", "common.pull"])
        #expect(model.removal?.items == 2_052)
        await model.confirmRemoval()
        #expect(calls.state.withLock { $0.removals } == ["github"])
        #expect(model.installed.isEmpty)
        #expect(
            model.notice?.line
                == "Removed GitHub 0.0.13. Its connector stopped, and its settings and secrets are gone. Its 2 types and their items stay.")
    }

    @Test func aRemovalTheServerRefusesIsToldAndTheSheetIsGone() async {
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [installed("github", "GitHub", version: "0.0.13", connector: true)]
            $0.removeRefusal = .notPermitted("connectors.manage")
        }
        let model = model(calls)
        await model.load()
        model.askToRemove(model.installed[0])
        await model.confirmRemoval()
        #expect(model.removal == nil)
        #expect(model.problem?.failure == .owner(.notPermitted("connectors.manage")))
        #expect(model.installed.count == 1, "nothing is shown removed that was not")
    }

    @Test func aConnectorsHostIsNamedOnlyWhereTheSignInMayRead() async {
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [installed("rss", "RSS", version: "0.0.13", connector: true, host: "h1")]
            $0.hostNames = ["h1": "Castell Studio"]
        }
        let without = model(calls)
        await without.load()
        await without.open("rss")
        #expect(without.hostName(of: without.installed[0]) == nil)

        let with = model(calls, grants: [.schemaWrite, .connectorsManage])
        await with.load()
        await with.open("rss")
        #expect(with.hostName(of: with.installed[0]) == "Castell Studio")
    }

    @Test func removingIsToldInTheServersWordsForAPluginWithNothingKept() {
        let answer = PluginRemoval(name: "x", version: "1.0.0", removedConnector: false, keptTypes: [], keptEdgeTypes: [])
        #expect(PluginWording.removed(answer, title: "X") == "Removed X 1.0.0. Nothing it brought is left to keep.")
    }
}
