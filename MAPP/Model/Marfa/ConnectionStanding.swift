import Foundation
import Marfa

/// The words of the Connection page's head and of its Account section, as state in, words out, so each state of the page
/// is tested without a view.
nonisolated enum ConnectionHeadWording {
    /// "Up to date 2 minutes ago", or "Up to date" before the first sync has finished.
    static func upToDate(since synced: Date?, now: Date, locale: Locale = .current) -> String {
        guard let synced else { return String(localized: "Up to date") }
        guard let age = SyncFootLine.age(of: synced, now: now, locale: locale) else { return String(localized: "Up to date just now") }
        return String(localized: "Up to date \(age)")
    }
}

/// How the server stands, for the head card: a word at its trailing edge or, where the person has something to do, the
/// button for it; a line under the server's name; and, for what does not fit one line, a note under the card.
nonisolated struct ConnectionStanding: Equatable, Sendable {
    nonisolated enum Tone: Equatable, Sendable { case ok, warning, problem, quiet }
    nonisolated enum Action: Equatable, Sendable {
        case none
        /// The server does not answer: ask again.
        case tryAgain
        /// The sign-in ended: sign in again, by the browser or with a code.
        case signIn
    }

    var word: String?
    var tone: Tone
    var line: String?
    var detail: String?
    var action: Action

    init(
        state: MarfaConnectionState, status: SyncStatus, lastSynced: Date?, now: Date, calendar: Calendar = .current,
        format: DateFormat = .stored()
    ) {
        let connection = ConnectionStatus(state)
        switch state {
        case .keyRefused:
            // The copy is kept and what waits is told in Account, so the head only says it.
            self.init(word: nil, tone: .problem, line: String(localized: "Signed out. This Mac’s copy is kept."), detail: nil, action: .signIn)
        case .offline:
            self.init(
                word: String(localized: "Not Answering"), tone: .warning,
                line: Self.notAnswering(lastSynced, now: now, calendar: calendar, format: format), detail: nil, action: .tryAgain)
        case .unavailable, .otherVersion, .inUse:
            self.init(word: connection.title, tone: .problem, line: nil, detail: connection.detail, action: .none)
        case .connecting, .online, .disconnected:
            if let note = status.primary {
                self.init(word: connection.title, tone: Self.tone(of: note), line: note.line, detail: connection.detail ?? note.detail, action: .none)
            } else if state == .online {
                self.init(word: connection.title, tone: .ok, line: ConnectionHeadWording.upToDate(since: lastSynced, now: now), detail: nil, action: .none)
            } else {
                self.init(word: connection.title, tone: .quiet, line: nil, detail: connection.detail, action: .none)
            }
        }
    }

    private init(word: String?, tone: Tone, line: String?, detail: String?, action: Action) {
        self.word = word
        self.tone = tone
        self.line = line
        self.detail = detail
        self.action = action
    }

    private static func tone(of note: SyncStatus.Notice) -> Tone {
        switch note.kind {
        case .keyRefused, .unavailable: .problem
        case .needsAttention, .offline: .warning
        case .catchingUp, .sending: .quiet
        }
    }

    /// "Not answering since 09:12. MAPP keeps trying.": the time of the last answer, as the date and clock are set.
    static func notAnswering(_ lastAnswered: Date?, now: Date, calendar: Calendar, format: DateFormat) -> String {
        guard let lastAnswered else { return String(localized: "Not answering. MAPP keeps trying.") }
        let time = DateDisplay.timeOfDay(of: lastAnswered, format: format, calendar: calendar)
        let when = calendar.isDate(lastAnswered, inSameDayAs: now)
            ? time : DateDisplay.text(of: lastAnswered, place: .value, format: format, now: now, calendar: calendar)
        return String(localized: "Not answering since \(when). MAPP keeps trying.")
    }
}

/// What the Account section of Connection holds in each state: who is signed in, what the owner has allowed MAPP, and
/// what waits to be sent.
nonisolated struct ConnectionAccount: Equatable, Sendable {
    /// Every owner permission: what Connection counts and what Allow More… asks for, `sign_ins.manage` included, as a
    /// key's and an app's pages count them. Only the sign-in itself leaves it out (`SystemSignIns.askedAtSignIn`).
    static let asked: Set<InstancePermission> = Set(InstancePermission.allCases)

    /// The permissions MAPP holds, and how many of the `asked` ones that is; nil where the sign-in cannot be read or
    /// the server is not reached, when nothing is said.
    var held: Int?
    var total: Int { Self.asked.count }
    /// "All 14", or nothing where some are not held.
    var holdsAll: Bool { held == total }
    var unsent: String
    var unsentLine: String?
    var showsPermissions: Bool
    /// Signed In As cannot be told because the sign-in may not read the owner's name, as one made before MAPP asked for it
    /// cannot; Allow More… or signing in again gives it.
    var offersName: Bool

    init(
        state: MarfaConnectionState, grants: Set<InstancePermission>, grantsRead: Bool, readsProfile: Bool = true, waiting: Int?,
        serverName: String
    ) {
        let reached = state == .online || state == .connecting
        showsPermissions = reached && grantsRead
        offersName = showsPermissions && !readsProfile
        held = showsPermissions ? grants.intersection(Self.asked).count : nil
        unsent = waiting.map { $0 > 0 ? Words.changes($0) : String(localized: "None") } ?? String(localized: "Unknown")
        switch state {
        case .keyRefused: unsentLine = (waiting ?? 0) > 0 ? String(localized: "Sent once you sign in again.") : nil
        case .offline: unsentLine = (waiting ?? 0) > 0 ? String(localized: "Sent when \(serverName) answers.") : nil
        default: unsentLine = nil
        }
    }

    /// "MAPP holds 5 of the owner’s 14 permissions."
    var permissionsLine: String {
        guard let held, !holdsAll else { return String(localized: "The owner’s permissions MAPP holds.") }
        return String(localized: "MAPP holds \(held) of the owner’s \(total) permissions.")
    }

    /// "All 14", where every permission is held.
    var permissionsValue: String { String(localized: "All \(total)") }
}
