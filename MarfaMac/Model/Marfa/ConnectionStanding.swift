import Foundation
import Marfa

/// The mark on the configured Marfa’s address. A connection problem takes precedence over an available server update.
nonisolated struct ConnectionAddressStatus: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case green, orange, red }

    let symbol: String
    let tone: Tone
    let words: String

    init(state: MarfaConnectionState, updateReady: Bool) {
        let connection = ConnectionStatus(state)
        switch state {
        case .online where updateReady:
            self.init("arrow.down.circle.fill", .orange, String(localized: "Update ready"))
        case .online:
            self.init("checkmark.circle.fill", .green, connection.title)
        case .connecting:
            self.init("ellipsis.circle.fill", .orange, connection.title)
        case .offline:
            self.init("exclamationmark.circle.fill", .orange, String(localized: "Not answering"))
        case .keyRefused:
            self.init("xmark.circle.fill", .red, String(localized: "Sign-in expired"))
        case .disconnected, .unavailable, .otherVersion, .inUse:
            self.init("xmark.circle.fill", .red, connection.title)
        }
    }

    private init(_ symbol: String, _ tone: Tone, _ words: String) {
        self.symbol = symbol
        self.tone = tone
        self.words = words
    }
}

/// What the Marfa section of Connection holds in each state: who is signed in, what the owner has allowed the app, and
/// what waits to be sent.
nonisolated struct ConnectionAccount: Equatable, Sendable {
    /// Every owner permission, as every sign-in and Allow More asks for them (`SystemSignIns.askedAtSignIn`): what
    /// Connection counts, as a key's and an app's pages count them.
    static let asked = SystemSignIns.askedAtSignIn

    /// The permissions the app holds, and how many of the `asked` ones that is; nil where the sign-in cannot be read or
    /// the server is not reached, when nothing is said.
    var held: Int?
    var total: Int { Self.asked.count }
    var holdsAll: Bool { held == total }
    var unsent: String
    var unsentLine: String?
    var showsPermissions: Bool
    /// Whether Signed In As is shown: whenever the sign-in is held, so also while the server does not answer.
    var showsName: Bool
    /// Signed In As cannot be told because the sign-in may not read the owner's name, as one made before the app asked for it
    /// cannot; Allow More gives it, beside Permissions.
    var offersName: Bool
    /// Whether Permissions offers Allow More: the sign-in lacks something the app asks for at sign-in
    /// (`MarfaHost.lacksAsked`), an owner permission, the read of the name or a scope the app began to ask for later.
    var offersMore: Bool

    init(
        state: MarfaConnectionState, grants: Set<InstancePermission>, grantsRead: Bool, readsProfile: Bool = true, lacksAsked: Bool = false,
        waiting: Int?
    ) {
        let reached = state == .online || state == .connecting
        showsPermissions = reached && grantsRead
        switch state {
        case .online, .connecting, .offline: showsName = true
        default: showsName = false
        }
        let count = grants.intersection(Self.asked).count
        held = showsPermissions ? count : nil
        offersName = showsPermissions && !readsProfile
        offersMore = showsPermissions && (count != Self.asked.count || lacksAsked || !readsProfile)
        unsent = waiting.map { $0 > 0 ? Words.changes($0) : String(localized: "None") } ?? String(localized: "Unknown")
        switch state {
        case .keyRefused: unsentLine = (waiting ?? 0) > 0 ? String(localized: "Sent once you sign in again.") : nil
        case .offline: unsentLine = (waiting ?? 0) > 0 ? String(localized: "Sent when this Marfa answers.") : nil
        default: unsentLine = nil
        }
    }

    /// What sits under Signed In As where the name is not read: nothing unless Allow More is there to give it.
    var nameLine: String? {
        offersName ? String(localized: "Allow More lets the app read the owner’s name.") : nil
    }

    /// What the count is of, and what Allow More adds. The count is of owner permissions, which open what the app may
    /// manage (keys, webhooks, backups). Allow More also asks for the rest of `SystemSignIns.scopes` (items, profile and
    /// the app's own settings), so with every permission held it can still be offered.
    var permissionsLine: String {
        if !holdsAll { return String(localized: "What you’ve allowed this app to manage. Allow More asks for the rest.") }
        if offersMore { return String(localized: "Every permission is allowed. Allow More asks for other access the app needs.") }
        return String(localized: "What you’ve allowed this app to manage.")
    }

    /// "All 14" or "12 of 14", where the sign-in can be read.
    var permissionsValue: String? {
        guard let held else { return nil }
        return holdsAll ? String(localized: "All \(total)") : String(localized: "\(held) of \(total)")
    }
}
