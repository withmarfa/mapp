import Foundation
import Marfa
import MarfaAPI
import Observation

/// What the Overview reads of the server: what needs the owner's attention, and how the server stands. The app keeps one, so
/// the sidebar's badge is its count whichever page is shown. A server refusal for want of a permission shows the page's
/// Needs a Permission state and has the grants read again.
@Observable @MainActor final class OverviewModel {
    private let context: OwnerContext
    private let healthReader: ServerHealthModel

    private(set) var concerns: [AttentionConcern] = []
    private(set) var metrics: InstanceMetricsReading?
    private(set) var update: UpdateStatus?
    private(set) var owner: String?
    private var lastBackup: Date?

    var updateReady: String? {
        guard releaseFailure == nil, let update, update.available, let latest = update.latest?.version else { return nil }
        if metricsFailure == nil, let installed = metrics?.version {
            guard let offered = PluginVersion(latest), let running = PluginVersion(installed), offered > running else { return nil }
        }
        return latest
    }
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private let metricsRead = OwnerLoader.ReadStatus()
    private let updateRead = OwnerLoader.ReadStatus()
    private let backupsRead = OwnerLoader.ReadStatus()
    var metricsFailure: OwnerFailure? { metricsRead.failure }
    var releaseFailure: OwnerFailure? { updateRead.failure }
    var lastBackupFailure: OwnerFailure? { backupsRead.failure }
    var hasLoaded: Bool { loader.hasLoaded }

    init(context: OwnerContext, health: ServerHealthModel? = nil) {
        self.context = context
        healthReader = health ?? ServerHealthModel(context: context)
    }

    /// What the sidebar's badge counts: the server's concerns, not the app's own missing permissions.
    var attentionCount: Int { concerns.count }

    /// The release the server runs, left out for a development build: it carries version 0.0.0, which is no version.
    var releaseVersion: String? {
        let running =
            if releaseFailure != nil, metricsFailure == nil { metrics?.version }
            else { update?.running ?? metrics?.version }
        return running.flatMap { $0 == Self.developmentVersion ? nil : $0 }
    }

    static let developmentVersion = "0.0.0"

    // MARK: Health

    enum Component { case database, disk, files }

    /// How a part stands, from what the server's health says of it. Where the health could not be read, no part is shown as
    /// working.
    func health(of component: Component) -> HealthPart {
        guard let health = healthReader.health else { return HealthPart(condition: .unknown) }
        switch component {
        case .database: return HealthPart(condition: health.database)
        case .disk: return HealthPart(condition: health.disk)
        case .files: return HealthPart(condition: health.files)
        }
    }

    /// The backups row, from the server's own account of its backups.
    var backups: BackupsHealth {
        guard var backups = healthReader.health?.backups else { return BackupsHealth(state: .unknown, lastBackup: lastBackup) }
        backups.lastBackup = backups.lastBackup ?? lastBackup
        return backups
    }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            await healthReader.load()
            concerns = try await context.calls.attention()
        }, secondary: [
            .required(metricsRead) { [self] () throws(OwnerFailure) in metrics = try await context.calls.instanceMetrics() },
            .required(updateRead) { [self] () throws(OwnerFailure) in update = try await context.calls.updateStatus() },
            .required(backupsRead) { [self] () throws(OwnerFailure) in
                guard context.grants().contains(.backupsManage) else {
                    lastBackup = nil
                    return
                }
                lastBackup = try await context.calls.backups().map(\.taken).max()
            },
            .quiet { [self] () throws(OwnerFailure) in
                let profile = try await context.calls.profile()
                owner = profile.name ?? profile.username
            },
        ])
    }

    /// Forgets what was read, such as when another server is opened.
    func reset() {
        concerns = []
        metrics = nil
        update = nil
        owner = nil
        lastBackup = nil
        metricsRead.clear()
        updateRead.clear()
        backupsRead.clear()
        loader.reset()
        healthReader.reset()
    }
}
