import Foundation

/// Whether the windows that were open come back when the app opens again, as Settings > General > Opening says. It is
/// the system's own `NSQuitAlwaysKeepsWindows`, so unset the answer is the Mac's ("Close windows when quitting an
/// application" is its inverse) and the app writes nothing. Only a change in Settings writes the key in the app's own
/// defaults, and Reset removes it, so the Mac's answer stands again. Never written to Marfa.
nonisolated enum ReopenWindows {
    static let key = "NSQuitAlwaysKeepsWindows"
    /// Where the answer is when no setting of the Mac says: windows come back.
    static let standard = true

    /// The app's own answer if one was set, else the Mac's, else the standard.
    static func stored(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? standard
    }

    /// The Mac's own answer, as the global setting says it, or nil where the Mac has none.
    static func system() -> Bool? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
    }
}
