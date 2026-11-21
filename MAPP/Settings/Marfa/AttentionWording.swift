import Foundation

/// How a concern from `GET /attention` is told on the Overview: the server's short title and one plain line MAPP words from the
/// concern's kind and reference. The server's own description is never shown, since it names settings by key and requests by
/// path for an operator; a kind MAPP has no wording for shows its title alone.
nonisolated extension AttentionConcern {
    var shownTitle: String {
        guard kind == .setting else { return title }
        // The server's own title names the setting by its key, so a setting MAPP has no name for is told without it.
        guard let secret = MonitoringSecret.named(key: reference) else { return String(localized: "Set a Secret Again") }
        return String(localized: "Set \(secret.settingTitle) Again")
    }

    var shownLine: String? {
        switch kind {
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
