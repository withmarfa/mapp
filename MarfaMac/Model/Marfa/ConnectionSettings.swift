import Foundation

/// What Connection's "This App’s Settings" section says in each state of `PreferencesSync.Standing`, in the app's words.
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
        case .syncing: String(localized: "Each Mac uses the groups it syncs.")
        case .off(.needsPermission):
            String(localized: "Allow the app to keep the groups you sync in \(name).")
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

    /// What stays on each Mac, whatever the state.
    static var footer: String {
        String(localized: "Each Mac keeps its own window sizes and positions, column widths, global shortcuts, and On This Mac settings.")
    }

    /// The question before Remove… takes the settings out of the Marfa.
    var removeTitle: String { String(localized: "Remove This App’s Settings from \(name)?") }
    var removeMessage: String {
        String(localized: "The shared settings are removed from \(name). Each Mac keeps its current settings. Your items stay.")
    }

    /// The checkbox on Disconnect's alert.
    var disconnectChoice: String { String(localized: "Also remove this app’s settings from \(name)") }

    /// Under the checkbox on the question about changes that wait: removing the settings sends the queue, so it can't go
    /// with discarding what is in it.
    var sendsWaitingChanges: String {
        String(localized: "Removing them also sends the changes above, so it can’t be combined with discarding them.")
    }

    /// Where one of the changes that wait is the removal itself, which has no text to show.
    var removalWaiting: String {
        String(localized: "One of them removes this app’s settings from \(name). Discard the copy and the settings stay there.")
    }

    /// Why Disconnect stopped, where the removal could not be made without sending what the person chose to discard.
    var discardedChangesWait: String {
        String(localized: "Removing them also sends the changes you chose to discard. Keep the copy to send them, or disconnect anyway and the settings stay in \(name).")
    }

    /// Why Disconnect stopped, where the server did not take the removal.
    var removalNotTaken: String {
        String(localized: "The app couldn’t finish removing them from \(name), so you’re still connected. Disconnect anyway and they may stay there.")
    }
}
