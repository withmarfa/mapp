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

    /// Changes a Marfa library could not keep because its copy closed first, for the window in front to tell,
    /// since by then the windows read another library and the one that refused them is shown nowhere.
    var unkept: Unkept?

    nonisolated struct Unkept: Hashable, Sendable {
        var title: String
        var message: String
        /// The text the person typed that no library holds, for them to put back.
        var text: String?
    }

    @ObservationIgnored private var marfaLibrary: MarfaLibrary?

    init(folder: NotesFolder, host: MarfaHost) {
        self.folder = folder
        self.host = host
        marfaSettings = MarfaSettingsModel(host: host)
        isLaunching = host.configuredConnection != nil
        host.handOverEdits = { [weak self] in await self?.flushEditors() ?? false }
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
    /// not open is never answered with the notes folder, which is not what the person asked to read. Leaving a
    /// server forgets its address first, so the folder is what comes next; a copy closed to open again, as when
    /// a key is replaced, is waited for, never shown as the folder in between.
    nonisolated static func mode(hasSource: Bool, isConfigured: Bool, state: MarfaHost.State, isLaunching: Bool, isBusy: Bool) -> Mode {
        if hasSource { return .marfa }
        guard isConfigured else { return .files }
        switch state {
        case .connecting: return .opening
        case .keyRefused, .unavailable, .otherVersion, .inUse: return isBusy ? .opening : .failed
        case .disconnected, .online, .offline: return isLaunching || isBusy ? .opening : .failed
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
        library.onNotKept = { [weak self] in self?.tell($0) }
        marfaLibrary = library
        return library
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
        folder.library?.finish()
        await marfaLibrary?.finish()
        return true
    }

    /// Quitting waits at most `limit` and is cancelled if the editors or library cannot finish.
    func flushEditors(within limit: Duration) async -> Bool {
        let first = FirstOf()
        return await withCheckedContinuation { continuation in
            Task {
                let kept = await flushEditors()
                first.resume(continuation, with: kept)
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
    private static func flush() async -> Bool {
        await withCheckedContinuation { continuation in
            EditorController.flushAll { continuation.resume(returning: $0) }
        }
    }

    /// The app's own: the person's defaults and Keychain, and the copy in the app's own storage.
    static func standard() -> Libraries {
        #if DEBUG
        // The UI tests, the screenshots and the unit tests hosted in the app never reach the person's saved server,
        // Keychain, copies or notes folder.
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("-MAPPSampleFolder")
            || environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        {
            let suite = "MAPP.SampleMarfa"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let root = URL.temporaryDirectory.appending(path: "Sample Marfa", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            // A debug build can be pointed at a test server by hand. The key stays in memory and the address goes
            // only to the sample defaults cleared above, so nothing reaches the Keychain or the saved server.
            var presets: [MarfaConnection: String] = [:]
            var server: MarfaConnection?
            if ProcessInfo.processInfo.arguments.contains("-MAPPSampleFolder"),
                let address = environment["MAPP_TEST_MARFA_URL"], let connection = try? MarfaConnection(address: address),
                let key = environment["MAPP_TEST_MARFA_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
            {
                presets[connection] = key
                server = connection
            }
            let host = MarfaHost(defaults: defaults, keys: MemoryKeyStore(presets), location: location(root: root))
            if let server { host.presetTestServer(server) }
            return Libraries(folder: NotesFolder(defaults: defaults), host: host)
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
