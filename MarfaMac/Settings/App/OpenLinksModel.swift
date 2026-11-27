import AppKit
import Observation

/// One app that registered `marfa://`, as the pop-up lists it.
struct LinkApp: Identifiable {
    let url: URL
    let name: String
    let title: String
    let icon: NSImage
    var id: URL { url }

    /// What the naming of a group of apps needs of one: how it is called and where it sits.
    struct Candidate: Equatable {
        let url: URL
        let name: String
        let version: String?
        /// The folder's name, as Finder shows it.
        let folder: String
        /// The folder's path, for two builds whose folders share a name.
        let path: String
    }

    /// The menu's titles, in order. An app whose name no other shares keeps its name; apps that share one are told apart by
    /// version and folder ("Marfa (0.0.12) in Applications"), and by the folder's whole path where those match too.
    static func titles(for candidates: [Candidate]) -> [String] {
        let sharing = Dictionary(grouping: candidates, by: \.name)
        return candidates.map { candidate in
            let group = sharing[candidate.name] ?? []
            guard group.count > 1 else { return candidate.name }
            let sameFolder = group.filter { $0.folder == candidate.folder && $0.version == candidate.version }
            let place = sameFolder.count > 1 ? candidate.path : candidate.folder
            if let version = candidate.version {
                return String(localized: "\(candidate.name) (\(version)) in \(place)")
            }
            return String(localized: "\(candidate.name) in \(place)")
        }
    }
}

/// The apps that open a `marfa://` link on this Mac and the one macOS holds as the default. macOS keeps the default; this
/// stores nothing and reads it back after every change, so the pop-up shows what macOS holds and never what was chosen.
@Observable @MainActor final class OpenLinksModel {
    static let scheme = "marfa"
    /// Only the scheme matters to the system's answer.
    private static let sample = URL(string: "\(scheme)://instance/item")!

    private(set) var apps: [LinkApp] = []
    private(set) var current: URL?
    private(set) var isChanging = false
    /// The app macOS kept when a change was refused or failed, shown in the one line under the title.
    private(set) var refusal: Refusal?

    struct Refusal: Equatable {
        /// The app macOS still opens links in, if it names one.
        let keptTitle: String?
    }

    /// Reads the list and the default again. The page does it when it appears and when the app becomes active, since
    /// another app can register or take the scheme at any time.
    func refresh() {
        refusal = nil
        read()
    }

    func choose(_ url: URL) async {
        guard url != current, !isChanging else { return }
        isChanging = true
        refusal = nil
        var failed = false
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpenURLsWithScheme: Self.scheme)
        } catch {
            failed = true
        }
        read()
        // Declining macOS's own question is not an error to the call, so the read-back decides.
        if failed || current != url {
            refusal = Refusal(keptTitle: apps.first { $0.url == current }?.title)
        }
        isChanging = false
    }

    private func read() {
        let workspace = NSWorkspace.shared
        var urls = workspace.urlsForApplications(toOpen: Self.sample)
        let defaultApp = workspace.urlForApplication(toOpen: Self.sample)
        // The default is listed even where macOS leaves it out of the registered apps, so the pop-up never shows a blank.
        if let defaultApp, !urls.contains(defaultApp) { urls.append(defaultApp) }
        let candidates = urls.map(Self.candidate)
        let titles = LinkApp.titles(for: candidates)
        apps = zip(candidates, titles).map { candidate, title in
            let icon = workspace.icon(forFile: candidate.url.path)
            icon.size = NSSize(width: 16, height: 16)
            return LinkApp(url: candidate.url, name: candidate.name, title: title, icon: icon)
        }
        current = defaultApp
    }

    private static func candidate(for url: URL) -> LinkApp.Candidate {
        let manager = FileManager.default
        var name = manager.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        let bundle = Bundle(url: url)
        if bundle?.bundleIdentifier == AppPaths.bundleIdentifier { name = String(localized: "Marfa for Mac") }
        let folder = url.deletingLastPathComponent()
        return LinkApp.Candidate(
            url: url, name: name, version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            folder: manager.displayName(atPath: folder.path), path: (folder.path as NSString).abbreviatingWithTildeInPath)
    }
}
