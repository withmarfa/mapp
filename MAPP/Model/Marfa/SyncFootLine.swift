import Foundation

/// The one line under the instance's name at the foot of the sidebar, which says how the library stands with its
/// server. State in, words out, with no view in it. Nothing is said where there is no server to sync with.
nonisolated struct SyncFootLine: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The copy is being brought up to date, or has not yet been heard from the server.
        case syncing
        /// The last sync finished without an error, and nothing waits.
        case updated
        /// Changes made here are waiting to go to the server, which can be reached.
        case waiting
        case offline
        /// The server refused changes for good, which the person has to look at.
        case needsAttention
        /// The key is refused or the copy cannot be used, so nothing syncs until the person acts.
        case failed
    }

    let kind: Kind
    let text: String
    /// The reason, for a tooltip.
    let help: String?

    var showsSpinner: Bool { kind == .syncing }

    /// Nil where there is nothing to say: no library, or one that is online and has not synced yet and is not
    /// being synced either, which a moment's wait settles.
    ///
    /// A sync is the copy finishing a pull from the server without an error (`lastSynced`), as against any contact.
    /// A server that cannot be reached, or one that refuses a key, leaves it where it was.
    init?(
        state: MarfaHost.State, report: SyncReport, lastSynced: Date?, now: Date, locale: Locale = .current
    ) {
        let status = SyncStatus(state: state, report: report, now: now)
        switch state {
        case .disconnected:
            return nil
        case .keyRefused, .unavailable, .otherVersion, .inUse:
            self.init(.failed, String(localized: "Couldn’t sync"), help: Self.reason(of: state, status))
        case .online, .connecting, .offline:
            let reachable = if case .offline = state { false } else { true }
            if !report.problems.isEmpty {
                self.init(.needsAttention, Words.needAttentionLine(report.problems.count), help: status.notes.first { $0.kind == .needsAttention }?.detail)
            } else if reachable, report.phase != .current || state == .connecting {
                self.init(.syncing, String(localized: "Syncing…"), help: nil)
            } else if !reachable {
                let line = report.waiting > 0
                    ? Words.offlineLine(report.waiting)
                    : lastSynced.map { Self.offline(since: $0, now: now, locale: locale) } ?? String(localized: "Offline")
                self.init(.offline, line, help: status.notes.first { $0.kind == .offline }?.detail)
            } else if status.primary?.kind == .sending {
                self.init(.waiting, Words.waitingToSend(report.waiting), help: status.primary?.detail)
            } else if let lastSynced {
                self.init(.updated, Self.updated(since: lastSynced, now: now, locale: locale), help: nil)
            } else {
                return nil
            }
        }
    }

    private init(_ kind: Kind, _ text: String, help: String?) {
        self.kind = kind
        self.text = text
        self.help = help
    }

    private static func reason(of state: MarfaHost.State, _ status: SyncStatus) -> String? {
        if case .unavailable(let message) = state, !message.isEmpty { return message }
        if case .inUse = state { return Words.inUse }
        return status.primary?.detail
    }

    // MARK: Time

    /// "Updated 2 minutes ago", or "Updated just now" under a minute.
    static func updated(since date: Date, now: Date, locale: Locale = .current) -> String {
        guard let age = age(of: date, now: now, locale: locale) else { return String(localized: "Updated just now") }
        return String(localized: "Updated \(age)")
    }

    /// "Offline, updated 3 hours ago".
    static func offline(since date: Date, now: Date, locale: Locale = .current) -> String {
        guard let age = age(of: date, now: now, locale: locale) else { return String(localized: "Offline, updated just now") }
        return String(localized: "Offline, updated \(age)")
    }

    /// How long ago `date` was, in the person's language and to the whole minute, hour or day, so the words change
    /// when the unit turns and not before. Nil under a minute, which is "just now".
    static func age(of date: Date, now: Date, locale: Locale = .current) -> String? {
        let elapsed = now.timeIntervalSince(date)
        let unit: TimeInterval
        switch elapsed {
        case ..<60: return nil
        case ..<3600: unit = 60
        case ..<86400: unit = 3600
        default: unit = 86400
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: now.addingTimeInterval(-(elapsed / unit).rounded(.down) * unit), relativeTo: now)
    }
}
