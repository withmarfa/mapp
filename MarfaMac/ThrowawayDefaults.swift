#if DEBUG
import Foundation
import Synchronization

/// Unit-test defaults backed by a temporary plist. On macOS 27, an absolute suite path lets the process write the
/// file directly instead of having `cfprefsd` write a named domain under `~/Library/Preferences`.
/// Keep the returned object alive for as long as the test needs the domain.
nonisolated final class ThrowawayDefaults: UserDefaults, @unchecked Sendable {
    /// The domain's name, which opens the same defaults again (`UserDefaults(suiteName:)`) while this object lives.
    let suite: String

    private static let folder = AppPaths.temporary("Throwaway Defaults")
    /// The files of the defaults not yet released.
    private static let held = Mutex<Set<String>>([])

    /// Sweeps the folder once, and removes what is still held when the process exits.
    private static let start: Void = {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sweep()
        atexit {
            for path in ThrowawayDefaults.held.withLock({ $0 }) { try? FileManager.default.removeItem(atPath: path + ".plist") }
        }
    }()

    /// Removes this helper's own files that a killed run left, once a day old: only regular files named as `make`
    /// names them, and only while the folder resolves inside the temporary folder, so it never follows a link out.
    private static func sweep() {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"
        guard folder.resolvingSymlinksInPath().path.hasPrefix(temporary) else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let dayAgo = Date(timeIntervalSinceNow: -86_400)
        let ours = /-[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.plist$/
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [] {
            guard file.lastPathComponent.contains(ours), let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < dayAgo else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Defaults of their own, named for what they serve, that stay until the returned object is released.
    static func make(_ name: String) -> ThrowawayDefaults {
        _ = start
        let path = folder.appending(path: "\(name)-\(UUID().uuidString)").path
        held.withLock { _ = $0.insert(path) }
        return ThrowawayDefaults(path: path)!
    }

    private init?(path: String) {
        suite = path
        super.init(suiteName: path)
    }

    deinit {
        removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
        Self.held.withLock { _ = $0.remove(suite) }
    }
}
#endif
