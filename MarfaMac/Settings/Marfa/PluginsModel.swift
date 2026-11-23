import Foundation
import Marfa
import MarfaAPI
import Observation

/// A bundle file the owner chose to install, as the app read it.
enum PluginFileChoice {
    case file(name: String, path: String, data: Data)
    /// The file could not be read, or is larger than a plugins release serves.
    case unreadable(name: String)
}

/// What the Plugins page asks of the app that holds it: how many items a type holds, and a file the owner chooses. In the
/// app's own terms, so a test scripts them.
struct PluginsAccess {
    var ownItems: (String) -> Int
    var chooseBundle: () async -> PluginFileChoice?
}

/// The Plugins page: the plugins the server holds, the newer versions the plugins release lists, and the plugins it lists that
/// are not installed. The release is read by the app itself and every bundle is checked against the digest the release lists
/// before anything is shown of it or sent. A bundle is installed as its bytes, unchanged. One whose types carry guidance is sent
/// like any other, and the server's answer decides: it asks the owner to sign in again (the call shows that in place and sends
/// again), or, while it takes guidance only from the command line, refuses, and the page then gives the command.
@Observable @MainActor final class PluginsModel {
    /// The plugins release as the page reads it. A release that cannot be read leaves the rest of the page working.
    enum Release: Equatable {
        case reading
        case read([ReleasePlugin])
        case unreadable(PluginFailure)
        /// A first read that was cancelled before any release was held. Not a failure: Available offers Try Again.
        case notRead
    }

    /// A bundle of the release, read and checked.
    enum Bundle: Equatable {
        case reading
        case read(ReleaseBundle)
        case failed(PluginFailure)
    }

    /// A newer version of an installed plugin.
    struct Update: Identifiable, Equatable {
        let installed: InstalledPlugin
        let entry: ReleasePlugin

        var id: String { entry.name }
    }

    /// What the last thing asked did not do, with the plugin it was about, where it was one.
    struct Problem: Equatable {
        var plugin: String?
        var title: String
        var failure: PluginFailure
    }

    /// What a removal would take and leave, shown before it is sent.
    struct Removal: Identifiable, Equatable {
        let plugin: InstalledPlugin
        /// Each type the plugin installed, with its name and the items it holds now.
        let types: [(id: String, title: String, items: Int)]

        var id: String { plugin.name }
        var items: Int { types.reduce(0) { $0 + $1.items } }

        static func == (lhs: Removal, rhs: Removal) -> Bool { lhs.plugin == rhs.plugin }
    }

    /// A line the owner closes: what a finished install, update or removal did.
    struct Notice: Equatable {
        var title: String
        var line: String
    }

    private let context: OwnerContext
    private let calls: any PluginCalls
    private let access: PluginsAccess

    private(set) var installed: [InstalledPlugin] = []
    private(set) var failure: OwnerFailure?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var release = Release.reading
    private(set) var bundles: [String: Bundle] = [:]
    private(set) var typeInfo: [String: PluginTypeInfo] = [:]
    /// The names of the connector hosts the page has read, by their IDs.
    private(set) var hostNames: [String: String] = [:]
    private(set) var working: Set<String> = []
    private(set) var isInstallingFile = false
    private(set) var problem: Problem?
    private(set) var notice: Notice?
    /// The commands the owner is given for a plugin that installs only from the command line, by the plugin's name.
    private(set) var commands: [String: String] = [:]
    var removal: Removal?
    /// The command last copied, for the button to say so.
    private(set) var copied: String?
    /// Loads that arrived while one was running. Each is resumed when that one finishes, and then reads for itself.
    private var loadsWaiting: [CheckedContinuation<Void, Never>] = []

    init(context: OwnerContext, calls: any PluginCalls, access: PluginsAccess) {
        self.context = context
        self.calls = calls
        self.access = access
    }

    // MARK: Reading

    func load() async {
        // One already running may be cancelled and leave nothing read. This one waits, then reads.
        if isLoading {
            await withCheckedContinuation { loadsWaiting.append($0) }
            guard !Task.isCancelled else { return }
            await load()
            return
        }
        isLoading = true
        defer {
            isLoading = false
            let waiting = loadsWaiting
            loadsWaiting = []
            waiting.forEach { $0.resume() }
        }
        do {
            installed = try await calls.installed()
            failure = nil
        } catch {
            failure = error
            hasLoaded = true
            await context.learn(from: error)
            return
        }
        // What a type is called is a nicety: without it the plugin's own IDs show.
        typeInfo = (try? await calls.typeInfo()) ?? typeInfo
        // The server's answers are all the page needs to show what is installed; the release is read after, in its own row.
        hasLoaded = true
        await readRelease()
    }

    /// Reads the release again. A release that cannot be read drops every bundle read before. A read that was cancelled puts
    /// back the release and the bundles held before it, and is no failure. A first read that never finished is `notRead`, so
    /// Available offers Try Again instead of staying on Reading. Each newer version's bundle is then read.
    func readRelease() async {
        let heldRelease = release
        let heldBundles = bundles
        release = .reading
        bundles = [:]
        do {
            let entries = try await calls.release()
            release = .read(entries)
        } catch {
            if error == .canceled {
                switch heldRelease {
                case .reading:
                    release = .notRead
                    bundles = [:]
                case .read, .unreadable, .notRead:
                    release = heldRelease
                    bundles = heldBundles
                }
            } else {
                release = .unreadable(error)
            }
            return
        }
        for update in updates { await readBundle(of: update.entry) }
    }

    /// Try Again for a bundle the page could not use. The release is read first, then the bundle of the entry that read lists.
    /// Where the release no longer lists the plugin, nothing of it is read and the page says so.
    func readAgain(_ name: String) async {
        let title = plugin(name)?.title ?? entry(name)?.title ?? name
        await readRelease()
        guard case .read = release, let fresh = entry(name) else {
            if case .read = release {
                notice = Notice(
                    title: String(localized: "Not in the Release"), line: String(localized: "The release no longer lists \(title)."))
            }
            return
        }
        await readBundle(of: fresh)
    }

    func readBundle(of entry: ReleasePlugin) async {
        if case .read? = bundles[entry.name] { return }
        bundles[entry.name] = .reading
        do {
            bundles[entry.name] = .read(try await calls.bundle(of: entry))
        } catch {
            bundles[entry.name] = error == .canceled ? nil : .failed(error)
        }
    }

    /// Reads one plugin as the server holds it now, for its own page, with the name of the machine its connector runs on.
    func open(_ name: String) async {
        typeInfo = (try? await calls.typeInfo()) ?? typeInfo
        do {
            let plugin = try await calls.plugin(name)
            if let index = installed.firstIndex(where: { $0.name == name }) { installed[index] = plugin } else { installed.append(plugin) }
        } catch {
            if error == .notFound { installed.removeAll { $0.name == name } } else { await context.learn(from: error) }
        }
        if let host = installed.first(where: { $0.name == name })?.host, hostNames[host] == nil, context.grants().contains(.connectorsManage) {
            hostNames[host] = try? await calls.hostName(host)
        }
    }

    func plugin(_ name: String) -> InstalledPlugin? { installed.first { $0.name == name } }

    var entries: [ReleasePlugin] {
        if case .read(let entries) = release { entries } else { [] }
    }

    func entry(_ name: String) -> ReleasePlugin? { entries.first { $0.name == name } }

    /// The installed plugins the release lists a newer version of.
    var updates: [Update] {
        installed.compactMap { plugin in
            guard let entry = entry(plugin.name), let have = PluginVersion(plugin.version), have < entry.version else { return nil }
            return Update(installed: plugin, entry: entry)
        }
    }

    func update(for name: String) -> Update? { updates.first { $0.id == name } }

    /// What the release lists that is not installed.
    var available: [ReleasePlugin] {
        let held = Set(installed.map(\.name))
        return entries.filter { !held.contains($0.name) }
    }

    func bundle(_ name: String) -> ReleaseBundle? {
        if case .read(let bundle)? = bundles[name] { bundle } else { nil }
    }

    /// The installed plugin's types, in the order the server lists them, named as the server names them.
    func typeTitle(_ id: String) -> String { typeInfo[id]?.title ?? id }

    func hostName(of plugin: InstalledPlugin) -> String? { plugin.host.flatMap { hostNames[$0] } }

    func items(ofType id: String) -> Int { access.ownItems(id) }

    /// The command the owner is given for `name`, once the server refused it for its guidance.
    func heldCommand(_ name: String) -> String? { commands[name] }

    /// The command that installs or updates `name` from the release.
    static func command(for name: String) -> String { "marfa plugins install \(name)" }

    /// What an update adds, from the bundle: its new types, edge types and connector. Empty until the bundle is read.
    func adds(_ update: Update) -> [String] {
        guard let bundle = bundle(update.id) else { return [] }
        let known = Set(update.installed.types)
        let newTypes = bundle.types.filter { !known.contains($0.id) }.map { $0.label ?? $0.id }
        let knownEdges = Set(update.installed.edgeTypes)
        let newEdges = bundle.edgeTypes.filter { !knownEdges.contains($0.id) }
        var parts: [String] = []
        if !newTypes.isEmpty { parts.append(PluginWording.addedTypes(newTypes)) }
        if !newEdges.isEmpty { parts.append(PluginWording.addedEdgeTypes(newEdges.count)) }
        if update.installed.connector == nil, bundle.connector != nil { parts.append(String(localized: "a connector")) }
        return parts
    }

    // MARK: Installing and updating

    func isWorking(_ name: String) -> Bool { working.contains(name) }

    /// Installs, or updates to, what the release lists for `entry`. The bundle is read and checked first.
    func install(_ entry: ReleasePlugin, asUpdate: Bool = false) async {
        let name = entry.name
        guard !working.contains(name) else { return }
        working.insert(name)
        defer { working.remove(name) }
        problem = nil
        notice = nil
        let title = asUpdate ? String(localized: "Not Updated") : String(localized: "Not Installed")
        await readBundle(of: entry)
        guard let bundle = bundle(name) else {
            if case .failed(let failure)? = bundles[name] { problem = Problem(plugin: name, title: title, failure: failure) }
            return
        }
        await send(bundle.bytes, plugin: name, title: title)
    }

    /// Installs a bundle file the owner chose, exactly as it is.
    func installFile() async {
        guard !isInstallingFile, let choice = await access.chooseBundle() else { return }
        isInstallingFile = true
        defer { isInstallingFile = false }
        problem = nil
        notice = nil
        commands[""] = nil
        let title = String(localized: "Not Installed From a File")
        switch choice {
        case .unreadable(let name):
            problem = Problem(
                plugin: nil, title: title,
                failure: .owner(.refused(String(localized: "“\(name)” couldn’t be read as a plugin bundle."))))
        case .file(_, let path, let data):
            await send(data, plugin: nil, title: title, filePath: path)
        }
    }

    private func send(_ bundle: Data, plugin: String?, title: String, filePath: String? = nil) async {
        do {
            let answer = try await calls.install(bundle)
            commands[answer.name] = nil
            await reloadAfterInstall(answer)
        } catch {
            switch error {
            case .carriesGuidance:
                if let plugin {
                    commands[plugin] = Self.command(for: plugin)
                } else if let filePath {
                    commands[""] = Self.command(forFile: filePath)
                }
            case .canceled:
                // The owner closed the sign-in the server asked for: nothing was sent and nothing is said.
                break
            case .owner(let owner):
                await context.learn(from: owner)
                problem = Problem(plugin: plugin, title: title, failure: error)
            default:
                problem = Problem(plugin: plugin, title: title, failure: error)
            }
        }
    }

    /// The command that installs a bundle file, with its path quoted for a shell.
    static func command(forFile path: String) -> String {
        "marfa plugins install '" + path.replacing("'", with: "'\\''") + "'"
    }

    private func reloadAfterInstall(_ answer: PluginInstallAnswer) async {
        // Where the list cannot be read the bundle stays, since the page that is showing the plugin reads from it.
        let reloaded = try? await calls.installed()
        if let reloaded {
            installed = reloaded
            bundles[answer.name] = nil
        }
        typeInfo = (try? await calls.typeInfo()) ?? typeInfo
        let held = plugin(answer.name)
        let verb =
            switch answer.outcome {
            case .installed: String(localized: "Installed \(held?.title ?? answer.name) \(answer.version).")
            case .updated: String(localized: "Updated \(held?.title ?? answer.name) to \(answer.version).")
            case .unchanged: String(localized: "\(held?.title ?? answer.name) \(answer.version) is already installed. Nothing changed.")
            }
        var line = verb
        if answer.outcome != .unchanged, let held, held.connector != nil, held.host == nil {
            line += " " + String(localized: "Its connector runs nowhere until you choose a machine for it.")
        }
        if reloaded == nil { line += " " + String(localized: "The list of plugins couldn’t be read, so what is shown may be out of date.") }
        notice = Notice(title: String(localized: "Done"), line: line)
        // The updates left are read again, so each still says what it adds.
        for update in updates { await readBundle(of: update.entry) }
    }

    // MARK: Removing

    /// Asks before removing: what stops and what stays, with the items the plugin's types hold now.
    func askToRemove(_ plugin: InstalledPlugin) {
        problem = nil
        notice = nil
        removal = Removal(
            plugin: plugin, types: plugin.types.map { (id: $0, title: typeTitle($0), items: items(ofType: $0)) })
    }

    func cancelRemoval() { removal = nil }

    func confirmRemoval() async {
        guard let asked = removal else { return }
        removal = nil
        let name = asked.plugin.name
        working.insert(name)
        defer { working.remove(name) }
        do {
            let answer = try await calls.remove(name)
            installed.removeAll { $0.name == name }
            commands[name] = nil
            notice = Notice(title: String(localized: "Removed"), line: PluginWording.removed(answer, title: asked.plugin.title))
        } catch {
            problem = Problem(plugin: name, title: String(localized: "Not Removed"), failure: .owner(error))
            await context.learn(from: error)
            if error == .notFound {
                installed.removeAll { $0.name == name }
            }
        }
    }

    func closeNotice() { notice = nil }

    func closeProblem() { problem = nil }

    func copyCommand(_ command: String) {
        OwnerClipboard.copyText(command)
        copied = command
    }
}
