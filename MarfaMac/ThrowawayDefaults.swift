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
        let dayAgo = Date(timeIntervalSinceNow: -86_400)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < dayAgo { try? FileManager.default.removeItem(at: file) }
        }
        atexit {
            for path in ThrowawayDefaults.held.withLock({ $0 }) { try? FileManager.default.removeItem(atPath: path + ".plist") }
        }
    }()

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
