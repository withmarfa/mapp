import Foundation
import Observation

/// The library the windows read: a Marfa server's once the app is connected to one, the notes folder's
/// otherwise. The app owns one of these, with the folder and the connection under it.
///
/// With no server set, which is how the app starts, the folder's library is chosen exactly as it was before
/// there was a server to choose, and nothing here shows.
@Observable @MainActor final class Libraries {
    /// What the windows have to show.
    nonisolated enum Mode: Hashable, Sendable {
        /// The notes folder, which is not yet chosen until the person chooses one.
        case files
        case marfa
        /// A server is set and its copy is being opened, so a window waits rather than show another library or
        /// give up what it was restored with.
        case opening
        /// A server is set and its copy is not open: its key was refused, or the copy cannot be opened.
        case failed
    }

    let folder: NotesFolder
    let host: MarfaHost
    /// True from launch until the saved server's copy has been tried.
    private(set) var isLaunching: Bool

    /// What Settings does for the connection, kept with the connection so a question put to the person is not
    /// forgotten when Settings is put away and opened again.
    let marfaSettings: MarfaSettingsModel

    @ObservationIgnored private var marfaLibrary: MarfaLibrary?

    init(folder: NotesFolder, host: MarfaHost) {
        self.folder = folder
        self.host = host
        marfaSettings = MarfaSettingsModel(host: host)
        isLaunching = host.configuredConnection != nil
        marfaSettings.beforeChange = { [weak self] in await self?.flushEditors() }
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

    /// Which library the windows show. A server's copy is shown whenever it is open; a server set whose copy is
    /// not open is never answered with the notes folder, which is not what the person asked to read. While the
    /// app leaves a server, the folder is already what comes next.
    nonisolated static func mode(hasSource: Bool, isConfigured: Bool, state: MarfaHost.State, isLaunching: Bool, isBusy: Bool) -> Mode {
        if hasSource { return .marfa }
        guard isConfigured else { return .files }
        switch state {
        case .connecting: return .opening
        case .keyRefused, .unavailable: return .failed
        case .disconnected, .online, .offline:
            if isLaunching { return .opening }
            // Leaving a server detaches its copy a moment before the address is forgotten.
            return isBusy ? .files : .failed
        }
    }

    /// The library to read, nil where there is none to show: no folder chosen yet, or a server whose copy is not
    /// open.
    var current: (any ItemLibrary)? {
        switch mode {
        case .files: folder.library
        case .marfa: marfa()
        case .opening, .failed: nil
        }
    }

    /// One library for as long as its source is the one open, so a window keeps what it holds as items change.
    private func marfa() -> MarfaLibrary? {
        guard let source = host.source else { return nil }
        if let marfaLibrary, marfaLibrary.source === source { return marfaLibrary }
        let library = MarfaLibrary(source: source)
        marfaLibrary = library
        return library
    }

    /// Hands every open page's last edit to the library it came from, and returns once each library keeps its
    /// writes on this Mac, never waiting on a server. Run before anything changes which library the windows read,
    /// and before quitting.
    func flushEditors() async {
        await Self.flush()
        folder.library?.finish()
        await marfaLibrary?.finish()
    }

    /// As `flushEditors`, for quitting: waits at most `limit`, so a library that cannot finish never keeps the app
    /// from quitting. False where it did not finish in time.
    func flushEditors(within limit: Duration) async -> Bool {
        let first = FirstOf()
        return await withCheckedContinuation { continuation in
            Task {
                await flushEditors()
                first.resume(continuation, with: true)
            }
            Task {
                try? await Task.sleep(for: limit)
                first.resume(continuation, with: false)
            }
        }
    }

    /// Resumes once, with whichever answer comes first.
    private final class FirstOf {
        private var done = false

        func resume(_ continuation: CheckedContinuation<Bool, Never>, with value: Bool) {
            guard !done else { return }
            done = true
            continuation.resume(returning: value)
        }
    }

    /// The pages first, since an edit still in a page reaches a library only by being handed over.
    private static func flush() async {
        await withCheckedContinuation { continuation in
            EditorController.flushAll { continuation.resume() }
        }
    }

    /// The app's own: the person's defaults and Keychain, and the copy in the app's own storage.
    static func standard() -> Libraries {
        #if DEBUG
        // The UI tests, the screenshots and the unit tests hosted in the app never reach the person's saved server,
        // Keychain or copies.
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("-MAPPSampleFolder")
            || environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        {
            let suite = "MAPP.SampleMarfa"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let root = URL.temporaryDirectory.appending(path: "Sample Marfa", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            return Libraries(
                folder: NotesFolder(), host: MarfaHost(defaults: defaults, keys: MemoryKeyStore(), location: location(root: root)))
        }
        #endif
        let host = MarfaHost(defaults: .standard, keys: KeychainKeyStore(), location: location())
        return Libraries(folder: NotesFolder(), host: host)
    }

    /// The initializer refuses only a root inside a notes folder, and none is given here.
    private static func location(root: URL = MarfaStoreLocation.applicationSupport) -> MarfaStoreLocation {
        do {
            return try MarfaStoreLocation(root: root)
        } catch {
            preconditionFailure("A copy’s location was refused: \(error)")
        }
    }
}
