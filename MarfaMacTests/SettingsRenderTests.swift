import AppKit
import Foundation
import Marfa
import MarfaAPI
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import MarfaMac

/// A host for the Marfa's pages with canned answers, which shows they need nothing of the app but the protocol.
@Observable @MainActor final class StubMarfaHost: MarfaSettingsHost {
    var serverName = "Castell Studio"
    var serverAddress: String? = "marfa.castell.studio"
    var connection = MarfaSettingsConnection.connected
    var grants: Set<InstancePermission> = Set(InstancePermission.allCases)
    /// A scope beyond the owner's permissions the sign-in lacks.
    var lacksScope = false
    var lacksAsked: Bool { !Set(InstancePermission.allCases).isSubset(of: grants) || lacksScope }
    func holds(_ scope: String) -> Bool { !lacksScope }
    var isAllowingMore = false
    var instanceSettings: InstanceSettingsModel
    let ownerDrafts = OwnerDrafts()
    var deletedItems: [MarfaDeletedItem] = []
    var deletedCount = 0
    var deletedRetentionDays: Int? = 60
    var canDeletePermanently = true
    var openInApp: ((String) -> Void)?
    var ownAppVendor: String? { "app.marfa-mac" }

    var webSignInReturn: String { "com.withmarfa.marfa.test:/signed-in" }
    /// What the web sign-in sheet answers, and the addresses it was shown.
    var webSignInAnswer = true
    var webSignIns: [URL] = []
    func showWebSignIn(at address: URL) async -> Bool {
        webSignIns.append(address)
        return webSignInAnswer
    }
    var allowed: [Set<InstancePermission>] = []
    var ownerCalls: any OwnerCalls = FakeOwnerCalls()
    var instanceCalls: any InstanceCalls = FakeInstanceCalls()
    var folderCalls: any FolderCalls = FakeFolderCalls()
    var overview: AccountOverview
    var health: ServerHealthModel
    var updates: UpdatesModel
    var shown: [MarfaSettingsPage] = []
    var shownSubpages: [SettingsSubpage?] = []
    var sources: [MarfaSourceRow] = []
    var canChangeSources = true
    var sourceChanges: [(code: String, change: MarfaSourceChange)] = []
    var markSets = [MarfaMarkSet(id: "lucide", title: "Lucide")]
    /// The icon of each type a render names, by type id.
    var typeIcons: [String: String] = ["core.bookmark": "lucide:bookmark", "core.note": "lucide:file-text"]

    init(settings: InstanceSettingsModel) {
        instanceSettings = settings
        let context = OwnerContext(calls: FakeOwnerCalls(), grants: { [] })
        let reader = ServerHealthModel(context: context)
        health = reader
        overview = AccountOverview(context: context)
        updates = UpdatesModel(context: context)
    }

    /// Binds the Overview and the health reader to the host's own calls and grants, as the app does.
    func bindOverview() {
        health = ServerHealthModel(context: OwnerContext(host: self))
        overview = AccountOverview(context: OwnerContext(host: self))
        updates = UpdatesModel(context: OwnerContext(host: self))
    }

    func show(_ page: MarfaSettingsPage, subpage: SettingsSubpage?) {
        shown.append(page)
        shownSubpages.append(subpage)
    }
    func refreshSources() async {}

    func changeSource(_ code: String, _ change: MarfaSourceChange) async -> OwnerFailure? {
        sourceChanges.append((code, change))
        return nil
    }

    func marks(matching query: String, in set: MarfaMarkSet) -> [String] { ["lucide:inbox", "lucide:rss", "lucide:book-open"] }
    func markGlyph(_ id: String) -> AnyView { AnyView(Image(systemName: "tray")) }
    func markTitle(_ id: String) -> String { id }
    func typeMark(for pattern: String) -> AnyView { AnyView(TypeTile(icon: typeIcons[pattern], size: .side)) }
    var typeCalls: any TypeCalls = FakeTypeCalls()
    func largeTypeMark(for id: String) -> AnyView { AnyView(TypeTile(icon: typeIcons[id], size: .large)) }
    func itemCount(ofType id: String) -> Int { 0 }
    func typePlural(of id: String) -> String? { nil }
    func typeIcon(of id: String) -> String? { typeIcons[id] }
    func changeTypeIcon(_ icon: String?, ofType id: String) async -> OwnerFailure? {
        typeIcons[id] = icon
        return nil
    }

    var pluginCalls: any PluginCalls = FakePluginCalls()
    func chooseBundleFile() async -> PluginFileChoice? { nil }

    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome {
        allowed.append(permissions)
        return .cancelled
    }

    func refreshGrants() async {}
    func tryAgain() {}
    func showConnection() {}
    private(set) var signOutRequests = 0
    func requestSignOut() { signOutRequests += 1 }
    func client() throws -> Client { throw MarfaServerCalls.Ending.keyRefused }
    func restoreDeleted(_ ids: Set<String>) { deletedItems.removeAll { ids.contains($0.id) } }
    func deleteDeletedPermanently(_ ids: Set<String>) {}
    func emptyDeleted() {}
}

/// Downloaded files with canned answers.
nonisolated struct FakeDownloads: DownloadedFiles {
    var state: DownloadedFileState
    func read() async throws -> DownloadedFileState { state }
    func setBudget(_ budget: DownloadBudget) async throws {}
    func removeDownloadedFiles() async throws {}
}

/// The window as the boards draw it, for a pull request's pictures: the sidebar and the page, with a strip standing for
/// the toolbar. The system's Back and Forward pill and title belong to the real window's toolbar, which an offscreen draw
/// has no window to give, so the strip only marks where they sit and is not their size or look; the pictures taken from
/// the running app show them as the system draws them.
struct RenderedWindow<Detail: View>: View {
    @Environment(\.colorScheme) private var scheme
    let selection: SettingsPage
    var search = ""
    var sheet: AnyView?
    /// The number of problems on Account.
    var badge: Int?
    let detail: Detail

    var body: some View {
        windowContents
            .settingsSheet(isPresented: sheet != nil, dismiss: {}) { if let sheet { sheet } }
    }

    private var windowContents: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: .constant(selection), search: .constant(search),
                badges: { page in page == .account ? badge : nil })
                .frame(width: SettingsTokens.Metric.sidebarWidth)
                .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(white: 0.93))
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
/// pull request. Skipped unless `MARFA_MAC_SETTINGS_RENDERS` names a folder.
@Suite(.enabled(if: SettingsRender.isRequested), .serialized, .hangLimit)
@MainActor struct SettingsRenderTests {
    static let size = CGSize(width: SettingsTokens.Metric.windowWidth, height: SettingsTokens.Metric.windowHeight)

    func stub(_ configure: (StubMarfaHost) -> Void = { _ in }) async -> StubMarfaHost {
        let source = FakeInstanceConfig([.name: .text("Castell Studio"), .trashRetentionDays: .number(60)])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        configure(host)
        return host
    }

    func connected() async throws -> (Libraries, HostBench) {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        try await libraries.host.connect(address: "https://marfa.castell.studio", key: "k")
        bench.servers.last?.state.set(.online)
        #expect(await eventually { libraries.host.state == .online && libraries.host.grantsRead })
        return (libraries, bench)
    }

    @Test(arguments: [ColorScheme.light, .dark], [13, 24])
    func general(appearance: ColorScheme, textSize: Int) async throws {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("GeneralRender")
        let libraries = Libraries(
            host: bench.host(), defaults: defaults, handOverPages: { $0(true) },
            syncsPreferences: true, defaultsDomain: defaults.suite)
        try await libraries.host.connect(address: "https://marfa.castell.studio", key: "k")
        libraries.preferences.attach(FakePreferencesCopy(), library: "marfa:castell-studio", name: { "Castell Studio" })
        await libraries.preferences.flush()
        try libraries.preferences.saveRestorePoint(.reset)
        let updater = AppUpdater(defaults: defaults, startingUpdater: false)
        try await SettingsRender.png(
            RenderedWindow(selection: .general, detail: GeneralPage(libraries: libraries))
                .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
                .environment(\.appUpdater, updater)
                .defaultAppStorage(defaults),
            size: CGSize(width: textSize == 24 ? SettingsTokens.Metric.windowMinWidth : Self.size.width,
                         height: textSize == 24 ? 2_450 : 1_420),
            named: "General, \(appearance), \(textSize) pt", appearance: appearance)
    }

    @Test(arguments: [11, 24])
    func generalAtTheTextSizeLimits(textSize: Int) async throws {
        let (libraries, _) = try await connected()
        let defaults = ThrowawayDefaults.make("SettingsRenderTextSize")
        defaults.set(textSize, forKey: InterfaceKey.textSize)
        try await SettingsRender.png(
            RenderedWindow(selection: .general, detail: GeneralPage(libraries: libraries))
                .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
                .defaultAppStorage(defaults),
            size: Self.size, named: "General, text size \(textSize)")
    }

    @Test func appearance() async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage()), size: Self.size, named: "Appearance")
    }

    /// The whole page, taller than the window, in place of the board's scrolled view.
    @Test(arguments: [ColorScheme.light, .dark], [13, 24])
    func appearanceWhole(appearance: ColorScheme, textSize: Int) async throws {
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        defaults.set(textSize, forKey: InterfaceKey.textSize)
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage())
                .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
                .defaultAppStorage(defaults),
            size: CGSize(width: Self.size.width, height: textSize == 24 ? 2_400 : 1_400),
            named: "Appearance, \(appearance), \(textSize) pt", appearance: appearance)
    }

    @Test func appearanceWithACustomAccent() async throws {
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        defaults.set(AccentChoice.custom("#B4468C").rawValue, forKey: AppearanceKey.accent)
        defaults.set(AppTheme.dark.rawValue, forKey: AppearanceKey.theme)
        try await SettingsRender.png(
            RenderedWindow(selection: .appearance, detail: AppearancePage().defaultAppStorage(defaults)),
            size: CGSize(width: Self.size.width, height: 1_300), named: "Appearance, a custom accent")
    }

    private func keyboard(_ prepare: (KeyboardPageModel) -> Void = { _ in }) async throws -> (SettingsPage, KeyboardPage) {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
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

    @Test func appSettingsBoards() async throws {
        let (libraries, _) = try await connected()
        let library = FakeItemLibrary(items: [])
        library.catalogue = MarfaMapping.catalogue(itemTypes: [
            ItemType(id: "user.job", label: "Job", plural: "Jobs", icon: "lucide:briefcase", origin: .registered),
            ItemType(id: "core.note", label: "Note", plural: "Notes", icon: "lucide:file-text", origin: .platform),
            ItemType(id: "studio.cuttings", label: "Press Cutting", plural: "Press Cuttings", icon: "lucide:scissors",
                     origin: .plugin, plugin: .init(name: "studio", version: "1"))
        ], edgeTypes: [])
        library.sources.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: "lucide:code-xml", nameOrigin: .key)]
        library.sources.counts = ["github": 47, "rss": 3]
        libraries.searchLeaveOuts.update(libraries.libraryKey) { $0.sources = ["github"]; $0.types = [TypeID("studio.cuttings")] }
        let launcher = SettingsLauncher()
        let host = AppSettingsHost(libraries: libraries, launcher: launcher)
        for page: SettingsPage in [.keyboard, .lists, .layouts, .search] {
            launcher.navigation.show(page)
            let detail = SettingsDetail(navigation: launcher.navigation, host: host, libraries: libraries)
                .environment(libraries).environment(\.library, library)
            let narrow = CGSize(width: SettingsTokens.Metric.windowMinWidth, height: Self.size.height)
            let cases = [(ColorScheme.light, "light", InterfaceStyle.defaultTextSize, Self.size),
                         (.dark, "dark", InterfaceStyle.defaultTextSize, Self.size), (.dark, "large", 24, narrow)]
            for (appearance, name, textSize, size) in cases {
                let window = RenderedWindow(selection: page, detail: detail.environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize)))
                try await SettingsRender.png(
                    window.defaultAppStorage(libraries.preferences.defaults), size: size,
                    named: "\(page.title) \(name)", appearance: appearance)
            }
        }
    }

    @Test func editor() async throws {
        try await SettingsRender.png(RenderedWindow(selection: .editor, detail: EditorPage()), size: Self.size, named: "Editor")
    }

    /// The whole page, taller than the window, in place of the board's scrolled view.
    @Test(arguments: [ColorScheme.light, .dark], [13, 24])
    func editorWhole(appearance: ColorScheme, textSize: Int) async throws {
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        defaults.set(textSize, forKey: InterfaceKey.textSize)
        try await SettingsRender.png(
            RenderedWindow(selection: .editor, detail: EditorPage())
                .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
                .defaultAppStorage(defaults),
            size: CGSize(width: Self.size.width, height: textSize == 24 ? 2_900 : 1_600),
            named: "Editor, \(appearance), \(textSize) pt", appearance: appearance)
    }

    @Test func editorWithAMissingFont() async throws {
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        defaults.set("Uninstalled Sans", forKey: AppearanceKey.textFont)
        try await SettingsRender.png(
            RenderedWindow(selection: .editor, detail: EditorPage().defaultAppStorage(defaults)),
            size: Self.size, named: "Editor, a missing font")
    }

    @Test func connectionConnected() async throws {
        let (libraries, bench) = try await connected()
        _ = bench
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: ConnectionPage(settingsHost: AppSettingsHost(libraries: libraries, launcher: SettingsLauncher())).environment(libraries).environment(libraries.host)),
            size: Self.size, named: "Connection")
    }

    /// A page's states against boards S26 to S30: the owner's permissions held in part or in full, the server not answering,
    /// and the sign-in ended.
    private func connection(
        named name: String, holding permissions: Set<InstancePermission> = SystemSignIns.askedAtSignIn, readsName: Bool = true,
        state: MarfaConnectionState = .online, waiting: Int = 0
    ) async throws {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        bench.servers.names.withLock { $0[try! MarfaConnection(address: "https://marfa.castell.studio")] = "Castell Studio" }
        try await libraries.host.connect(address: "https://marfa.castell.studio", key: "k")
        let source = try #require(bench.servers.last)
        // Without `readsName`, a sign-in made before the app asked for the owner's name.
        bench.signIns.save("k", for: URL(string: "https://marfa.castell.studio")!, permissions: permissions, profile: readsName)
        source.report.set(SyncReport(lastSynced: .now.addingTimeInterval(-60), waiting: waiting, queueRead: true))
        source.state.set(state)
        await libraries.host.refreshGrants()
        let page = ConnectionPage(settingsHost: AppSettingsHost(libraries: libraries, launcher: SettingsLauncher()))
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: page.environment(libraries).environment(libraries.host)),
            size: Self.size, named: name, settle: .milliseconds(800))
    }

    @Test func connectionWithEveryPermission() async throws { try await connection(named: "Connection") }
    @Test func connectionWithoutTheOwnersName() async throws {
        try await connection(named: "Connection, without the owner’s name", readsName: false)
    }
    @Test func connectionWithoutTheOwnersPermissions() async throws {
        try await connection(named: "Connection, without the owner’s permissions", holding: [.itemsPurge, .configManage, .schemaWrite])
    }
    @Test func connectionNotAnswering() async throws {
        try await connection(named: "Connection, not answering", state: .offline(reason: "refused"), waiting: 3)
    }
    @Test func connectionSignedOut() async throws { try await connection(named: "Connection, signed out", state: .keyRefused, waiting: 3) }

    @Test func connectionNotConnected() async throws {
        let bench = HostBench()
        let defaults = ThrowawayDefaults.make("SettingsRenderTests")
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        try await SettingsRender.png(
            RenderedWindow(selection: .connection, detail: ConnectionPage(settingsHost: AppSettingsHost(libraries: libraries, launcher: SettingsLauncher())).environment(libraries).environment(libraries.host)),
            size: Self.size, named: "Connection, not connected")
    }

    @Test func search() async throws {
        let library = FakeItemLibrary(items: [])
        library.sources.infos = ["github": SourceInfo(code: "github", name: "GitHub", mark: "lucide:code-xml", nameOrigin: .key)]
        library.sources.counts = ["github": 1_840]
        let (libraries, bench) = try await connected()
        _ = bench
        libraries.searchLeaveOuts.update(libraries.libraryKey) { $0.sources = ["github"]; $0.types = [LibraryFixture.ticket] }
        library.catalogue = LibraryFixture.catalogue
        try await SettingsRender.png(
            RenderedWindow(selection: .search, detail: SearchPage().environment(libraries).environment(\.library, library)),
            size: Self.size, named: "Search")
    }

    /// Exclusions at the limit. The Add sheet explains which additions still fit.
    @Test func searchAtTheLimit() async throws {
        let library = FakeItemLibrary(items: [])
        let codes = (0..<12).map { "source-\($0)" }
        library.sources.infos = Dictionary(uniqueKeysWithValues: codes.map { ($0, SourceInfo(code: $0, name: "Source \($0)", mark: nil, nameOrigin: .key)) })
        library.sources.counts = Dictionary(uniqueKeysWithValues: codes.map { ($0, 10) })
        let (libraries, bench) = try await connected()
        _ = bench
        libraries.searchLeaveOuts.update(libraries.libraryKey) { $0.sources = Set(codes.prefix(10)) }
        library.catalogue = LibraryFixture.catalogue
        try await SettingsRender.png(
            RenderedWindow(selection: .search, detail: SearchPage().environment(libraries).environment(\.library, library)),
            size: Self.size, named: "Search, at the limit")
    }

    @Test(arguments: [ColorScheme.light, .dark], [13, 24])
    func connectionWithLocalCopy(appearance: ColorScheme, textSize: Int) async throws {
        let library = FakeItemLibrary(items: [])
        library.downloadedFiles = FakeDownloads(
            state: DownloadedFileState(
                budget: .automatic, limit: 12_000_000_000, bytes: 1_200_000,
                attachments: .init(held: 53, heldBytes: 640_000, missing: 0, reasons: [])))
        let (libraries, bench) = try await connected()
        let host = AppSettingsHost(libraries: libraries, launcher: SettingsLauncher())
        let defaults = ThrowawayDefaults.make("ConnectionRender")
        let connection = try #require(libraries.host.configuredConnection)
        let store = bench.location.store(for: connection)
        try Data(repeating: 1, count: 2_000_000).write(to: store)
        try await SettingsRender.png(
            RenderedWindow(
                selection: .connection, detail: ConnectionPage(settingsHost: host)
                    .environment(libraries).environment(libraries.host).environment(\.library, library))
                .environment(\.settingsTextScale, InterfaceStyle.scale(for: textSize))
                .defaultAppStorage(defaults),
            size: textSize == 24 ? CGSize(width: SettingsTokens.Metric.windowMinWidth, height: 1_775) : Self.size,
            named: "Connection, \(appearance), \(textSize) pt", appearance: appearance, settle: .milliseconds(1_000))
    }

    /// The host's fake server, to put concerns and readings on.
    func fake(_ host: StubMarfaHost) -> FakeOwnerCalls { host.ownerCalls as! FakeOwnerCalls }

    private func windowed(
        _ page: MarfaSettingsPage, host: StubMarfaHost, subpage: SettingsSubpage? = nil, sheet: AnyView? = nil, badge: Int? = nil
    ) -> some View {
        RenderedWindow(
            selection: .marfa(page), sheet: sheet, badge: badge, detail: MarfaSettingsPageView(page: page, host: host).environment(\.settingsSubpage, subpage))
    }

    @Test func accountProblems() async throws {
        let host = await stub()
        fake(host).state.withLock {
            $0.concerns = [
                AttentionConcern(kind: .key, reference: "key-1", title: "Backup script expires on Monday"),
                AttentionConcern(kind: .connector, reference: "rss", title: "RSS reports a problem"),
            ]
            $0.metrics = InstanceMetricsReading(version: "0.0.84", databaseBytes: 214_000_000, fileBytes: 3_400_000_000)
            $0.update.available = true
            $0.update.latest = UpdateRelease(version: "0.0.85")
            $0.profile = OwnerProfile(username: "Mira Castell", emailIsReadable: true, email: nil)
            $0.health?.backups.lastBackup = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now)
        }
        host.bindOverview()
        await host.overview.load()
        try await SettingsRender.png(windowed(.account, host: host, badge: 2), size: Self.size, named: "Account")
    }

    @Test func accountWithoutTheOwnersPermissions() async throws {
        let host = await stub { $0.grants = [.instanceRead, .keysManage, .itemsPurge, .grantsManage, .keysMint] }
        fake(host).state.withLock {
            $0.metrics = InstanceMetricsReading(version: "0.0.84", databaseBytes: 214_000_000, fileBytes: 3_400_000_000)
        }
        host.bindOverview()
        try await SettingsRender.png(windowed(.account, host: host), size: Self.size, named: "Account, without the owner’s permissions")
    }

    @Test func accountWithARefusedWrite() async throws {
        let source = FakeInstanceConfig([.name: .text("Castell Studio"), .versionRecentDays: .number(30)])
        source.updateFailure.withLock { $0 = .refused("That name is already taken on this server.") }
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        host.bindOverview()
        // The page reads the server's settings as it opens, so the refused save is made once that read is done.
        let refused = Task {
            try await Task.sleep(for: .milliseconds(300))
            settings.draft[.name] = "Harbour Joinery"
            await settings.save([.name])
        }
        try await SettingsRender.png(
            windowed(.account, host: host), size: Self.size, named: "Account, a write the server refused", settle: .milliseconds(1_000))
        try await refused.value
    }

    private static let sourceRows = [
        MarfaSourceRow(code: "marfa-mac", name: "Marfa for Mac", mark: nil, count: 4_212, nameOrigin: .app),
        MarfaSourceRow(code: "github", name: "GitHub", mark: nil, count: 318, nameOrigin: .set),
        MarfaSourceRow(code: "readwise", name: "Readwise", mark: nil, count: 127, nameOrigin: .key),
        MarfaSourceRow(code: "rss", name: "RSS", mark: nil, count: 156, nameOrigin: .key),
    ]

    @Test func sources() async throws {
        let host = await stub { $0.sources = Self.sourceRows }
        try await SettingsRender.png(windowed(.sources, host: host), size: Self.size, named: "Sources")
    }

    @Test func limitSources() async throws {
        let host = await stub { $0.sources = Self.sourceRows }
        fake(host).state.withLock {
            $0.names = ["core.highlight": "Highlights", "core.bookmark": "Bookmarks"]
            $0.sources = Self.sourceRows.map { OwnerSource(code: $0.code, name: $0.name) }
            $0.sourceLimit = SourceLimit(
                instanceID: "instance-1", isOn: true, types: ["core.highlight"], sources: ["marfa-mac", "readwise"], strictTypes: nil, allowlist: nil)
        }
        try await SettingsRender.png(
            windowed(.sources, host: host, subpage: SourcesPage.limitSources), size: Self.size, named: "Sources, Limit Sources")
    }

    @Test func history() async throws {
        let source = FakeInstanceConfig([
            .versionRecentDays: .number(30), .versionDailyDays: .number(90), .versionWeeklyDays: .number(365), .versionMaxVersions: .number(500),
            .auditRetentionDays: .number(90), .eventLogRetentionDays: .number(30), .rowLogRetentionDays: .number(30),
            .inboundHandledRetentionDays: .number(7), .inboundPendingRetentionDays: .number(30),
        ])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        try await SettingsRender.png(
            windowed(.fileStorage, host: StubMarfaHost(settings: settings)), size: Self.size, named: "Storage, versions")
    }

    @Test func fileStorage() async throws {
        let source = FakeInstanceConfig([
            .blobMinCopies: .number(1), .diskReserveMegabytes: .number(128), .enrichmentEnabled: .flag(true), .enrichmentOcrEnabled: .flag(true),
            .mcpFetchEnabled: .flag(true), .mcpFetchMaxMegabytes: .number(50), .blobCleanupEnabled: .flag(true), .blobCleanupGraceSeconds: .number(86_400),
        ])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        fake(host).state.withLock {
            $0.fileStores = FileStores(
                stores: [
                    FileStoreRow(id: "a", kind: .disk, locator: "/var/lib/marfa/files", error: nil),
                    FileStoreRow(id: "b", kind: .folder, locator: "/Volumes/Studio Backup", error: nil),
                ], orphanCount: 3, orphanBytes: 12_000_000, firstFound: .now, orphansComplete: true)
            $0.metrics.fileBytes = 3_400_000_000
        }
        try await SettingsRender.png(windowed(.fileStorage, host: host), size: Self.size, named: "File Storage")
    }

    @Test func trash() async throws {
        let titles = [
            "Order oak for the Harbour Joinery worktops", "Lisbon zine: first cover ideas", "Kiln hire in East Sussex",
            "“The joint is the detail that tells you who made it”", "Lewes Trust site walk", "Allotment shed: felt roof quote",
            "Tom Hartley", "Oak species and their grain",
        ]
        let host = await stub {
            $0.deletedItems = titles.enumerated().map { index, title in
                MarfaDeletedItem(
                    id: "item-\(index)", title: title, deleted: Date.now.addingTimeInterval(-Double(index) * 86_400 * 2), kind: "Notes",
                    source: "Marfa for Mac")
            }
            $0.deletedCount = 1_204
        }
        try await SettingsRender.png(
            RenderedWindow(selection: .trash, detail: MarfaSettingsPageView(page: .trash, host: host)),
            size: Self.size, named: "Recently Deleted")
        try await SettingsRender.png(
            windowed(.trash, host: host, subpage: TrashPage.allDeleted), size: Self.size, named: "All deleted items")
    }

    @Test func needsAPermission() async throws {
        let host = await stub { $0.grants = [] }
        try await SettingsRender.png(
            RenderedWindow(selection: .trash, detail: MarfaSettingsPageView(page: .trash, host: host)),
            size: Self.size, named: "A page the app may not open")
    }

    @Test func notAnswering() async throws {
        let host = await stub { $0.connection = .notAnswering(lastAnswered: .now.addingTimeInterval(-600)) }
        try await SettingsRender.png(
            RenderedWindow(selection: .account, detail: MarfaSettingsPageView(page: .account, host: host)), size: Self.size,
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
    func owner(_ configure: (FakeOwnerCalls.State) -> Void = { _ in }) -> StubMarfaHost {
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
                AppAccess(id: "g1", clientID: "marfa-mac", kind: .app, name: "Marfa for Mac on MacBook Pro", origins: [], scopes: ["*:read", "*:write"], granted: Self.days(30), lastUsed: .now),
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
            // A key sign-in, since a signed-in app can't be told from another app by anything it knows about itself.
            state.identity = OwnIdentity(keyID: "k-marfa-mac", expires: nil)
            let ownMaker = OwnerWebhook.Maker(kind: .key, id: "k-marfa-mac", name: "Marfa for Mac on MacBook Pro")
            let raycast = OwnerWebhook.Maker(kind: .app, id: "raycast", name: "Raycast")
            let zine = OwnerWebhook.Maker(kind: .key, id: "k2", name: "Lisbon zine importer")
            state.webhooks = [
                OwnerWebhook(id: "w1", url: "https://build.castell.studio/hooks/marfa", events: ["item.created", "item.updated", "item.trashed"], typeFilter: "core.task", secretTail: "8f2c", active: true, created: Self.days(48), maker: ownMaker),
                OwnerWebhook(id: "w2", url: "https://hooks.ledgerly.app/marfa", events: ["item.created"], typeFilter: "core.task", secretTail: "1a9d", active: false, created: Self.days(20), maker: ownMaker),
                OwnerWebhook(id: "w3", url: "https://raycast.castell.studio/notify", events: ["item.created", "item.updated"], typeFilter: "core.task", secretTail: "5e07", active: true, created: Self.days(30), maker: raycast),
                OwnerWebhook(id: "w4", url: "https://zine.castell.studio/hooks/new", events: ["item.created"], typeFilter: "core.bookmark", secretTail: "c3b1", active: true, created: Self.days(12), maker: zine),
            ]
            state.deliveries["w4"] = [
                WebhookDeliveryInfo(id: "d4", event: "item.created", status: .failed, statusCode: 502, attempts: 3, error: "The receiver answered 502.", created: .now.addingTimeInterval(-3600)),
            ]
            state.deliveries["w1"] = [
                WebhookDeliveryInfo(id: "d1", event: "item.updated", status: .succeeded, statusCode: 200, attempts: 1, error: nil, created: .now.addingTimeInterval(-600)),
                WebhookDeliveryInfo(id: "d2", event: "item.created", status: .failed, statusCode: 500, attempts: 3, error: "The receiver answered 500.", created: .now.addingTimeInterval(-7200)),
                WebhookDeliveryInfo(id: "d3", event: "item.trashed", status: .succeeded, statusCode: 200, attempts: 1, error: nil, created: Self.days(1)),
            ]
            state.deliveries["w2"] = []
            state.folders = [OwnerFolder(id: "f1", title: "Studio Notes"), OwnerFolder(id: "f2", title: "Client Drawings")]
            state.reports["f1"] = FolderReport(copies: [
                FolderCopy(id: "c1", signIn: "marfa on MacBook Pro", pendingUploads: 0, pendingDownloads: 0, pausedRemovals: 0, firstSyncWaiting: false, problems: [], ageSeconds: 70),
                FolderCopy(id: "c2", signIn: "marfa on Mac mini", pendingUploads: 0, pendingDownloads: 3, pausedRemovals: 0, firstSyncWaiting: false, problems: [], ageSeconds: 1200),
            ])
            state.reports["f2"] = FolderReport(copies: [
                FolderCopy(id: "c3", signIn: "marfa on MacBook Pro", pendingUploads: 0, pendingDownloads: 0, pausedRemovals: 12, firstSyncWaiting: false, problems: [.init(code: .heldFile, count: 8)], ageSeconds: 75),
            ])
            state.settings = AddressSettings(
                instanceID: "i", signIn: "https://marfa.castell.studio",
                addresses: ["https://marfa.castell.studio", "http://castell-studio.local", "https://100.84.12.7"],
                websites: ["https://castell.studio"])
        }
        let host = StubMarfaHost(settings: InstanceSettingsModel { nil })
        host.ownerCalls = calls
        host.folderCalls = FakeFolderCalls(
            FakeFolderCalls.folder("f1", "Studio Notes", types: ["core.note"], ignore: [".DS_Store", "*.tmp", "Exports/"]),
            FakeFolderCalls.folder("f2", "Client Drawings", types: ["core.file"]))
        return host
    }

    func page(
        _ page: MarfaSettingsPage, _ host: StubMarfaHost, subpage: SettingsSubpage? = nil, sheet: AnyView? = nil, size: CGSize = Self.size,
        named: String
    ) async throws {
        try await SettingsRender.png(
            RenderedWindow(
                selection: .marfa(page), sheet: sheet,
                detail: MarfaSettingsPageView(page: page, host: host).environment(\.settingsSubpage, subpage)),
            size: size, named: named, settle: .milliseconds(900))
    }

    func context(_ host: StubMarfaHost) -> OwnerContext { OwnerContext(host: host) }

    @Test(arguments: [ColorScheme.light, .dark]) func accountBoards(appearance: ColorScheme) async throws {
        let host = owner()
        let source = FakeInstanceConfig([.name: .text("Castell Studio")])
        source.config.withLock { $0.signInAddress = "https://marfa.castell.studio" }
        host.instanceSettings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        fake(host).state.withLock { state in
            state.profile = OwnerProfile(name: "Mira Castell", username: "mcastell", emailIsReadable: true, email: "mira@castell.studio", pictureIsReadable: true)
            state.metrics = InstanceMetricsReading(version: "0.0.106", databaseBytes: 200_000_000, fileBytes: 3_400_000_000)
            state.update.running = "0.0.106"
            state.update.available = true
            state.update.latest = UpdateRelease(version: "0.0.107")
            state.concerns = [.init(kind: .key, reference: "key", title: "A key expires next Monday")]
        }
        host.bindOverview()
        await host.overview.load()
        for page in [MarfaSettingsPage.account, .passkeys, .browsers, .network] {
            let height = page == .account ? CGFloat(1300) : Self.size.height
            try await SettingsRender.png(windowed(page, host: host, badge: host.overview.attentionBadge),
                size: CGSize(width: Self.size.width, height: height), named: "\(page.title), \(appearance)", appearance: appearance)
        }
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

    @Test func anAppWithOwnerPermissions() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock { $0.apps[1].scopes += ["backups.manage", "audit.read"] }
        try await page(.apps, host, subpage: SettingsSubpage(id: "app:g2", title: "Raycast"), named: "An app, Raycast, with owner permissions")
    }

    @Test func anAppsOwnerPermissions() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock { $0.apps[1].scopes += ["backups.manage", "audit.read"] }
        try await page(
            .apps, host, subpage: OwnerPermissions.subpage(of: SettingsSubpage(id: "app:g2", title: "Raycast")),
            named: "An app's owner permissions")
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

    @Test func aKeyWithExtend() async throws {
        try await page(.keys, owner(), subpage: SettingsSubpage(id: "key:k1", title: "Backup script"), named: "A key, Extend")
    }

    @Test func extendKey() async throws {
        let host = owner()
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginExtend(model.keys[1])
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "Extend Key")
    }

    @Test func extendKeyRefused() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.fail("change", with: .notPermitted(nil))
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginExtend(model.keys[1])
        model.extensionChoice = .days(365)
        await model.extend()
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "Extend Key, refused")
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

    @Test func aKeysOwnerPermissions() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock { $0.keys[0].permissions = ["backups.manage", "items.purge", "audit.read"] }
        try await page(
            .keys, host, subpage: OwnerPermissions.subpage(of: SettingsSubpage(id: "key:k1", title: "Backup script")),
            named: "A key's owner permissions")
    }

    @Test func newKeyChoosingOwnerPermissions() async throws {
        let host = owner()
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginNewKey()
        model.draft.permissions = ["items.purge"]
        model.isChoosingPermissions = true
        try await page(.keys, host, sheet: AnyView(KeySheet(model: model)), named: "New Key, owner permissions")
    }

    /// A sheet taller than the window grows to the window's height, then scrolls between its title and its buttons.
    @Test func newKeyInAShortWindow() async throws {
        let host = owner()
        let model = KeysModel(context: context(host))
        await model.load()
        model.beginNewKey()
        model.isChoosingPermissions = true
        try await page(
            .keys, host, sheet: AnyView(KeySheet(model: model)), size: CGSize(width: SettingsTokens.Metric.windowWidth, height: 560),
            named: "New Key, in a short window")
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
        try await page(.network, owner(), named: "Network")
    }

    @Test func addressesAddingOne() async throws {
        let host = owner()
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        try await page(.network, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Network, adding one")
    }

    @Test func addressesAddingOneTheServerRefuses() async throws {
        let host = owner()
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.addAddress)
        model.input = "https://castell.studio/path"
        await model.check()
        try await page(.network, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Network, an address refused")
    }

    @Test func addressesChangingTheSignInAddress() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock {
            $0.reach = .answers
            $0.requiresConfirmation = true
            $0.consequences = [
                .init(code: "browser_sessions_end", sentence: "Every browser signs in again at the new address. 2 are signed in.", count: 2),
                .init(code: "passkeys_unusable", sentence: "A passkey works only where it was added. Add them again.", count: 2),
                .init(code: "apps_sign_in_again", sentence: "The app included. Each signs in at the new address.", count: 4),
            ]
        }
        let model = AddressesModel(context: context(host))
        await model.load()
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        try await page(.network, host, sheet: AnyView(AddressSheet(model: model, serverName: "Castell Studio")), named: "Network, changing the sign-in address")
    }

    // MARK: Webhooks and Folders

    @Test func webhooks() async throws {
        try await page(.webhooks, owner(), named: "Webhooks")
    }

    @Test func webhooksWithoutManageKeys() async throws {
        let host = owner()
        host.grants = [.webhooksManage]
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock { $0.webhooks = Array($0.webhooks.prefix(2)) }
        try await page(.webhooks, host, named: "Webhooks, without Manage Keys")
    }

    @Test func aWebhookAnotherAppMade() async throws {
        try await page(
            .webhooks, owner(), subpage: SettingsSubpage(id: "webhook:w4", title: "zine.castell.studio/hooks/new"),
            size: CGSize(width: SettingsTokens.Metric.windowWidth, height: 1100), named: "A webhook another key made")
    }

    @Test func webhooksOfEveryMakerWithOneGone() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock {
            $0.webhooks.append(
                OwnerWebhook(id: "w5", url: "https://old.example.com/hook", events: ["item.created"], typeFilter: nil, secretTail: "0d4e", active: true, created: Self.days(90), maker: .init(kind: .key, id: "k-gone", name: nil)))
        }
        try await page(.webhooks, host, named: "Webhooks, a revoked key's among them")
    }

    @Test func noWebhooks() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.state.withLock { $0.webhooks = [] }
        try await page(.webhooks, host, named: "Webhooks, none yet")
    }

    @Test func aWebhook() async throws {
        try await page(
            .webhooks, owner(), subpage: SettingsSubpage(id: "webhook:w1", title: "build.castell.studio/hooks/marfa"),
            size: CGSize(width: SettingsTokens.Metric.windowWidth, height: 1500), named: "A webhook")
    }

    @Test func newWebhook() async throws {
        let host = owner()
        let model = WebhooksModel(context: context(host))
        await model.load()
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        try await page(.webhooks, host, sheet: AnyView(WebhookSheet(model: model, serverName: "Castell Studio")), named: "New Webhook")
    }

    @Test func newWebhookRefused() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.fail("createWebhook", with: .refused("That address isn’t public, so Castell Studio won’t send to it."))
        let model = WebhooksModel(context: context(host))
        await model.load()
        model.beginNew()
        model.draft.address = "http://10.0.0.5/hook"
        await model.make()
        try await page(.webhooks, host, sheet: AnyView(WebhookSheet(model: model, serverName: "Castell Studio")), named: "New Webhook, refused")
    }

    @Test func theSigningSecretShownOnce() async throws {
        let host = owner()
        let model = WebhooksModel(context: context(host))
        await model.load()
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        await model.make()
        try await page(.webhooks, host, sheet: AnyView(WebhookSheet(model: model, serverName: "Castell Studio")), named: "The signing secret, shown once")
    }

    @Test func webhooksWithoutWebhooksManage() async throws {
        let host = owner()
        host.grants = []
        try await page(.webhooks, host, named: "Webhooks, without webhooks.manage")
    }

    @Test func folders() async throws {
        try await page(.folders, owner(), named: "Folders")
    }

    @Test func aFolder() async throws {
        try await page(.folders, owner(), subpage: SettingsSubpage(id: "folder:f1", title: "Studio Notes"), named: "A folder")
    }

    @Test func aFolderWithRemovalsWaiting() async throws {
        try await page(.folders, owner(), subpage: SettingsSubpage(id: "folder:f2", title: "Client Drawings"), named: "A folder with removals waiting")
    }

    @Test func foldersTheServerRefusesToList() async throws {
        let host = owner()
        (host.ownerCalls as? FakeOwnerCalls)?.fail("folders", with: .notPermitted(nil))
        try await page(.folders, host, named: "Folders, refused")
    }
}
