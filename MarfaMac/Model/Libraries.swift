import Foundation
import Marfa
import MarfaTesting
import Observation
import os

/// The library the windows read: the connected Marfa server's, and none until a server is set and its copy is
/// open. The app owns one of these, with the connection under it.
@Observable @MainActor final class Libraries {
    /// What the windows have to show.
    nonisolated enum Mode: Hashable, Sendable {
        /// No server is set, which is how the app starts, so the windows ask the person to connect to one.
        case unconfigured
        case marfa
        /// A server is set and its copy is being opened, so a window waits rather than show another library or
        /// give up what it was restored with.
        case opening
        /// A server is set and its copy is not open: its key was refused, or the copy cannot be opened.
        case failed
    }

    let host: MarfaHost
    /// True from launch until the saved server's copy has been tried.
    private(set) var isLaunching: Bool

    /// What Settings does for the connection, kept with the connection so a question put to the person is not
    /// forgotten when Settings is put away and opened again.
    let marfaSettings: MarfaSettingsModel

    /// The server's own settings that This Marfa edits, kept with the connection so a draft survives putting Settings
    /// away.
    let instanceSettings: InstanceSettingsModel

    /// The owner's pages that are open, which hold what was typed and not kept until Settings closes or the app quits.
    let ownerDrafts = OwnerDrafts()

    /// What each library's person chose to show in the sidebar.
    let sidebarLayouts: SidebarLayouts

    /// The look each library's person chose for its types.
    let typeLooks: TypeLooks

    /// What each library's person leaves out of search.
    let searchLeaveOuts: SearchLeaveOuts

    /// The shortcut each menu command has, on this Mac and for every library.
    let shortcuts: ShortcutBindings

    /// The shortcuts that work in any app, off until the person sets one.
    let anyAppShortcuts: AnyAppShortcuts

    /// The app's own settings, kept in the connected Marfa so every Mac that connects to it uses them.
    let preferences: PreferencesSync

    /// Asks every open page for its last edit and answers whether they all handed it over. A test gives its own, since
    /// the real one waits on every page in the process, those of tests running beside it too.
    private let handOverPages: (QuitTrace, @escaping (Bool) -> Void) -> Void

    /// The value panel open, if any, whose typed text is written or handed back before anything else changes.
    private let valuePanels: ValueEditPresenter

    private let defaults: UserDefaults

    init(
        host: MarfaHost, defaults: UserDefaults = .standard,
        handOverPages: ((@escaping (Bool) -> Void) -> Void)? = nil,
        valuePanels: ValueEditPresenter = .shared, instanceSettings: InstanceSettingsModel? = nil,
        hotKeys: any HotKeyRegistrar = NoHotKeys(), syncsPreferences: Bool = false
    ) {
        self.host = host
        self.defaults = defaults
        self.valuePanels = valuePanels
        self.handOverPages = handOverPages.map { injected in { _, done in injected(done) } }
            ?? { trace, done in EditorController.flushAll(trace: trace, then: done) }
        sidebarLayouts = SidebarLayouts(defaults: defaults)
        typeLooks = TypeLooks(defaults: defaults)
        searchLeaveOuts = SearchLeaveOuts(defaults: defaults)
        shortcuts = ShortcutBindings(defaults: defaults)
        anyAppShortcuts = AnyAppShortcuts(defaults: defaults, registrar: hotKeys)
        preferences = PreferencesSync(
            defaults: defaults, enabled: syncsPreferences,
            reload: { [sidebarLayouts, typeLooks, searchLeaveOuts, shortcuts, anyAppShortcuts] in
                sidebarLayouts.reload()
                typeLooks.reload()
                searchLeaveOuts.reload()
                shortcuts.reload()
                anyAppShortcuts.reload()
            })
        marfaSettings = MarfaSettingsModel(host: host)
        marfaSettings.settingsKept = .over(preferences)
        self.instanceSettings = instanceSettings ?? InstanceSettingsModel(provider: { [host] in host.instanceConfigTarget() })
        self.instanceSettings.onSaved = { [host] answer, settings, address in host.instanceSaved(answer, changing: settings, of: address) }
        isLaunching = host.configuredConnection != nil
        ownerDrafts.arrival = { [ownerDrafts, notices = host.notices] draft in
            ownerDrafts.deliver(draft, to: notices, because: String(localized: "You closed Settings before this was saved."))
        }
        host.handOverEdits = { [weak self] in await self?.flushEditors() ?? false }
        host.libraryChanged = { [weak self] library in self?.follow(library) }
        LaunchTrace.shared.mark(.librariesInit, note: isLaunching ? "server set" : "no server")
    }

    /// Puts every setting on this Mac back (`MacSettings`) and the shortcuts already held in memory with it, so the menus
    /// and the hot keys change at once and nothing writes the old choices back. Where the settings sync, the Marfa's are
    /// put back with them, for every Mac.
    func resetMacSettings() {
        shortcuts.restoreDefaults()
        anyAppShortcuts.clearAll()
        MacSettings.reset(in: defaults)
        Task { await preferences.flush() }
    }

    /// Has this app's settings follow the library's copy, where it has one of a Marfa server.
    private func follow(_ library: MarfaLibrary?) {
        guard let source = library?.source as? MarfaSource else {
            preferences.detach()
            return
        }
        // The copy's own server, since a switch opens the new copy before the host keeps its address.
        let connection = source.connection
        preferences.attach(
            WorkingCopyPreferences(
                copy: source.copy, answers: source.preferenceAnswers, sendSoon: { [engine = source.engine] in await engine.sync.drain() }),
            library: Self.libraryKey(for: connection.address),
            name: { [host] in host.instanceName(for: connection) })
    }

    /// Opens the saved server's copy and paints from it before the network is asked anything.
    func launch() async {
        await host.launch()
        isLaunching = false
        LaunchTrace.shared.mark(.copyOpened, note: host.library == nil ? "no copy" : "copy open")
        if host.library == nil { LaunchTrace.shared.settleWithoutLibrary() }
    }

    var mode: Mode {
        Self.mode(
            hasSource: host.source != nil, isConfigured: host.configuredConnection != nil, state: host.state,
            isLaunching: isLaunching, isBusy: host.isBusy)
    }

    /// Which library the windows show. An open copy is shown; a configured server whose copy is opening is waited
    /// for. With no server configured, the windows ask for one.
    nonisolated static func mode(hasSource: Bool, isConfigured: Bool, state: MarfaConnectionState, isLaunching: Bool, isBusy: Bool) -> Mode {
        if hasSource { return .marfa }
        guard isConfigured else { return .unconfigured }
        switch state {
        case .connecting: return .opening
        case .keyRefused, .unavailable, .otherVersion, .inUse: return isBusy ? .opening : .failed
        case .disconnected, .online, .offline: return isLaunching || isBusy ? .opening : .failed
        }
    }

    /// The library to read, nil where there is none to show: no server set, or a server whose copy is not open.
    var current: (any ItemLibrary)? {
        mode == .marfa ? host.library : nil
    }

    /// Names the library the windows read by its server's address, so its sidebar layout and its type looks are its own.
    var libraryKey: String {
        Self.libraryKey(for: host.configuredConnection?.address)
    }

    nonisolated static func libraryKey(for address: URL?) -> String {
        "marfa:" + (address?.absoluteString ?? "")
    }

    var sidebarLayout: SidebarLayout { sidebarLayouts.layout(for: libraryKey) }

    /// What the library the windows read leaves out of search.
    var searchLeaveOut: SearchLeaveOut { searchLeaveOuts.leaveOut(for: libraryKey) }

    func updateSidebarLayout(_ change: (inout SidebarLayout) -> Void) {
        sidebarLayouts.update(libraryKey, change)
    }

    /// Ends the open value panel and hands every open page's last edit to the library it came from, and returns once each library keeps its
    /// writes on this Mac, never waiting on a server. Run before anything changes which library the windows read,
    /// and before quitting.
    @discardableResult
    func flushEditors() async -> Bool {
        await flushEditors(tracing: QuitTrace(purpose: .libraryChange))
    }

    private func flushEditors(tracing trace: QuitTrace) async -> Bool {
        // A value typed in the panel is written, or handed back, before the library is asked to keep its writes.
        valuePanels.handOff()
        guard await flush(tracing: trace) else { return false }
        // A settings change still coalescing is queued with the rest.
        await preferences.flush()
        // The library may have closed since the flush began; then it holds nothing to wait for.
        guard let library = host.library else {
            trace.skip(.queue, because: "no library is open")
            return true
        }
        trace.begin(.queue, activity: library.engineActivity)
        await library.finish()
        trace.end(.queue)
        return true
    }

    /// Hands over what was typed in Settings and not saved, as the window does when it closes: a window's close is not
    /// posted when the app quits, and the draft has no other home.
    func handOffDraftsAtQuit() {
        instanceSettings.handOver(
            to: host.notices, because: String(localized: "You quit the app before saving the changes to this Marfa’s settings."))
        ownerDrafts.handOver(to: host.notices, because: String(localized: "You quit the app before this was saved."))
    }

    /// Quitting waits at most `limit` and is cancelled if the editors or library cannot finish. A page or a title
    /// that cannot be handed over has told the person already; a library still keeping its writes is told here.
    func flushEditors(within limit: Duration) async -> Bool {
        let first = FirstOf()
        let trace = QuitTrace(purpose: .quit)
        let interval = Telemetry.begin(.quit, "quit.flush")
        return await withCheckedContinuation { continuation in
            Task {
                let kept = await flushEditors(tracing: trace)
                let elapsed = interval.end()
                if first.resume(continuation, with: kept) {
                    Telemetry.logger(.quit).info("quit flush \(kept ? "kept" : "refused", privacy: .public) after \(elapsed.inMilliseconds, privacy: .public) ms")
                }
            }
            Task { [host] in
                try? await Task.sleep(for: limit)
                guard first.resume(continuation, with: false) else { return }
                trace.logTimeout(after: limit)
                // A page's hand-over can wait its turn behind another, each for up to the editor's own limit.
                let message = trace.unfinished.first == .editors
                    ? String(localized: "The app is still saving what you last typed. Try again in a moment.")
                    : String(localized: "The app is still saving your changes on this Mac. Try again in a moment.")
                host.notices.tell(String(localized: "Couldn’t Quit"), message)
            }
        }
    }

    /// Resumes once, with whichever answer comes first.
    private final class FirstOf {
        private var done = false

        /// Whether this answer was the first.
        @discardableResult
        func resume(_ continuation: CheckedContinuation<Bool, Never>, with value: Bool) -> Bool {
            guard !done else { return false }
            done = true
            continuation.resume(returning: value)
            return true
        }
    }

    /// The pages first, since an edit still in a page reaches a library only by being handed over.
    private func flush(tracing trace: QuitTrace) async -> Bool {
        trace.begin(.editors)
        defer { trace.end(.editors) }
        return await withCheckedContinuation { continuation in
            handOverPages(trace) { continuation.resume(returning: $0) }
        }
    }

    /// The app's own: the person's defaults and Keychain, and the copy in the app's own storage.
    static func standard() -> Libraries {
        #if DEBUG
        // The UI tests, the screenshots, the unit tests hosted in the app and Xcode's previews, which start the whole
        // app, never reach the person's saved server, Keychain or copies.
        let environment = ProcessInfo.processInfo.environment
        if SampleLibrary.isRequested
            || TestHost.isRequested
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        {
            let suite = "MarfaMac.SampleMarfa"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            let root = URL.temporaryDirectory.appending(path: "Sample Marfa", directoryHint: .isDirectory)
            // A run against a test server may ask to keep the copy the last run left (`-MarfaMacKeepTestStore`), so the
            // speed tests can time a launch on a copy that is already there.
            let keepsCopy = environment["MARFA_MAC_TEST_MARFA_URL"] != nil
                && ProcessInfo.processInfo.arguments.contains("-MarfaMacKeepTestStore")
            if !keepsCopy {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: root)
            }
            guard SampleLibrary.isRequested, !SampleLibrary.startsUnconfigured else {
                // The unit tests, previews and `-MarfaMacSampleUnconfigured` start with no server, as a first launch does.
                let host = MarfaHost(defaults: defaults, signIns: ScriptedSignIns(), location: location(root: root))
                return Libraries(host: host, defaults: defaults)
            }
            // A debug build can be pointed at a test server by hand, in place of the sample. The key stays in memory
            // and the address goes only to the sample defaults cleared above, so nothing reaches the Keychain or the
            // saved server.
            if let address = environment["MARFA_MAC_TEST_MARFA_URL"], let connection = try? MarfaConnection(address: address),
                let key = environment["MARFA_MAC_TEST_MARFA_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
            {
                let signIns = ScriptedSignIns([connection.address: key])
                let host = MarfaHost(defaults: defaults, signIns: signIns, location: location(root: root))
                host.presetTestServer(connection)
                // The key holds what the server says it holds, so a key without an owner's permissions shows Needs a Permission.
                Task {
                    // The test key is the app's own, which may write the settings' type, as a sign-in asks (`SystemSignIns`).
                    await signIns.adoptScopes(for: connection, adding: [PreferencesType.vendorScope])
                    await host.refreshGrants()
                }
                // `-MarfaMacSyncSettings` keeps this app's settings in the test server's item, as a real sign-in does. The pages
                // read the standard defaults, so the sync follows those, which this debug build starts empty.
                guard ProcessInfo.processInfo.arguments.contains("-MarfaMacSyncSettings") else { return Libraries(host: host, defaults: defaults) }
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
                return Libraries(host: host, defaults: .standard, syncsPreferences: true)
            }
            let sample = SampleLibrary.connection
            let host = MarfaHost(
                defaults: defaults, signIns: ScriptedSignIns([sample.address: "sample"]), location: location(root: root),
                opener: { connection, _, _ in SampleLibrary.open(connection) },
                describer: { _ in SampleLibrary.name },
                historian: { _, _ in nil }, configurer: { _, _ in nil })
            host.presetTestServer(sample)
            return Libraries(host: host, defaults: defaults)
        }
        #endif
        let host = MarfaHost(defaults: .standard, signIns: SystemSignIns(), location: location())
        return Libraries(host: host, hotKeys: SystemHotKeys(), syncsPreferences: true)
    }

    private static func location(root: URL = MarfaStoreLocation.applicationSupport) -> MarfaStoreLocation {
        MarfaStoreLocation(root: root)
    }
}
