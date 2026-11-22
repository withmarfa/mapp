import Foundation

/// What Connection's "MAPP’s Settings" section says in each state of `PreferencesSync.Standing`, in the app's words.
nonisolated struct ConnectionSettings: Equatable, Sendable {
    nonisolated enum Action: Equatable, Sendable {
        /// Moves the settings out of the Marfa.
        case remove
        /// Signs in again, asking for what keeps them in the Marfa.
        case allowMore
        /// Keeps this Mac's settings in the Marfa again after they were removed.
        case keepAgain
        case none
    }

    let standing: PreferencesSync.Standing
    /// The connected Marfa's name.
    let name: String

    /// Not shown without a Marfa, as in the sample library.
    var isShown: Bool { standing != .off(.noMarfa) }

    var title: String {
        switch standing {
        case .syncing: String(localized: "Kept in \(name)")
        case .off(.needsPermission), .off(.removed), .off(.noMarfa): String(localized: "Kept on This Mac Only")
        case .off(.notFilled): String(localized: "Not Ready Yet")
        }
    }

    var line: String? {
        switch standing {
        case .syncing: String(localized: "Every Mac that connects to it uses them.")
        case .off(.needsPermission):
            String(localized: "MAPP isn’t allowed to keep them in \(name) yet. Once it is, every Mac that connects uses them.")
        case .off(.notFilled): String(localized: "MAPP keeps them in \(name) once this Mac has finished downloading it.")
        case .off(.removed): String(localized: "They were removed from \(name). This Mac keeps its own.")
        case .off(.noMarfa): nil
        }
    }

    var action: Action {
        switch standing {
        case .syncing: .remove
        case .off(.needsPermission): .allowMore
        case .off(.removed): .keepAgain
        case .off(.notFilled), .off(.noMarfa): .none
        }
    }

    var actionTitle: String? {
        switch action {
        case .remove: String(localized: "Remove…")
        case .allowMore: String(localized: "Allow More…")
        case .keepAgain: String(localized: "Keep in Marfa Again")
        case .none: nil
        }
    }

    /// What stays on each Mac, whatever the state.
    static var footer: String {
        String(localized: "Window sizes and positions, column widths and On This Mac stay on each Mac.")
    }

    /// The question before Remove… takes the settings out of the Marfa.
    var removeTitle: String { String(localized: "Remove MAPP’s Settings from \(name)?") }
    var removeMessage: String {
        String(localized: "Every Mac that connects to \(name) loses them. This Mac keeps its own, and your items stay.")
    }

    /// The checkbox on Disconnect's alert.
    var disconnectChoice: String { String(localized: "Also remove MAPP’s settings from \(name)") }
}
