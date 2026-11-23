import Foundation

/// How a connector stands, as the Connectors page says it. The server gives no health word: this one is derived, in this
/// order, from what the owner chose (`GET /plugins/{name}/connector`), what the connector reported (`GET /connectors/{id}`),
/// when its machine was last seen (`GET /connector-hosts`) and the required settings that have no value.
nonisolated enum ConnectorHealth: Hashable, Sendable {
    /// What the owner chose could not be read.
    case unread
    /// The owner paused it: it does nothing at its next run.
    case paused
    /// A required setting has no value, so the connector cannot run.
    case needsSetup(missing: [String])
    /// No machine is chosen to run it.
    case noMachine
    /// A machine is chosen, but the connector has neither reported nor been heard from.
    case waiting(machineSeen: Bool)
    /// Its latest sign of life, a heartbeat, a run report or its machine's last visit, is older than `silentAfter`.
    case silent(since: Date)
    /// The connector reports problems of its own.
    case problems(count: Int)
    /// Its last run failed.
    case lastRunFailed(Date?)
    /// The owner asked for a run, which it starts at its next run.
    case runRequested
    case ran(Date)
    case notRunYet

    /// How long a connector may go without a sign of life before it counts as silent.
    static let silentAfter: TimeInterval = 3600

    /// Where a connector stands: a connector with no host to read can pass nil.
    static func of(
        control: ConnectorControl?, registration: ConnectorRegistration?, settings: ConnectorSettingsReading?, host: ConnectorHostInfo?,
        now: Date = .now
    ) -> ConnectorHealth {
        guard let control else { return .unread }
        if control.paused { return .paused }
        if let missing = settings?.missing, !missing.isEmpty { return .needsSetup(missing: missing) }
        guard control.host != nil else { return .noMachine }
        let signs = [registration?.lastHeartbeat, registration?.lastRun?.finished, host?.lastSeen].compactMap { $0 }
        guard let latest = signs.max(), registration != nil else { return .waiting(machineSeen: host?.lastSeen != nil) }
        if now.timeIntervalSince(latest) > silentAfter { return .silent(since: latest) }
        if let registration, !registration.problems.isEmpty { return .problems(count: registration.problems.count) }
        if let run = registration?.lastRun {
            if !run.succeeded { return .lastRunFailed(run.finished) }
        }
        if control.runRequested != nil { return .runRequested }
        if let finished = registration?.lastRun?.finished { return .ran(finished) }
        return .notRunYet
    }

    /// Whether the connector needs the owner to look at it.
    var needsAttention: Bool {
        switch self {
        case .needsSetup, .silent, .problems, .lastRunFailed: true
        default: false
        }
    }
}

enum ConnectorWording {
    /// The word a connector's row ends in.
    static func title(_ health: ConnectorHealth, now: Date = .now) -> String {
        switch health {
        case .unread: String(localized: "Couldn’t read")
        case .paused: String(localized: "Paused")
        case .needsSetup: String(localized: "Needs setup")
        case .noMachine: String(localized: "No machine")
        case .waiting: String(localized: "Waiting to start")
        case .silent: String(localized: "Not heard from")
        case .problems(let count): count == 1 ? String(localized: "1 problem") : String(localized: "\(count) problems")
        case .lastRunFailed: String(localized: "Last run failed")
        case .runRequested: String(localized: "Run requested")
        case .ran(let date): String(localized: "Ran \(ago(date, now: now))")
        case .notRunYet: String(localized: "Hasn’t run yet")
        }
    }

    /// What the word means, under Status on the connector's page. `labels` name the settings the connector still needs, by
    /// their names as the server gives them.
    static func line(_ health: ConnectorHealth, hostName: String?, labels: [String: String] = [:], now: Date = .now) -> String {
        switch health {
        case .unread: String(localized: "MAPP couldn’t read how it stands.")
        case .paused: String(localized: "It does nothing at its next run until you resume it.")
        case .needsSetup(let missing):
            String(localized: "It needs \(list(missing.map { labels[$0] ?? $0 })) before it can run.")
        case .noMachine: String(localized: "Choose the machine that runs it.")
        case .waiting(let seen):
            seen
                ? String(localized: "\(hostName ?? String(localized: "Its machine")) hasn’t started it yet.")
                : String(localized: "\(hostName ?? String(localized: "Its machine")) hasn’t connected yet.")
        case .silent(let since): String(localized: "Last heard from \(when(since, now: now)).")
        case .problems: String(localized: "It reports what needs attention below.")
        case .lastRunFailed(let date):
            date.map { String(localized: "Its last run, \(when($0, now: now)), failed.") } ?? String(localized: "Its last run failed.")
        case .runRequested: String(localized: "A run was asked for. It starts at its next run.")
        case .ran: String(localized: "It is running as it should.")
        case .notRunYet: String(localized: "It is waiting for its first run.")
        }
    }

    /// "Today, 14:02", or the day and time.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let format = DateFormat.stored()
        guard calendar.isDate(date, inSameDayAs: now) else { return DateDisplay.text(of: date, place: .value, format: format, now: now, calendar: calendar) }
        return String(localized: "Today, \(DateDisplay.timeOfDay(of: date, format: format, calendar: calendar))")
    }

    /// "2 hours ago", as the Mac's region says it.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func list(_ names: [String]) -> String { names.formatted(.list(type: .and)) }

    /// The line under the head: where it runs and how its last run went.
    static func head(hostName: String?, run: ConnectorRunInfo?, now: Date = .now) -> String {
        var parts: [String] = []
        if let hostName { parts.append(String(localized: "Runs on \(hostName).")) }
        if let finished = run?.finished {
            let when = when(finished, now: now)
            if let summary = run?.summary, run?.succeeded == true, !summary.isEmpty {
                parts.append(String(localized: "Last run \(when): \(summary)."))
            } else {
                parts.append(run?.succeeded == true ? String(localized: "Last run \(when).") : String(localized: "Last run \(when) failed."))
            }
        }
        return parts.joined(separator: " ")
    }

    /// A setting's label in title case, as the page's other titles are. A plugin writes its labels as sentences; a word that
    /// already holds a capital after its first letter, or a digit, such as "ID", stays as written.
    nonisolated static func settingTitle(_ label: String) -> String {
        let small: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "the", "to"]
        let words = label.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return words.enumerated().map { index, word in
            if word.dropFirst().contains(where: { $0.isUppercase || $0.isNumber }) { return word }
            if index > 0, index < words.count - 1, small.contains(word) { return word }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// A kind's name as a row's title: "pull_request" is "Pull Request".
    static func kindTitle(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// What a kind does, in words: where it is written and which way it moves.
    static func kindLine(_ kind: ConnectorKind, typeName: String) -> String {
        switch kind.direction {
        case .into: String(localized: "As \(typeName). From the service into Marfa.")
        case .out: String(localized: "As \(typeName). From Marfa to the service.")
        case .both: String(localized: "As \(typeName). Both ways.")
        }
    }

    /// The service a vendor sign-in goes to.
    static func provider(_ name: String) -> String {
        switch name {
        case "google": "Google"
        default: name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// Why a sign-in did not finish, from the server's one outcome word. The provider's own text is never kept, so these
    /// are all the words there are.
    static func signInFailure(_ reason: String?, provider: String) -> String {
        switch reason {
        case "access_denied": String(localized: "The sign-in was declined at \(provider).")
        case "invalid_client": String(localized: "\(provider) didn’t accept the client ID or the client secret.")
        case "invalid_grant", "invalid_request", "unauthorized_client", "unsupported_grant_type", "invalid_scope", "unsupported_response_type":
            String(localized: "\(provider) refused the sign-in.")
        case "timeout", "unreachable", "server_error", "temporarily_unavailable":
            String(localized: "\(provider) didn’t answer.")
        case "no_refresh_token": String(localized: "\(provider) gave no way to stay signed in.")
        case "changed_since_start": String(localized: "A setting changed while you signed in. Try again.")
        default: String(localized: "The sign-in didn’t finish.")
        }
    }

    /// What a sign-in that cannot start says, naming each setting it needs by its label.
    static func signInNeeds(_ labels: [String]) -> String {
        labels.isEmpty
            ? String(localized: "Set the client settings the sign-in needs first.")
            : String(localized: "Set \(list(labels)) first.")
    }
}
