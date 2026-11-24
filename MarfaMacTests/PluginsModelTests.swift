import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MarfaMac

/// A server and a release with every answer scripted.
/// Holds a scripted answer until the test lets it go.
actor ReleaseGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

final class FakePluginCalls: PluginCalls, @unchecked Sendable {
    let releaseName = "withmarfa/plugins"
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
        var releaseGate: ReleaseGate?
        var bundleFailure: PluginFailure?
        /// When set, a bundle is refused unless the release lists this version and digest, as `ClientPluginCalls` does.
        var checksListedRelease = false
        var bundleAsks: [ReleasePlugin] = []
        /// Clears `releaseFailure` after it is thrown once, so a later read can succeed.
        var consumeReleaseFailure = false
        var installedFailure: OwnerFailure?
        /// Makes the next read of the installed plugins fail once an install has been taken.
        var failReadAfterInstall = false
    }

    let state = Mutex(State())

    func installed() async throws(OwnerFailure) -> [InstalledPlugin] {
        if let failure = state.withLock({ $0.installedFailure }) { throw failure }
        return state.withLock { $0.installed }
    }

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
        if let gate = state.withLock({ $0.releaseGate }) { await gate.wait() }
        let failure = state.withLock { state -> PluginFailure? in
            let failure = state.releaseFailure
            if state.consumeReleaseFailure { state.releaseFailure = nil }
            return failure
        }
        if let failure { throw failure }
        return state.withLock { $0.release }
    }

    func bundle(of plugin: ReleasePlugin) async throws(PluginFailure) -> ReleaseBundle {
        let snapshot = state.withLock { state -> (PluginFailure?, Bool, [ReleasePlugin], ReleaseBundle?) in
            state.bundleAsks.append(plugin)
            return (state.bundleFailure, state.checksListedRelease, state.release, state.bundles[plugin.name])
        }
        if let failure = snapshot.0 { throw failure }
        if snapshot.1 {
            guard let fresh = snapshot.2.first(where: { $0.name == plugin.name }), fresh.version == plugin.version,
                fresh.sha256.lowercased() == plugin.sha256.lowercased()
            else { throw .releaseChanged }
        }
        guard let bundle = snapshot.3 else { throw .releaseUnreadable("missing") }
        return bundle
    }

    func install(_ bundle: Data) async throws(PluginFailure) -> PluginInstallAnswer {
        if let refusal = state.withLock({ $0.installRefusal }) { throw refusal }
        state.withLock {
            $0.sent.append(bundle)
            if $0.failReadAfterInstall { $0.installedFailure = .unreachable }
        }
        return PluginInstallAnswer(name: "tickets", version: "0.0.14", outcome: .updated, fingerprint: "ab")
    }

    func remove(_ name: String) async throws(OwnerFailure) -> PluginRemoval {
        if let refusal = state.withLock({ $0.removeRefusal }) { throw refusal }
        state.withLock { $0.removals.append(name) }
        return state.withLock { $0.removalAnswer }
            ?? PluginRemoval(name: name, version: "1", removedConnector: false, keptTypes: [], keptEdgeTypes: [], keptConnector: nil)
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

private func bundle(_ plugin: ReleasePlugin, types: [String] = [], connector: Bool = false) -> ReleaseBundle {
    ReleaseBundle(
        plugin: plugin, bytes: Data("{\"name\":\"\(plugin.name)\"}".utf8),
        types: types.map { .init(id: $0, label: $0, description: nil, icon: nil) },
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

    @Test func anUpdateSaysWhatItAddsAndNeverThatAnythingIsRemoved() async {
        let calls = FakePluginCalls()
        let spikes = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13", types: ["common.ticket"])]
            $0.release = [spikes]
            $0.bundles["tickets"] = bundle(spikes, types: ["common.ticket", "common.spike"])
        }
        let model = model(calls)
        await model.load()
        let update = try! #require(model.update(for: "tickets"))
        #expect(PluginWording.updateLine(adds: model.adds(update)) == "Adds the type common.spike. Nothing is removed.")
    }

    @Test func installingSendsTheBundleBytesUnchangedAndReadsThePluginsAgain() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        let released = bundle(entry, types: ["common.ticket"])
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

    @Test func aPluginWhoseTypesCarryGuidanceIsSentLikeAnyOtherAndNoCommandIsGiven() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        let released = bundle(entry, types: ["common.ticket"])
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = released
        }
        let model = model(calls)
        await model.load()
        await model.readBundle(of: entry)
        #expect(model.heldCommand("tickets") == nil, "the server's answer decides, so nothing is held before it answers")
        await model.install(entry)
        #expect(calls.state.withLock { $0.sent } == [released.bytes], "sent once, as the server asked for the owner's sign-in in place")
        #expect(model.heldCommand("tickets") == nil)
        #expect(model.problem == nil)
    }

    @Test func aServerRefusalForGuidanceGivesTheCommandAndNoFailure() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry, types: ["common.ticket"])
            $0.installRefusal = .carriesGuidance
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(model.heldCommand("tickets") == "marfa plugins install tickets")
        #expect(model.problem == nil, "it is an answer, not a failure")
        #expect(model.notice == nil)
    }

    @Test func aSignInSheetTheOwnerClosesChangesNothingAndSaysNothing() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry, types: ["common.ticket"])
            $0.installRefusal = .canceled
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(model.problem == nil && model.notice == nil && model.heldCommand("tickets") == nil)
        #expect(calls.state.withLock { $0.sent }.isEmpty)
        #expect(!model.isWorking("tickets"), "Install is offered again")
    }

    @Test func anOwnerWhoDeclinesTheSignInIsToldItWasNotInstalled() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry, types: ["common.ticket"])
            $0.installRefusal = .owner(.notConfirmed)
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(model.problem?.title == "Not Installed")
        #expect(model.problem?.failure == .owner(.notConfirmed))
    }

    @Test func theClosedSheetAndTheDeclineAreToldApartWhereTheServerAnswers() {
        #expect(ClientPluginCalls.refusal(.canceled(message: "closed")) == .canceled)
        let declined = MarfaError.forbidden(code: "access_denied", message: "no", server: nil)
        #expect(ClientPluginCalls.refusal(declined) == .owner(.notConfirmed))
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

    @Test func aFileThatCannotBeReadIsToldAndNothingIsSent() async throws {
        let calls = FakePluginCalls()
        let model = model(calls, file: .unreadable(name: "big.json"))
        await model.installFile()
        #expect(calls.state.withLock { $0.sent }.isEmpty)
        let problem = try #require(model.problem)
        #expect(problem.title == "Not Installed From a File")
        #expect(problem.failure == .bundleFileUnreadable(name: "big.json"))
        #expect(PluginWording.line(problem.failure) == "The app couldn’t read “big.json” on this Mac. Choose another plugin bundle.")
    }

    @Test func removingAsksWithTheItemsEachTypeHoldsThenShowsWhatTheServerAnswered() async {
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [installed("github", "GitHub", version: "0.0.13", types: ["common.issue", "common.pull"], connector: true)]
            $0.typeInfo = ["common.issue": PluginTypeInfo(label: "Issue", plural: "Issues", parent: "core.task")]
            $0.removalAnswer = PluginRemoval(
                name: "github", version: "0.0.13", removedConnector: true, keptTypes: ["common.issue", "common.pull"], keptEdgeTypes: [],
                keptConnector: .init(source: "github", state: true, agreements: 3))
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
                == "Removed GitHub 0.0.13. Its connector stopped, and its settings, secrets and saved mapping are gone, with any rewrite it asked for. Its source github keeps its state and 3 agreements. Its 2 types and their items stay.")
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

    @Test func readingTheReleaseAgainDropsEveryBundleReadBefore() async {
        let calls = FakePluginCalls()
        let first = listed("tickets", "Tickets", version: "0.0.14")
        let second = listed("tickets", "Tickets", version: "0.0.15")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13")]
            $0.release = [first]
            $0.bundles["tickets"] = bundle(first)
        }
        let model = model(calls)
        await model.load()
        #expect(model.bundle("tickets")?.plugin.version.description == "0.0.14")
        calls.state.withLock {
            $0.release = [second]
            $0.bundles["tickets"] = bundle(second)
        }
        await model.readRelease()
        #expect(model.bundle("tickets")?.plugin.version.description == "0.0.15", "Try Again never keeps an older version's bundle")
    }

    @Test func aBundleIsSentOnlyWhereTheFreshIndexListsTheVersionAndDigestShown() throws {
        let shown = listed("tickets", "Tickets", version: "0.0.14")
        #expect(throws: Never.self) { try ClientPluginCalls.confirm(shown, in: [shown]) }
        let newer = listed("tickets", "Tickets", version: "0.0.15")
        #expect(throws: PluginFailure.releaseChanged) { try ClientPluginCalls.confirm(shown, in: [newer]) }
        var other = shown
        other.sha256 = String(repeating: "b", count: 64)
        #expect(throws: PluginFailure.releaseChanged) { try ClientPluginCalls.confirm(shown, in: [other]) }
        #expect(throws: PluginFailure.releaseChanged, "a plugin the release stopped listing") { try ClientPluginCalls.confirm(shown, in: []) }
    }

    @Test func tryAgainReadsTheBundleTheNewReleaseLists() async {
        let calls = FakePluginCalls()
        let shown = listed("hello", "Hello", version: "0.0.14")
        let fresh = listed("hello", "Hello", version: "0.0.15")
        calls.state.withLock { $0.release = [shown] }
        let model = model(calls)
        await model.load()
        calls.state.withLock {
            $0.release = [fresh]
            $0.bundles["hello"] = bundle(fresh)
            $0.checksListedRelease = true
            $0.bundleAsks = []
        }
        await model.readBundle(of: shown)
        #expect(model.bundles["hello"] == .failed(.releaseChanged), "the fresh index refuses the version the page still holds")
        calls.state.withLock { $0.bundleAsks = [] }
        await model.readAgain("hello")
        #expect(model.bundle("hello")?.plugin.version.description == "0.0.15")
        #expect(calls.state.withLock { $0.bundleAsks } == [fresh], "Try Again reads the entry the new release lists, not the one it refused")
    }

    @Test func tryAgainShowsAPluginTheReleaseNoLongerLists() async {
        let calls = FakePluginCalls()
        let shown = listed("hello", "Hello", version: "0.0.14")
        calls.state.withLock {
            $0.release = [shown]
            $0.checksListedRelease = true
        }
        let model = model(calls)
        await model.load()
        calls.state.withLock {
            $0.release = []
            $0.bundleAsks = []
        }
        await model.readAgain("hello")
        #expect(model.entry("hello") == nil)
        #expect(model.notice?.line == "The release no longer lists Hello.")
        #expect(calls.state.withLock { $0.bundleAsks }.isEmpty, "no bundle is read for a plugin the release dropped")
    }

    @Test func aCancelledReleaseReadPutsBackTheReleaseAndItsBundles() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13")]
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry)
        }
        let model = model(calls)
        await model.load()
        #expect(model.bundle("tickets")?.plugin.version.description == "0.0.14")
        calls.state.withLock { $0.releaseFailure = .canceled }
        await model.readRelease()
        #expect(model.entries.map(\.name) == ["tickets"])
        #expect(model.bundle("tickets")?.plugin.version.description == "0.0.14", "a cancelled read puts back the bundles it held")
        #expect(model.release != .reading)
    }

    @Test func aNewerLoadReadsAfterOneThatWasCancelled() async {
        let calls = FakePluginCalls()
        let gate = ReleaseGate()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.installed = [installed("tickets", "Tickets", version: "0.0.13")]
            $0.release = [entry]
            $0.releaseGate = gate
            $0.releaseFailure = .canceled
            $0.consumeReleaseFailure = true
        }
        let model = model(calls)
        let first = Task { await model.load() }
        #expect(await eventually { model.isLoading })
        let started = Mutex(false)
        let finished = Mutex(false)
        let second = Task {
            started.withLock { $0 = true }
            await model.load()
            finished.withLock { $0 = true }
        }
        #expect(await eventually { started.withLock { $0 } })
        let returnedEarly = finished.withLock { $0 }
        await gate.open()
        await first.value
        await second.value
        #expect(!returnedEarly, "a load that finds one running waits, then reads, rather than returning")
        #expect(model.entries.map(\.name) == ["tickets"])
    }

    @Test func aFileInstalledAfterAnotherThatNeededTheCommandLineDropsThatCommand() async {
        let calls = FakePluginCalls()
        let model = model(calls, file: .file(name: "a.json", path: "/tmp/a.json", data: Data("{}".utf8)))
        calls.state.withLock { $0.installRefusal = .carriesGuidance }
        await model.installFile()
        #expect(model.commands[""] != nil)
        calls.state.withLock { $0.installRefusal = nil }
        await model.installFile()
        #expect(model.commands[""] == nil, "the first file's command is not the second file's")
    }

    @Test func anInstallWhoseListCannotBeReadKeepsItsBundleAndSaysSo() async {
        let calls = FakePluginCalls()
        let entry = listed("tickets", "Tickets", version: "0.0.14")
        calls.state.withLock {
            $0.release = [entry]
            $0.bundles["tickets"] = bundle(entry)
            $0.failReadAfterInstall = true
        }
        let model = model(calls)
        await model.load()
        await model.install(entry)
        #expect(model.bundle("tickets") != nil, "the page that shows it keeps what it reads from, so it does not wait for ever")
        #expect(model.notice?.line.contains("The list of plugins couldn’t be read") == true)
    }
}
