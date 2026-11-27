import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

extension ClientOwnerCalls {
    func health() async throws(OwnerFailure) -> ServerHealth {
        guard let server else { throw .failed(String(localized: "There is no server to ask.")) }
        do {
            return ServerHealth(try await server().health())
        } catch {
            throw Self.failure(error)
        }
    }

    // MARK: Settings

    private static func upkeep(_ config: Components.Schemas.InstanceConfig) -> UpkeepSettings {
        let folder = config.backupPath.flatMap { $0.isEmpty ? nil : $0 }
        return UpkeepSettings(
            instanceID: config.instanceId, folder: folder, objectStore: !(config.objectStoreBucket ?? "").isEmpty,
            intervalSeconds: config.backupIntervalSeconds ?? UpkeepSettings.defaultInterval,
            checksForUpdates: config.updateCheckEnabled ?? true)
    }

    func upkeepSettings() async throws(OwnerFailure) -> UpkeepSettings {
        try await run { client in Self.upkeep(try await client.getConfig().ok.body.json) }
    }

    func change(_ settings: UpkeepSettings, _ change: UpkeepSettingsChange) async throws(OwnerFailure) -> UpkeepSettings {
        try await run(plainConflict: Self.configConflict) { client in
            var body = Operations.UpdateConfig.Input.Body.JsonPayload()
            switch change.folder {
            case .set(let path)?: body.backupPath = .value(path)
            case .remove?: body.backupPath = .null
            case nil: break
            }
            if let seconds = change.intervalSeconds { body.backupIntervalSeconds = .value(seconds) }
            if let enabled = change.checksForUpdates { body.updateCheckEnabled = .value(enabled) }
            return Self.upkeep(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: settings.instanceID), body: .json(body)).ok.body.json)
        }
    }

    // MARK: Backups

    func backups() async throws(OwnerFailure) -> [BackupRecord] {
        try await run { client in
            do {
                return try await client.listBackups().ok.body.json.data
                    .map { BackupRecord(instanceID: $0.instanceId, name: $0.name, taken: $0.createdAt, bytes: $0.sizeBytes) }
                    .sorted { $0.taken > $1.taken }
            } catch {
                // A server with nowhere to keep backups refuses the list (`no_backup_destination`): there are none, which the
                // page says as it says an empty list, with the way to choose a place.
                if case .server(_, "no_backup_destination", _, _, _)? = Self.marfaError(error) { return [] }
                throw error
            }
        }
    }

    func backUpNow() async throws(OwnerFailure) -> BackupTaken {
        try await run { client in
            let run = try await client.runBackup().ok.body.json
            return BackupTaken(taken: run.backup.createdAt, filesLost: run.blobsLost.count, filesWaiting: run.blobsWaiting)
        }
    }

    func restore(_ backup: BackupRecord) async throws(OwnerFailure) -> BackupRestored {
        try await run { client in
            let done = try await client.restoreBackup(path: .init(instanceId: backup.instanceID, name: backup.name)).ok.body.json
            return BackupRestored(
                leftOut: done.notRestored.map(\.kind.rawValue), added: Int(done.imported), alreadyHeld: Int(done.duplicates),
                secretsToSet: done.secretsToSet)
        }
    }

    // MARK: Updates

    private static func status(_ update: Components.Schemas.Update) -> UpdateStatus {
        let stage: UpdateStage? =
            switch update.progress.state {
            case .idle: nil
            case .fetching: .fetching
            case .checking: .checking
            case .swapping: .swapping
            case .restarting: .restarting
            case .settling: .settling
            }
        let last = update.last.value.map { last in
            UpdateOutcome(
                result: last.outcome == .succeeded ? .succeeded : (last.outcome == .rolledBack ? .putBack : .failed),
                release: last.release, finished: date(last.finishedAt), finishedHasTime: hasTime(last.finishedAt))
        }
        return UpdateStatus(
            running: update.release, checksAutomatically: update.checkEnabled,
            latest: update.latest.value.map { UpdateRelease(version: $0.release, published: date($0.publishedAt)) },
            available: update.available, checkFailed: update.checkError.value != nil, updatesItself: update.method == .server,
            step: update.step, progress: stage.map { UpdateProgress(stage: $0, release: update.progress.release) }, last: last)
    }

    func updateStatus() async throws(OwnerFailure) -> UpdateStatus {
        try await run { client in Self.status(try await client.getUpdate().ok.body.json) }
    }

    func checkForUpdates() async throws(OwnerFailure) -> UpdateStatus {
        try await run { client in
            // A check that finds nothing is no failure of the call: the status says why.
            _ = try await client.runHousekeeping(path: .init(name: "release-check")).ok
            return Self.status(try await client.getUpdate().ok.body.json)
        }
    }

    func startUpdate() async throws(OwnerFailure) -> UpdateStatus {
        try await run { client in Self.status(try await client.startUpdate().accepted.body.json) }
    }

    // MARK: Housekeeping

    func housekeepingJobs() async throws(OwnerFailure) -> [HousekeepingJob] {
        try await run { client in
            try await client.listHousekeeping().ok.body.json.data.map { job in
                let outcome: HousekeepingJob.Outcome? =
                    switch job.lastOutcome.value {
                    case .succeeded?: .succeeded
                    case .failed?: .failed
                    case .held?: .held
                    case nil: nil
                    }
                return HousekeepingJob(
                    name: job.name, intervalSeconds: job.intervalSeconds, lastFinished: Self.date(job.lastFinishedAt),
                    runningSince: Self.date(job.runningSince), lastFinishedHasTime: Self.hasTime(job.lastFinishedAt), outcome: outcome)
            }
        }
    }

    func confirmClock() async throws(OwnerFailure) -> Date? {
        try await run { client in Self.date(try await client.confirmClock().ok.body.json.confirmedAt) }
    }
}
