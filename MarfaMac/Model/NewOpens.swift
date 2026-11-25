import Foundation

/// What New Item opens, as Settings > General > New Opens says: the one line, or the text form, which takes text and
/// files as well. One word in the defaults (`key`), which syncs through the Marfa (`PreferencesMap`); a word this
/// version does not know reads as the line.
nonisolated enum NewOpens: String, CaseIterable {
    case line
    case textForm

    static let key = "newOpens"

    static func stored(in defaults: UserDefaults = .standard) -> NewOpens {
        defaults.string(forKey: key).flatMap(NewOpens.init) ?? .line
    }

    var title: String {
        switch self {
        case .line: String(localized: "One Line")
        case .textForm: String(localized: "Text Form")
        }
    }
}
