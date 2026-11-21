import Foundation

// What Backups, Updates and Housekeeping read of the server, in values of their own so the pages read nothing generated and a test
// can script every answer.

/// A backup the server holds, by the instance that took it and its name.
nonisolated struct BackupRecord: Identifiable, Hashable, Sendable {
    let instanceID: String
    let name: String
    let taken: Date
    let bytes: Int

    var id: String { instanceID + "/" + name }
}

/// The settings of Backups and Updates, as `GET /config` gives them: where and how often the server backs itself up, and whether it checks for updates.
nonisolated struct UpkeepSettings: Hashable, Sendable {
    /// How often the server backs up when it has something new, unless it was set: the contract's default, an hour.
    static let defaultInterval = 3600

    var instanceID: String?
    /// The folder on the machine the server runs on, where one is set.
    var folder: String?
    /// Whether an object store is the destination, which the server allows only with no folder.
    var objectStore: Bool
    var intervalSeconds: Int
    /// Whether the server checks for a newer release by itself.
    var checksForUpdates: Bool
}

/// What a change to `UpkeepSettings` sends: only what changed.
nonisolated struct UpkeepSettingsChange: Hashable, Sendable {
    enum Folder: Hashable, Sendable {
        case set(String)
        case remove
    }

    var folder: Folder?
    var intervalSeconds: Int?
    var checksForUpdates: Bool?
}

/// A backup the owner asked for, as the server took it.
nonisolated struct BackupTaken: Hashable, Sendable {
    var taken: Date
    /// How many files the backup names that no copy was kept of.
    var filesLost: Int
    var filesWaiting: Int
}

/// What a restore did.
nonisolated struct BackupRestored: Hashable, Sendable {
    /// What the server did not take from the backup, by its kind: `sign_in`, `keys`, `apps` and the rest the contract names.
    var leftOut: [String]
    var added: Int
    var alreadyHeld: Int
    /// Settings the backup names that the server holds no secret for, by key.
    var secretsToSet: [String]
}

nonisolated struct UpdateRelease: Hashable, Sendable {
    var version: String
    var published: Date?
}

/// Where an update under way is, in the order the server takes it.
nonisolated enum UpdateStage: Int, CaseIterable, Hashable, Sendable {
    case fetching, checking, swapping, restarting, settling
}

nonisolated struct UpdateProgress: Hashable, Sendable {
    var stage: UpdateStage
    var release: String?
}

nonisolated struct UpdateOutcome: Hashable, Sendable {
    enum Result: Hashable, Sendable {
        case succeeded
        /// The new release was put back: the server runs the release it ran before.
        case putBack
        /// The server did not change the running release, or could not put the old one back.
        case failed
    }

    var result: Result
    var release: String
    var finished: Date?
    /// Whether the server's value carried a time of day, so the page shows one only when it is known.
    var finishedHasTime = true
}

/// How the server stands on updates, as `GET /update` gives it.
nonisolated struct UpdateStatus: Hashable, Sendable {
    /// The release the server runs.
    var running: String
    var checksAutomatically: Bool
    var latest: UpdateRelease?
    /// Whether the newest release found is newer than the one running.
    var available: Bool
    /// Whether the last check found no answer.
    var checkFailed: Bool
    /// Whether the server can swap its own programs; where not, its owner does it on the machine it runs on.
    var updatesItself: Bool
    /// What the owner does on that machine, as the server says it, where it cannot update itself.
    var step: String?
    var progress: UpdateProgress?
    var last: UpdateOutcome?
}

/// A job the server runs by itself, by the name the contract gives it.
nonisolated struct HousekeepingJob: Identifiable, Hashable, Sendable {
    enum Outcome: Hashable, Sendable { case succeeded, failed, held }

    let name: String
    let intervalSeconds: Int
    var lastFinished: Date?
    var lastFinishedHasTime = true
    /// Nil until a run has finished.
    var outcome: Outcome?

    var id: String { name }
}
