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
    var ownerCalls: any OwnerCalls = FakeOwnerCalls()

    init(settings: InstanceSettingsModel) { instanceSettings = settings }

    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome {
        allowed.append(permissions)
        return .cancelled
    }

    func refreshGrants() async {}
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
    var sheet: AnyView?
    let detail: Detail

    var body: some View {
        windowContents
            .settingsSheet(isPresented: sheet != nil, dismiss: {}) { if let sheet { sheet } }
    }

    private var windowContents: some View {
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

    // MARK: The owner's pages (Account, Apps, Keys, Addresses)

    private static let days: (Int) -> Date = { Date.now.addingTimeInterval(-86_400 * Double($0)) }

    /// The server's answers as the boards draw them, in Castell Studio.
    private func owner(_ configure: (FakeOwnerCalls.State) -> Void = { _ in }) -> StubMarfaHost {
        let calls = FakeOwnerCalls()
        calls.state.withLock { state in
            state.profile = OwnerProfile(username: "mira", emailIsReadable: true, email: "mira@castell.studio")
            state.passkeys = [
                OwnerPasskey(id: "p1", name: "MacBook Pro", added: Self.days(49), lastUsed: .now),
                OwnerPasskey(id: "p2", name: "iPhone", added: Self.days(49), lastUsed: Self.days(2)),
            ]
            state.browsers = [
                BrowserSignIn(id: "b1", name: "Safari on macOS", added: Self.days(3), lastUsed: .now),
                BrowserSignIn(id: "b2", name: "Firefox on Windows", added: Self.days(19), lastUsed: Self.days(4)),
            ]
            state.names = ["core.task": "Tasks", "core.note": "Notes", "core.bookmark": "Bookmarks"]
            state.apps = [
                AppAccess(id: "g1", clientID: "mapp", kind: .app, name: "MAPP on MacBook Pro", origins: [], scopes: ["*:read", "*:write"], granted: Self.days(30), lastUsed: .now),
                AppAccess(id: "g2", clientID: "raycast", kind: .app, name: "Raycast", origins: [], scopes: ["core.task:read", "core.task:write", "core.note:read", "core.note:write", "core.bookmark:read"], granted: Self.days(50), lastUsed: Self.days(0)),
                AppAccess(id: "g3", clientID: "shortcuts", kind: .app, name: "Shortcuts", origins: [], scopes: ["core.task:read", "core.task:write"], granted: Self.days(40), lastUsed: Self.days(2)),
                AppAccess(id: "g4", clientID: "marfa-cli", kind: .commandLine, name: "marfa on Mac mini", origins: [], scopes: ["*:read", "*:write"], granted: Self.days(20), lastUsed: Self.days(3)),
            ]
            state.keys = [
                KeyInfo(id: "k1", label: "Backup script", source: "backup", permissions: ["backups.manage"], tier: .library, types: ["*": .read], created: Self.days(60), expires: .now.addingTimeInterval(86_400 * 3), lastUsed: .now, appClientID: nil),
                KeyInfo(id: "k2", label: "Lisbon zine importer", source: "lisbon-zine", permissions: [], tier: .feed, types: ["core.bookmark": .write, "core.note": .read], created: Self.days(19), expires: .now.addingTimeInterval(86_400 * 88), lastUsed: .now, appClientID: nil),
                KeyInfo(id: "k3", label: "GitHub connector", source: "github", permissions: [], tier: .feed, types: ["core.task": .write, "core.bookmark": .write], created: Self.days(40), expires: nil, lastUsed: .now.addingTimeInterval(-240), appClientID: nil),
                KeyInfo(id: "k4", label: "Raycast capture", source: "raycast", permissions: [], tier: .feed, types: ["core.note": .write], created: Self.days(30), expires: nil, lastUsed: .now, appClientID: "raycast"),
            ]
            state.settings = AddressSettings(
                instanceID: "i", signIn: "https://marfa.castell.studio",
                addresses: ["https://marfa.castell.studio", "http://castell-studio.local", "https://100.84.12.7"],
                websites: ["https://castell.studio"])
        }
        let host = StubMarfaHost(settings: InstanceSettingsModel { nil })
        host.ownerCalls = calls
        return host
    }

    private func page(_ page: MarfaSettingsPage, _ host: StubMarfaHost, subpage: SettingsSubpage? = nil, sheet: AnyView? = nil, named: String) async throws {
        try await SettingsRender.png(
            RenderedWindow(
                selection: .marfa(page), sheet: sheet,
                detail: MarfaSettingsPageView(page: page, host: host).environment(\.settingsSubpage, subpage)),
            size: Self.size, named: named, settle: .milliseconds(900))
    }

    private func context(_ host: StubMarfaHost) -> OwnerContext { OwnerContext(host: host) }

    @Test func account() async throws {
        try await page(.account, owner(), named: "Account")
    }

    @Test func accountChangingThePassword() async throws {
        let host = owner()
        let model = AccountModel(context: context(host))
        await model.load()
        await model.beginChangePassword()
        model.currentPassword = "old password"
        model.newPassword = "a new password"
        try await page(.account, host, sheet: AnyView(AccountSheet(model: model)), named: "Account, changing the password")
    }

    @Test func accountWithAWrongPassword() async throws {
        let host = owner()
        let model = AccountModel(context: context(host))
        await model.load()
        await model.beginChangePassword()
        model.currentPassword = "not the password"
        model.newPassword = "a new password"
        await model.changePassword()
        try await page(.account, host, sheet: AnyView(AccountSheet(model: model)), named: "Account, a wrong password refused")
    }

    @Test func accountWithoutSignInsManage() async throws {
        let host = owner()
        host.grants = []
        try await page(.account, host, named: "Account, without sign_ins.manage")
    }

    @Test func apps() async throws {
        try await page(.apps, owner(), named: "Apps")
    }

    @Test func anApp() async throws {
        try await page(.apps, owner(), subpage: SettingsSubpage(id: "app:g2", title: "Raycast"), named: "An app, Raycast")
    }

    @Test func appsNeedsAPermission() async throws {
        let host = owner()
        host.grants = [.configManage]
        try await page(.apps, host, named: "Apps, without grants.manage")
    }

    @Test func keys() async throws {
        try await page(.keys, owner(), named: "Keys")
    }

    @Test func keysWithoutKeysMint() async throws {
        let host = owner()
        host.grants = [.keysManage]
        try await page(.keys, host, named: "Keys, without keys.mint")
    }

    @Test func aKey() async throws {
        try await page(.keys, owner(), subpage: SettingsSubpage(id: "key:k2", title: "Lisbon zine importer"), named: "A key")
    }

    @Test func aKeyThatIsGone() async throws {
        try await page(.keys, owner(), subpage: SettingsSubpage(id: "key:gone", title: "Old key"), named: "A key that is gone")
    }

    @Test func newKey() async throws {
        let host = owner()
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        model.draft.exceptions["core.bookmark"] = .write
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "New Key")
    }

    @Test func newKeyRefused() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.fail("create", with: .refused("That source is taken by another key."))
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        await model.make()
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "New Key, refused")
    }

    @Test func theKeyShownOnce() async throws {
        let host = owner()
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        await model.make()
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "The key, shown once")
    }

    @Test func addresses() async throws {
        try await page(.addresses, owner(), named: "Addresses")
    }

    @Test func addressesAddingOne() async throws {
        let host = owner()
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        try await page(.addresses, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Addresses, adding one")
    }

    @Test func addressesAddingOneTheServerRefuses() async throws {
        let host = owner()
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.addAddress)
        model.input = "https://castell.studio/path"
        await model.check()
        try await page(.addresses, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Addresses, an address refused")
    }

    @Test func addressesChangingTheSignInAddress() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock {
            $0.reach = .answers
            $0.requiresConfirmation = true
            $0.consequences = [
                .init(code: "browser_sessions_end", sentence: "Every browser signs in again at the new address. 2 are signed in.", count: 2),
                .init(code: "passkeys_unusable", sentence: "A passkey works only where it was added. Add them again.", count: 2),
                .init(code: "apps_sign_in_again", sentence: "MAPP included. Each signs in at the new address.", count: 4),
            ]
        }
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        try await page(.addresses, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Addresses, changing the sign-in address")
    }
}
