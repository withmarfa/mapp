import AppKit
import Foundation
import Marfa
import MarfaAPI
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import MAPP

/// A host for the Marfa's pages with canned answers, which shows they need nothing of MAPP but the protocol.
@Observable @MainActor final class StubMarfaHost: MarfaSettingsHost {
    var serverName = "Castell Studio"
    var serverAddress: String? = "marfa.castell.studio"
    var connection = MarfaSettingsConnection.connected
    var grants: Set<InstancePermission> = Set(InstancePermission.allCases)
    var isAllowingMore = false
    var instanceSettings: InstanceSettingsModel
    var deletedItems: [MarfaDeletedItem] = []
    var deletedCount = 0
    var deletedRetentionDays: Int? = 60
    var canDeletePermanently = true
    var openInApp: ((String) -> Void)? { nil }
    var allowed: [Set<InstancePermission>] = []

    init(settings: InstanceSettingsModel) { instanceSettings = settings }

    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome {
        allowed.append(permissions)
        return .cancelled
    }

    func tryAgain() {}
    func showConnection() {}
    func client() throws -> Client { throw MarfaServerCalls.Ending.keyRefused }
    func restoreDeleted(_ ids: Set<String>) { deletedItems.removeAll { ids.contains($0.id) } }
    func deleteDeletedPermanently(_ ids: Set<String>) {}
    func emptyDeleted() {}
}

/// The window as the boards draw it, for a pull request's pictures: the sidebar and the page, with a strip standing for
/// the toolbar. The system's Back and Forward pill and title belong to the real window's toolbar, which an offscreen draw
/// has no window to give, so the strip only marks where they sit and is not their size or look; the pictures taken from
/// the running app show them as the system draws them.
private struct RenderedWindow<Detail: View>: View {
    let selection: SettingsPage
    var search = ""
    let detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: .constant(selection), search: .constant(search))
                .frame(width: SettingsTokens.Metric.sidebarWidth)
                .background(Color(white: 0.93))
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.left").foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    Text(selection.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(SettingsTokens.page)
                detail
            }
        }
        .interfaceTextStyle()
    }
}

/// Draws each page this piece moves into the window, and the states of a page the person may not open, to PNGs for the
/// pull request. Skipped unless `MAPP_SETTINGS_RENDERS` names a folder.
@Suite(.enabled(if: SettingsRender.isRequested), .serialized, .hangLimit)
@MainActor struct SettingsRenderTests {
    private static let size = CGSize(width: SettingsTokens.Metric.windowWidth, height: SettingsTokens.Metric.windowHeight)

    private func stub(_ configure: (StubMarfaHost) -> Void = { _ in }) async -> StubMarfaHost {
        let source = FakeInstanceConfig([.name: .text("Castell Studio"), .trashRetentionDays: .number(60)])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        configure(host)
        return host
    }

    private func connected() async throws -> (Libraries, HostBench) {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "SettingsRenderTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        try await libraries.host.connect(address: "https://marfa.castell.studio", key: "k")
        bench.servers.last?.state.set(.online)
        #expect(await eventually { libraries.host.state == .online && libraries.host.grantsRead })
        return (libraries, bench)
    }

    @Test func general() async throws {
        try await SettingsRender.png(RenderedWindow(selection: .general, detail: GeneralPage()), size: Self.size, named: "General")
    }

    @Test func appearance() async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage()), size: Self.size, named: "Appearance")
    }

    /// The whole page, taller than the window, in place of the board's scrolled view.
    @Test func appearanceWhole() async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage()),
            size: CGSize(width: Self.size.width, height: 1_300), named: "Appearance, whole page")
    }

    /// A font chosen once and uninstalled since, and a color of the person's own.
    @Test func appearanceWithAMissingFontAndACustomAccent() async throws {
        let defaults = UserDefaults.standard
        let keys = [AppearanceKey.textFont, AppearanceKey.accent, AppearanceKey.theme]
        defer { for key in keys { defaults.removeObject(forKey: key) } }
        defaults.set("Uninstalled Sans", forKey: AppearanceKey.textFont)
        defaults.set(AccentChoice.custom("#B4468C").rawValue, forKey: AppearanceKey.accent)
        defaults.set(AppTheme.dark.rawValue, forKey: AppearanceKey.theme)
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage()),
            size: CGSize(width: Self.size.width, height: 1_300), named: "Appearance, a missing font and a custom accent")
    }

    private func keyboard(_ prepare: (KeyboardPageModel) -> Void = { _ in }) async throws -> (SettingsPage, KeyboardPage) {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "SettingsRenderTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let model = KeyboardPageModel(bindings: libraries.shortcuts, anyApp: libraries.anyAppShortcuts)
        prepare(model)
        return (.keyboard, KeyboardPage(libraries: libraries, model: model))
    }

    @Test func keyboardRecording() async throws {
        let (page, detail) = try await keyboard { model in
            model.bindings.set(nil, for: .addTag)
            model.startRecording(.menu(.quickLook))
        }
        try await SettingsRender.png(RenderedWindow(selection: page, detail: detail), size: Self.size, named: "Keyboard, recording")
    }

    @Test func keyboardAnyApp() async throws {
        let (page, detail) = try await keyboard { model in
            model.anyApp.set(Shortcut(key: " ", modifiers: [.control, .option], keyCode: 49), for: .commandPalette)
        }
        try await SettingsRender.png(RenderedWindow(selection: page, detail: detail), size: Self.size, named: "Keyboard, in any app")
    }

    @Test func keyboardAnyAppRefusesOptionAlone() async throws {
        let (page, detail) = try await keyboard { model in
            model.startRecording(.anyApp(.searchItems))
            model.record(Shortcut(key: "k", modifiers: .option, keyCode: 40))
        }
        try await SettingsRender.png(RenderedWindow(selection: page, detail: detail), size: Self.size, named: "Keyboard, Option alone refused")
    }

    @Test func keyboardTakenKey() async throws {
        let (page, detail) = try await keyboard { model in
            model.search = "tag"
            model.startRecording(.menu(.addTag))
            model.record(Shortcut(key: "k", modifiers: .command, keyCode: 40))
        }
        try await SettingsRender.png(RenderedWindow(selection: page, search: "", detail: detail), size: Self.size, named: "Keyboard, taken")
    }

    @Test func keyboardSearchingByKeys() async throws {
        let (page, detail) = try await keyboard { model in
            model.searchesByKeys = true
            model.pressed = Shortcut(key: "k", modifiers: .command, keyCode: 40)
        }
        try await SettingsRender.png(RenderedWindow(selection: page, detail: detail), size: Self.size, named: "Keyboard, by keys")
    }

    @Test func lists() async throws {
        try await SettingsRender.png(RenderedWindow(selection: .lists, detail: ListsPage()), size: Self.size, named: "Lists")
    }

    @Test func editor() async throws {
        try await SettingsRender.png(RenderedWindow(selection: .editor, detail: EditorPage()), size: Self.size, named: "Editor")
    }

    @Test func connectionConnected() async throws {
        let (libraries, bench) = try await connected()
        _ = bench
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: ConnectionPage().environment(libraries).environment(libraries.host)),
            size: Self.size, named: "Connection")
    }

    @Test func connectionNotConnected() async throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "SettingsRenderTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: ConnectionPage().environment(libraries).environment(libraries.host)),
            size: Self.size, named: "Connection, not connected")
    }

    @Test func overview() async throws {
        let host = await stub()
        try await SettingsRender.png(
            RenderedWindow(selection: .overview, detail: MarfaSettingsPageView(page: .overview, host: host)), size: Self.size,
            named: "Overview")
    }

    @Test func overviewWithARefusedWrite() async throws {
        let source = FakeInstanceConfig([.name: .text("Castell Studio"), .versionRecentDays: .number(30)])
        source.updateFailure.withLock { $0 = .refused("That name is already taken on this server.") }
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        // The page reads the server's settings as it opens, so the refused save is made once that read is done.
        let refused = Task {
            try await Task.sleep(for: .milliseconds(300))
            settings.draft[.name] = "Harbour Joinery"
            await settings.save()
        }
        try await SettingsRender.png(
            RenderedWindow(selection: .overview, detail: MarfaSettingsPageView(page: .overview, host: host)), size: Self.size,
            named: "Overview, a write the server refused", settle: .milliseconds(1_000))
        try await refused.value
    }

    @Test func recentlyDeleted() async throws {
        let titles = [
            "Order oak for the Harbour Joinery worktops", "Lisbon zine: first cover ideas", "Kiln hire in East Sussex",
            "“The joint is the detail that tells you who made it”", "Lewes Trust site walk", "Allotment shed: felt roof quote",
            "Tom Hartley", "Oak species and their grain",
        ]
        let host = await stub {
            $0.deletedItems = titles.enumerated().map { index, title in
                MarfaDeletedItem(id: "item-\(index)", title: title, deleted: Date.now.addingTimeInterval(-Double(index) * 86_400 * 2))
            }
            $0.deletedCount = 1_204
        }
        try await SettingsRender.png(
            RenderedWindow(selection: .recentlyDeleted, detail: MarfaSettingsPageView(page: .recentlyDeleted, host: host)),
            size: Self.size, named: "Recently Deleted")
    }

    @Test func needsAPermission() async throws {
        let host = await stub { $0.grants = [] }
        try await SettingsRender.png(
            RenderedWindow(selection: .recentlyDeleted, detail: MarfaSettingsPageView(page: .recentlyDeleted, host: host)),
            size: Self.size, named: "A page MAPP may not open")
    }

    @Test func notAnswering() async throws {
        let host = await stub { $0.connection = .notAnswering(lastAnswered: .now.addingTimeInterval(-600)) }
        try await SettingsRender.png(
            RenderedWindow(selection: .overview, detail: MarfaSettingsPageView(page: .overview, host: host)), size: Self.size,
            named: "Castell Studio not answering")
    }

    @Test func sidebarWithASearchTyped() async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .editor, search: "spell", detail: EditorPage()), size: Self.size, named: "Sidebar, search typed")
    }

    @Test func sidebarSearchWithNoMatch() async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .editor, search: "zzzz", detail: EditorPage()), size: Self.size, named: "Sidebar, search with no match")
    }
}
