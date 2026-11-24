#if DEBUG
import Foundation
import Synchronization

/// Defaults that a unit test, the test host or a preview uses once and loses, kept in a file in the temporary folder
/// and removed with the object, so a run leaves nothing behind.
///
/// A named domain (`UserDefaults(suiteName:)`) leaves a file in `~/Library/Preferences` that `removePersistentDomain`
/// empties but never removes, and `cfprefsd` writes it late, so deleting it by hand is not reliable either. A suite
/// named by an absolute path is kept at that path instead, written by the process itself. The file goes when the last
/// reference to the defaults does, so a test needs no teardown: hold the defaults for as long as the test uses them.
/// What a page or window outlives the test with goes when the process exits, and what a killed run left goes at the
/// next run's first use, once a day old.
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
        // Only the global domain and the app's own are refused, and a path is neither.
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
