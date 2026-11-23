import Foundation

/// Folders this copy of the app owns. The directory is named for the bundle identifier, so a Debug copy, a Release
/// copy and Marfa's command line never read or remove one another's files.
nonisolated enum AppPaths {
    /// The release identifier, used where the running bundle has none.
    static let fallbackBundleIdentifier = "com.withmarfa.marfa"

    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier

    static var applicationSupport: URL { applicationSupport(for: bundleIdentifier) }

    static func applicationSupport(for bundleIdentifier: String) -> URL {
        URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    static var temporaryRoot: URL { temporaryRoot(for: bundleIdentifier) }

    static func temporaryRoot(for bundleIdentifier: String) -> URL {
        URL.temporaryDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    static func temporary(_ name: String, for bundleIdentifier: String = AppPaths.bundleIdentifier) -> URL {
        temporaryRoot(for: bundleIdentifier).appending(path: name, directoryHint: .isDirectory)
    }
}
