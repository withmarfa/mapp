import Foundation
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

    /// What each library's person chose to show in the sidebar.
    let sidebarLayouts: SidebarLayouts

    /// Asks every open page for its last edit and answers whether they all handed it over. A test gives its own, since
    /// the real one waits on every page in the process, those of tests running beside it too.
    private let handOverPages: (QuitTrace, @escaping (Bool) -> Void) -> Void

    init(
        host: MarfaHost, defaults: UserDefaults = .standard,
        handOverPages: ((@escaping (Bool) -> Void) -> Void)? = nil
    ) {
        self.host = host
        self.handOverPages = handOverPages.map { injected in { _, done in injected(done) } }
            ?? { trace, done in EditorController.flushAll(trace: trace, then: done) }
        sidebarLayouts = SidebarLayouts(defaults: defaults)
        marfaSettings = MarfaSettingsModel(host: host)
        instanceSettings = InstanceSettingsModel(provider: { [host] in host.instanceConfigTarget() })
        instanceSettings.onRenamed = { [host] in host.refreshName() }
        isLaunching = host.configuredConnection != nil
        host.handOverEdits = { [weak self] in await self?.flushEditors() ?? false }
        LaunchTrace.shared.mark(.librariesInit, note: isLaunching ? "server set" : "no server")
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

    /// Which library the windows show. A server's copy is shown whenever it is open. Leaving a server forgets its
    /// address first, so the windows ask for another; a copy closed to open again, as when a key is replaced, is
    /// waited for.
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

    /// Names the library the windows read by its server's address, so its sidebar layout is its own.
    var sidebarLayoutKey: String {
        "marfa:" + (host.configuredConnection?.address.absoluteString ?? "")
    }

    var sidebarLayout: SidebarLayout { sidebarLayouts.layout(for: sidebarLayoutKey) }

    func updateSidebarLayout(_ change: (inout SidebarLayout) -> Void) {
        sidebarLayouts.update(sidebarLayoutKey, change)
    }

    /// Hands every open page's last edit to the library it came from, and returns once each library keeps its
    /// writes on this Mac, never waiting on a server. Run before anything changes which library the windows read,
    /// and before quitting.
    @discardableResult
    func flushEditors() async -> Bool {
        await flushEditors(tracing: QuitTrace(purpose: .libraryChange))
    }

    private func flushEditors(tracing trace: QuitTrace) async -> Bool {
        guard await flush(tracing: trace) else { return false }
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
                    ? String(localized: "MAPP is still saving what you last typed. Try again in a moment.")
                    : String(localized: "MAPP is still saving your changes on this Mac. Try again in a moment.")
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
            let suite = "MAPP.SampleMarfa"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            let root = URL.temporaryDirectory.appending(path: "Sample Marfa", directoryHint: .isDirectory)
            // A run against a test server may ask to keep the copy the last run left (`-MAPPKeepTestStore`), so the
            // speed tests can time a launch on a copy that is already there.
            let keepsCopy = environment["MAPP_TEST_MARFA_URL"] != nil
                && ProcessInfo.processInfo.arguments.contains("-MAPPKeepTestStore")
            if !keepsCopy {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: root)
            }
            guard SampleLibrary.isRequested, !SampleLibrary.startsUnconfigured else {
                // The unit tests, previews and `-MAPPSampleUnconfigured` start with no server, as a first launch does.
                let host = MarfaHost(defaults: defaults, keys: MemoryKeyStore(), location: location(root: root))
                return Libraries(host: host, defaults: defaults)
            }
            // A debug build can be pointed at a test server by hand, in place of the sample. The key stays in memory
            // and the address goes only to the sample defaults cleared above, so nothing reaches the Keychain or the
            // saved server.
            if let address = environment["MAPP_TEST_MARFA_URL"], let connection = try? MarfaConnection(address: address),
                let key = environment["MAPP_TEST_MARFA_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
            {
                let host = MarfaHost(defaults: defaults, keys: MemoryKeyStore([connection: key]), location: location(root: root))
                host.presetTestServer(connection)
                return Libraries(host: host, defaults: defaults)
            }
            let sample = SampleLibrary.connection
            let host = MarfaHost(
                defaults: defaults, keys: MemoryKeyStore([sample: "sample"]), location: location(root: root),
                opener: { connection, _, _ in SampleLibrary.open(connection) },
                describer: { _ in SampleLibrary.name },
                historian: { _, _ in nil }, configurer: { _, _ in nil })
            host.presetTestServer(sample)
            return Libraries(host: host, defaults: defaults)
        }
        #endif
        let host = MarfaHost(defaults: .standard, keys: KeychainKeyStore(), location: location())
        return Libraries(host: host)
    }

    private static func location(root: URL = MarfaStoreLocation.applicationSupport) -> MarfaStoreLocation {
        MarfaStoreLocation(root: root)
    }
}
