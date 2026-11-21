import Foundation

/// The words of Backups, Updates and Housekeeping. The server's own errors and descriptions are never shown, since they name
/// settings by key and requests by path: each title and line here is MAPP's own, from what the server counts or names.
nonisolated enum UpkeepWording {
    /// A moment as "Today, 14:00", "Yesterday, 14:00" or "12 November, 14:00" (with the year when it is not this one).
    static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today, \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(time)")
        }
        return String(localized: "\(OwnerWording.day(date, now: now, calendar: calendar)), \(time)")
    }

    /// A moment inside a sentence: "today, 13:00" and "yesterday, 13:00" begin with a small letter, a date does not.
    static func momentInSentence(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let text = moment(date, now: now, calendar: calendar)
        let isRelative = calendar.isDate(date, inSameDayAs: now)
            || calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } == true
        return isRelative ? text.prefix(1).lowercased() + text.dropFirst() : text
    }

    /// A day as "Today", "Yesterday" or "12 November".
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return OwnerWording.day(date, now: now, calendar: calendar)
    }

    // MARK: Failures

    /// A failure in MAPP's own words: a refusal or fault carries the server's text, which names settings by key and requests by
    /// path, so it is never shown.
    static func owned(_ failure: OwnerFailure) -> OwnerFailure {
        switch failure {
        case .refused, .failed, .sourceHeld: .failed(String(localized: "The server couldn’t do that."))
        default: failure
        }
    }

    // MARK: Backups

    /// What a backup's size reads as in the table.
    static func size(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    /// How often the server backs up, as a pop-up says it.
    static func interval(_ seconds: Int) -> String {
        switch seconds {
        case 0: String(localized: "Never")
        case 900: String(localized: "15 Minutes")
        case 3600: String(localized: "Hour")
        case 21_600: String(localized: "6 Hours")
        case 86_400: String(localized: "Day")
        case 604_800: String(localized: "Week")
        default:
            if seconds % 86_400 == 0 { String(localized: "\(seconds / 86_400) Days") }
            else if seconds % 3600 == 0 { String(localized: "\(seconds / 3600) Hours") }
            else if seconds % 60 == 0 { String(localized: "\(seconds / 60) Minutes") }
            else { String(localized: "\(seconds) Seconds") }
        }
    }

    /// The intervals a pop-up offers, which are the contract's range in the steps an owner chooses by.
    static let intervals = [900, 3600, 21_600, 86_400, 604_800, 0]

    /// What is wrong with the backups, as a title and one line each, from what the server counts.
    static func problems(_ backups: BackupsHealth) -> [(title: String, line: String)] {
        var problems: [(title: String, line: String)] = []
        switch backups.reason {
        case .noDestination?:
            problems.append((String(localized: "No backups are kept"), String(localized: "Choose a folder or an object store.")))
        case .turnedOff?:
            problems.append((String(localized: "Backups are turned off"), String(localized: "Choose how often to back up.")))
        case .destinationUnusable?, nil:
            break
        }
        for fault in backups.faults {
            switch fault {
            case .runFailed:
                problems.append((String(localized: "The last backup didn’t finish"), String(localized: "Files may be missing from it.")))
            case .destinationRefusing:
                problems.append((String(localized: "Backups can’t be kept there"), String(localized: "The folder or object store isn’t taking them.")))
            case .filesWaiting(let count):
                problems.append(
                    (String(localized: "Files are waiting for a second copy"), String(localized: "\(count.formatted()) files aren’t copied to the backup place yet.")))
            case .damagedParts(let count):
                problems.append((String(localized: "Some stored backups are damaged"), String(localized: "\(count.formatted()) parts are altered or can’t be read.")))
            }
        }
        if problems.isEmpty, backups.state == .failing || backups.state == .incomplete {
            problems.append((String(localized: "Backups need attention"), String(localized: "The newest backup isn’t whole.")))
        }
        return problems
    }

    /// What a restore leaves out, by the kind the server names and the sentence the restore sheet lists it with. Each pair of
    /// kinds that the server tells together is one row.
    static let notRestored: [(symbol: String, title: String, kinds: Set<String>)] = [
        ("key", String(localized: "Sign-ins, keys and apps"), ["sign_in", "keys", "apps"]),
        ("dot.radiowaves.up.forward", String(localized: "Webhooks and connector addresses"), ["webhooks", "inbound_endpoints", "connector_keys"]),
        ("globe", String(localized: "Addresses and the name"), ["addresses", "name"]),
        ("list.bullet.rectangle", String(localized: "Logs"), ["logs"]),
    ]

    /// A setting key as a person reads it: "posthog_project_token" is "Posthog Project Token".
    static func settingName(_ key: String) -> String {
        key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: Updates

    static func stageTitle(_ stage: UpdateStage) -> String {
        switch stage {
        case .fetching: String(localized: "Downloading")
        case .checking: String(localized: "Checking")
        case .swapping: String(localized: "Replacing")
        case .restarting: String(localized: "Restarting")
        case .settling: String(localized: "Settling")
        }
    }

    // MARK: Housekeeping

    /// The jobs the page lists, in order, by the name the contract gives each and the title the owner reads. The jobs that
    /// only tidy the server's inside (event logs, credentials, bulk jobs, table rows, inbound deliveries, feed expiry, integrity
    /// checks, the attention check and the heartbeat) are not listed.
    static let jobs: [(name: String, title: String)] = [
        ("backup", String(localized: "Back Up")),
        ("trash-purge", String(localized: "Empty Recently Deleted")),
        ("version-thinning", String(localized: "Thin Old Versions")),
        ("audit-cleanup", String(localized: "Remove Old Activity")),
        ("blob-orphans", String(localized: "Remove Unused Files")),
        ("blob-replicate", String(localized: "Copy Files to Storage")),
        ("enrichment-sweep", String(localized: "Read New Files")),
        ("release-check", String(localized: "Check for Updates")),
    ]

    static func jobTitle(_ name: String) -> String {
        jobs.first { $0.name == name }?.title ?? settingName(name.replacingOccurrences(of: "-", with: "_"))
    }

    /// How often a job runs, as the table says it.
    static func every(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: String(localized: "\(seconds) seconds")
        case 60: String(localized: "Minute")
        case 3600: String(localized: "Hour")
        case 86_400: String(localized: "Day")
        default:
            if seconds % 86_400 == 0 { String(localized: "\(seconds / 86_400) days") }
            else if seconds % 3600 == 0 { String(localized: "\(seconds / 3600) hours") }
            else if seconds % 60 == 0 { String(localized: "\(seconds / 60) minutes") }
            else { String(localized: "\(seconds) seconds") }
        }
    }

    static func result(_ outcome: HousekeepingJob.Outcome?) -> String {
        switch outcome {
        case .succeeded?: String(localized: "Done")
        case .held?: String(localized: "Paused")
        case .failed?: String(localized: "Failed")
        case nil: String(localized: "Not Yet")
        }
    }
}
