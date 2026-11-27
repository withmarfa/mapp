import Foundation

/// How a concern from `GET /attention` is told in Account: the server's short title and one plain line the app words from the
/// concern's kind and reference. The server's own description is never shown, since it names settings by key and requests by
/// path for an operator; a kind the app has no wording for shows its title alone.
nonisolated extension AttentionConcern {
    enum Repair: Equatable {
        case page(MarfaSettingsPage)
        case command(String)
    }

    var repair: Repair {
        switch kind {
        case .webhook: .page(.webhooks)
        case .key: .page(.keys)
        case .connector: .page(.connectors)
        case .folder: .page(.folders)
        case .backup: .page(.backups)
        case .job, .clock: .page(.housekeeping)
        case .setting where reference.contains("/"): .page(.connectors)
        case .setting where reference == "object_store_secret_access_key": .command("marfa config set object_store_secret_access_key")
        case .setting where reference.hasPrefix("object_store_"): .page(.fileStorage)
        case .setting where reference.hasPrefix("backup_"): .page(.backups)
        case .setting: .page(.monitoring)
        case .health: .page(.fileStorage)
        case .fault: .page(.activity)
        case .unavailable:
            switch reference.lowercased() {
            case "api keys": .page(.keys)
            case "health": .page(.fileStorage)
            case "connectors": .page(.connectors)
            case "folders": .page(.folders)
            case "webhooks": .page(.webhooks)
            case "housekeeping": .page(.housekeeping)
            default: .page(.activity)
            }
        }
    }

    /// The repair command bound to the given server, so it never reaches the command line's default server instead.
    func repairCommand(serverAddress: String?) -> String? {
        guard case .command(let command) = repair else { return nil }
        guard let serverAddress, !serverAddress.isEmpty else { return command }
        return "\(command) --url '\(serverAddress.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var shownTitle: String {
        guard kind == .setting else { return title }
        if case .command = repair { return String(localized: "Set the object store secret key again") }
        // The server's own title names the setting by its key, so a setting the app has no name for is told without it.
        guard let secret = MonitoringSecret.named(key: reference) else { return String(localized: "Set a secret again") }
        return String(localized: "Set the \(secret.removalName) again")
    }

    var shownLine: String? {
        switch kind {
        case .webhook:
            return String(localized: "Its recent deliveries have failed.")
        case .health:
            return String(localized: "The server’s own check found a problem.")
        case .job:
            return String(localized: "Its last run failed.")
        case .connector:
            if title.hasSuffix("failed its last run") { return String(localized: "Its last run failed.") }
            if title.hasSuffix("reports problems") { return String(localized: "It reports problems.") }
            if title.hasSuffix("has gone quiet") { return String(localized: "Nothing has been heard from it for more than a day.") }
            return nil
        case .folder:
            return String(localized: "It has trouble syncing.")
        case .key:
            return String(localized: "Anything that uses it will stop working when it expires.")
        case .backup:
            return backupLine
        case .setting:
            if case .command = repair {
                return String(localized: "Copy the command, run it in Terminal, then enter the secret key when prompted.")
            }
            return String(localized: "The server can’t read this secret, so it can’t use it until it is set again.")
        case .clock:
            return reference == "clock_ahead"
                ? String(localized: "Clean-up waits until the server’s clock is right.")
                : reference == "clock_behind" ? String(localized: "The server’s clock is behind.") : nil
        case .fault:
            return String(localized: "The server met a fault lately.")
        case .unavailable:
            return String(localized: "The server didn’t answer this check, so its state is unknown.")
        }
    }

    private var backupLine: String? {
        switch reference {
        case "no_backup_destination": String(localized: "There is nowhere to keep backups.")
        case "turned_off": String(localized: "The server takes no backup on a schedule.")
        case "store": String(localized: "Some files are waiting for their copy in the backup destination.")
        case "run": String(localized: "The last backup run failed or lost files.")
        case "parts_damaged": String(localized: "Some stored parts of backups are damaged.")
        case "incomplete": String(localized: "Some files the newest backup needs are still waiting for a copy.")
        case "folder_lock_lost", "folder_shared", "folder_lock_restored", "folder_claim_kept", "folder_unlocked":
            String(localized: "The backup folder may not belong to this server alone.")
        default: nil
        }
    }
}
