import Foundation

/// What General says about settings kept in the Marfa, and what Sign Out says about removing them.
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
        case .syncing: String(localized: "Kept in this Marfa")
        case .off(.needsPermission), .off(.removed), .off(.noMarfa): String(localized: "Kept on this Mac only")
        case .off(.notFilled): String(localized: "Not ready yet")
        }
    }

    var line: String? {
        switch standing {
        case .syncing: String(localized: "Every Mac that connects to it uses them.")
        case .off(.needsPermission):
            String(localized: "The app isn’t allowed to keep them in \(name) yet. Once it is, every Mac that connects uses them.")
        case .off(.notFilled): String(localized: "The app keeps them in \(name) once this Mac has finished downloading it.")
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

    /// The question before Remove… takes the settings out of the Marfa.
    var removeTitle: String { String(localized: "Remove This App’s Settings from \(name)?") }
    var removeMessage: String {
        String(localized: "Every Mac that connects to \(name) loses them. This Mac keeps its own, and your items stay.")
    }

    /// The checkbox on the Sign Out alert.
    var signOutChoice: String { String(localized: "Also remove this app’s settings from this Marfa") }

    /// Under the checkbox on the question about changes that wait: removing the settings sends the queue, so it can't go
    /// with discarding what is in it.
    var sendsWaitingChanges: String {
        String(localized: "Removing them also sends the changes above, so it can’t be combined with discarding them.")
    }

    /// Where one of the changes that wait is the removal itself, which has no text to show.
    var removalWaiting: String {
        String(localized: "One of them removes this app’s settings from \(name). Discard the copy and the settings stay there.")
    }

    /// Why sign-out stopped when removal would have sent what the person chose to discard.
    var discardedChangesWait: String {
        String(localized: "Removing them also sends the changes you chose to discard. Keep the copy to send them, or sign out anyway and the settings stay in \(name).")
    }

    /// Why sign-out stopped when the server did not take the removal.
    var removalNotTaken: String {
        String(localized: "The app couldn’t finish removing them from \(name), so you’re still signed in. Sign out anyway and they may stay there.")
    }
}
