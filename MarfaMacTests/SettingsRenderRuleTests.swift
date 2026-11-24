import AppKit
import Foundation
import Marfa
import MarfaAPI
import SwiftUI
import Synchronization
import Testing
@testable import MarfaMac

/// The pages and sheets the button rule moves that `SettingsRenderTests` does not draw: the plugins and their removal sheet, the
/// pages of the server's upkeep, and the Connection page while a sign-in code waits. Skipped unless
/// `MARFA_MAC_SETTINGS_RENDERS` names a folder.
extension SettingsRenderTests {
    private func plugin(_ name: String, _ title: String, version: String, connector: Bool = false) -> InstalledPlugin {
        InstalledPlugin(
            name: name, title: title, description: "\(title) plugin", mark: "lucide:ticket", maker: "Marfa", marfa: "0.0.90", version: version,
            types: ["common.issue", "common.pull"], edgeTypes: [], connector: connector ? .init(source: name, sourceName: title) : nil, host: nil,
            fingerprint: "ff", installedAt: nil, installedBy: nil)
    }

    private func pluginHost() -> StubMarfaHost {
        let host = owner()
        let calls = FakePluginCalls()
        calls.state.withLock {
            $0.installed = [plugin("github", "GitHub", version: "0.0.13", connector: true), plugin("tickets", "Tickets", version: "0.0.14")]
        }
        host.pluginCalls = calls
        return host
    }

    @Test func plugins() async throws {
        try await page(.plugins, pluginHost(), named: "Plugins")
    }

    /// A destructive action alone at the sheet's leading edge, Cancel at the trailing edge.
    @Test func removingAPlugin() async throws {
        let host = pluginHost()
        let calls = try #require(host.pluginCalls as? FakePluginCalls)
        let model = PluginsModel(
            context: context(host), calls: calls, access: PluginsAccess(ownItems: { _ in 1_000 }, chooseBundle: { nil }))
        await model.load()
        model.askToRemove(model.installed[0])
        let removal = try #require(model.removal)
        try await page(.plugins, host, sheet: AnyView(PluginRemovalSheet(model: model, removal: removal)), named: "Plugins, removing one")
    }

    @Test func types() async throws { try await page(.types, owner(), named: "Types") }
    @Test func connectors() async throws { try await page(.connectors, owner(), named: "Connectors") }
    @Test func backups() async throws { try await page(.backups, owner(), named: "Backups") }
    @Test func updates() async throws { try await page(.updates, owner(), named: "Updates") }
    @Test func housekeeping() async throws { try await page(.housekeeping, owner(), named: "Housekeeping") }
    @Test func activity() async throws { try await page(.activity, owner(), named: "Activity") }
    @Test func monitoring() async throws { try await page(.monitoring, owner(), named: "Monitoring") }
    @Test func limits() async throws { try await page(.limits, owner(), named: "Limits") }
    @Test func startUp() async throws { try await page(.startUp, owner(), named: "Start-Up") }

    /// The sign-in code's row and the row that opens the page it is typed on, each with one button.
    @Test func connectionWaitingForACode() async throws {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("SettingsRenderRuleTests")
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let (never, hold) = AsyncStream<Void>.makeStream()
        defer { hold.finish() }
        bench.signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "https://marfa.castell.studio/device")!, completeAddress: nil,
            expiresAt: .now.addingTimeInterval(600), finish: { for await _ in never {}; try Task.checkCancellation(); return SignedIn() }))])
        libraries.marfaSettings.address = "https://marfa.castell.studio"
        let task = libraries.marfaSettings.start(.connect(usingCode: true))
        #expect(await eventually { libraries.marfaSettings.code != nil })
        let host = AppSettingsHost(libraries: libraries, launcher: SettingsLauncher())
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: ConnectionPage(settingsHost: host).environment(libraries).environment(libraries.host)),
            size: Self.size, named: "Connection, waiting for a code", settle: .milliseconds(800))
        libraries.marfaSettings.cancelSignIn()
        await task.value
    }
}
