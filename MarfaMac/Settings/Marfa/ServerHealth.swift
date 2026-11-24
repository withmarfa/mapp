import Foundation
import Marfa
import Observation

// What the Marfa's pages read of `GET /health`, in values of their own. The package reads it once (`Server.health()`): the open
// fields for any caller, the detail for a sign-in that holds `instance.read`. A page reads one `ServerHealthModel`, so
// Overview, Backups and Housekeeping never disagree. The server's own `error` and `lastError` texts are never kept: they name
// settings by key and paths, so each page words its own title and one plain line.

nonisolated extension Condition {
    /// The worse of two parts, so a database that reads but cannot write is shown by its write.
    func worst(with other: Condition) -> Condition {
        rank >= other.rank ? self : other
    }

    private var rank: Int {
        switch self {
        case .ok: 0
        case .unknown: 1
        case .degraded: 2
        case .down: 3
        }
    }

    init(_ status: HealthStatus) {
        switch status {
        case .ok: self = .ok
        case .degraded: self = .degraded
        case .down: self = .down
        case .other: self = .unknown
        }
    }
}

nonisolated struct BackupsHealth: Hashable, Sendable {
    enum State: String, Hashable, Sendable { case ok, incomplete, failing, off, unknown }
    enum Reason: Hashable, Sendable { case noDestination, turnedOff, destinationUnusable }
    enum Destination: Hashable, Sendable { case folder, objectStore }

    /// What the server counts wrong with its backups, never its own words.
    enum Fault: Hashable, Sendable {
        /// The last runs failed or lost files.
        case runFailed(count: Int)
        /// The destination is not taking copies.
        case destinationRefusing
        case filesWaiting(Int)
        case damagedParts(Int)
    }

    var state: State
    var lastBackup: Date?
    var reason: Reason?
    var destination: Destination?
    var faults: [Fault] = []
}

/// A job whose last run failed, by the server's name for it.
nonisolated struct FailedJob: Hashable, Sendable {
    let name: String
    let at: Date?
}

/// Why jobs that delete are held: the server's clock is more than 7 days past the time it last trusted.
nonisolated struct ClockHold: Hashable, Sendable {
    /// What the server's clock reads.
    var clockAt: Date?
    var trustedAt: Date?
    var endsAt: Date?
}

/// What the server says needs attention in its background work. Only a sign-in holding `instance.read` is given it.
nonisolated struct HousekeepingHealth: Hashable, Sendable {
    /// Nil where the schedule could not be read in time.
    var failed: [FailedJob]?
    var hold: ClockHold?
}

nonisolated struct ServerHealth: Hashable, Sendable {
    var database: Condition
    var disk: Condition
    var files: Condition
    var backups: BackupsHealth
    /// Nil for a sign-in without `instance.read`.
    var housekeeping: HousekeepingHealth?

    init(database: Condition, disk: Condition, files: Condition, backups: BackupsHealth, housekeeping: HousekeepingHealth?) {
        self.database = database
        self.disk = disk
        self.files = files
        self.backups = backups
        self.housekeeping = housekeeping
    }

    init(_ health: InstanceHealth) {
        let parts = health.components
        let backups = health.backups
        var faults: [BackupsHealth.Fault] = []
        if let failures = backups.failures, failures > 0 { faults.append(.runFailed(count: failures)) }
        if backups.storeError != nil || backups.reason == .destinationUnusable { faults.append(.destinationRefusing) }
        if let waiting = backups.lastBackupFilesWaiting ?? backups.copiesWaiting, waiting > 0 { faults.append(.filesWaiting(waiting)) }
        if let damaged = backups.damagedParts, damaged > 0 { faults.append(.damagedParts(damaged)) }
        let state: BackupsHealth.State =
            switch backups.status {
            case .ok: .ok
            case .incomplete: .incomplete
            case .failing: .failing
            case .off: .off
            case .other: .unknown
            }
        let reason: BackupsHealth.Reason? =
            switch backups.reason {
            case .noBackupDestination?: .noDestination
            case .turnedOff?: .turnedOff
            case .destinationUnusable?: .destinationUnusable
            case .other?, nil: nil
            }
        let destination: BackupsHealth.Destination? =
            switch backups.destination {
            case .folder?: .folder
            case .bucket?: .objectStore
            case .other?, nil: nil
            }
        self.init(
            database: Condition(parts.database.status).worst(with: Condition(parts.databaseWrite.status)),
            disk: Condition(parts.disk.status), files: Condition(parts.blobStorage.status),
            backups: BackupsHealth(
                state: state, lastBackup: backups.lastBackupAt, reason: reason, destination: destination, faults: faults),
            housekeeping: health.housekeeping.map { housekeeping in
                HousekeepingHealth(
                    failed: housekeeping.failed?.map { FailedJob(name: $0.name, at: $0.at) },
                    hold: housekeeping.held.flatMap { held in
                        held.reason == .clockAhead ? ClockHold(clockAt: held.clockAt, trustedAt: held.trustedAt, endsAt: held.endsAt) : nil
                    })
            })
    }
}

/// The one reader of the server's health that Overview, Backups and Housekeeping share. A read that fails leaves `health` nil,
/// which every page tells as "Couldn’t Check", never as working; a refusal for want of a permission has the grants read again.
@Observable @MainActor final class ServerHealthModel {
    private let context: OwnerContext

    private(set) var health: ServerHealth?
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    var hasLoaded: Bool { loader.hasLoaded }

    init(context: OwnerContext) {
        self.context = context
    }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            do throws(OwnerFailure) {
                health = try await context.calls.health()
            } catch {
                health = nil
                throw error
            }
        })
    }

    func reset() {
        health = nil
        loader.reset()
    }
}
