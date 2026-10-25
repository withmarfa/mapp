import Foundation
import Observation

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

    /// Changes a Marfa library could not keep because its copy closed first, for the window in front to tell,
    /// since by then the windows read another library and the one that refused them is shown nowhere.
    var unkept: Unkept?

    nonisolated struct Unkept: Hashable, Sendable {
        var title: String
        var message: String
        /// The text the person typed that no library holds, for them to put back.
        var text: String?
    }

    /// What each library's person chose to show in the sidebar.
    let sidebarLayouts: SidebarLayouts

    init(host: MarfaHost, defaults: UserDefaults = .standard) {
        self.host = host
        sidebarLayouts = SidebarLayouts(defaults: defaults)
        marfaSettings = MarfaSettingsModel(host: host)
        isLaunching = host.configuredConnection != nil
        host.handOverEdits = { [weak self] in await self?.flushEditors() ?? false }
        host.onNotKept = { [weak self] in self?.tell($0) }
    }

    /// Opens the saved server's copy and paints from it before the network is asked anything.
    func launch() async {
        await host.launch()
        isLaunching = false
    }

    var mode: Mode {
        Self.mode(
            hasSource: host.source != nil, isConfigured: host.configuredConnection != nil, state: host.state,
            isLaunching: isLaunching, isBusy: host.isBusy)
    }

    /// Which library the windows show. A server's copy is shown whenever it is open. Leaving a server forgets its
    /// address first, so the windows ask for another; a copy closed to open again, as when a key is replaced, is
    /// waited for.
    nonisolated static func mode(hasSource: Bool, isConfigured: Bool, state: MarfaHost.State, isLaunching: Bool, isBusy: Bool) -> Mode {
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

    /// Gathers what is not kept until the person has been told, so a second refusal adds its text to the first.
    func tell(_ notKept: MarfaLibrary.NotKept) {
        let texts = [unkept?.text, notKept.text].compactMap { $0 }.filter { !$0.isEmpty }
        let text = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        let title = unkept == nil ? notKept.title : String(localized: "Some Changes Weren’t Saved")
        let message = Self.unkeptMessage(for: notKept, text: text, earlier: unkept?.message)
        unkept = Unkept(title: title, message: message, text: text)
    }

    /// What the person is told: the reason the change was not kept and where their text is. Changes not kept for
    /// different reasons share the plainest account of them.
    private static func unkeptMessage(for notKept: MarfaLibrary.NotKept, text: String?, earlier: String?) -> String {
        let message: String
        if let reason = notKept.reason {
            message = text == nil ? reason : String(localized: "\(reason) Your text is on the clipboard, so you can paste it back.")
        } else if text == nil {
            message = String(localized: "MAPP closed the library before it could keep your change. Make the change again.")
        } else {
            message = String(localized: "MAPP closed the library before it could keep what you typed. Your text is on the clipboard, so you can paste it back.")
        }
        guard let earlier, earlier != message else { return message }
        return text == nil
            ? String(localized: "MAPP couldn’t keep some of your changes. Make them again.")
            : String(localized: "MAPP couldn’t keep some of what you typed. Your text is on the clipboard, so you can paste it back.")
    }

    /// Hands every open page's last edit to the library it came from, and returns once each library keeps its
    /// writes on this Mac, never waiting on a server. Run before anything changes which library the windows read,
    /// and before quitting.
    @discardableResult
    func flushEditors() async -> Bool {
        guard await Self.flush() else { return false }
        await host.library?.finish()
        return true
    }

    /// Quitting waits at most `limit` and is cancelled if the editors or library cannot finish. A page or a title
    /// that cannot be handed over has told the person already; a library still keeping its writes is told here.
    func flushEditors(within limit: Duration) async -> Bool {
        let first = FirstOf()
        return await withCheckedContinuation { continuation in
            Task {
                let kept = await flushEditors()
                first.resume(continuation, with: kept)
            }
            Task { [host] in
                try? await Task.sleep(for: limit)
                guard first.resume(continuation, with: false) else { return }
                host.library?.failure = (
                    String(localized: "Couldn’t Quit"),
                    String(localized: "MAPP is still saving your changes on this Mac. Try again in a moment."))
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
    private static func flush() async -> Bool {
        await withCheckedContinuation { continuation in
            EditorController.flushAll { continuation.resume(returning: $0) }
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
            defaults.removePersistentDomain(forName: suite)
            let root = URL.temporaryDirectory.appending(path: "Sample Marfa", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
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
                describer: { _ in SampleLibrary.name })
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
