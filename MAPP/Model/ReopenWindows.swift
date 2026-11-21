import Foundation

/// Whether the windows that were open come back when the app opens again, as Settings > General > Opening says. A Mac
/// setting, one value in the defaults (`key`), never written to Marfa. The system keeps its own answer under
/// `systemKey`, which `apply` sets from the person's, so the choice holds whatever the Mac's own setting says.
nonisolated enum ReopenWindows {
    static let key = "reopenWindows"
    static let systemKey = "NSQuitAlwaysKeepsWindows"
    static let standard = true

    static func stored(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? standard
    }

    static func apply(to defaults: UserDefaults = .standard) {
        defaults.set(stored(in: defaults), forKey: systemKey)
    }
}
