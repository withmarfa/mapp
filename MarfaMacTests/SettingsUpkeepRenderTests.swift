import Marfa
import SwiftUI
import Synchronization
import Testing
@testable import MarfaMac

/// Draws Backups, Updates and Housekeeping from a scripted server, for a pull request's pictures. Skipped unless
/// `MARFA_MAC_SETTINGS_RENDERS` names a folder.
@Suite(.enabled(if: SettingsRender.isRequested), .serialized, .hangLimit)
@MainActor struct SettingsUpkeepRenderTests {
    private static let size = SettingsRenderTests.size

    private static func at(hour: Int, minute: Int = 0, daysAgo: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func host(
        grants: Set<InstancePermission> = Set(InstancePermission.allCases), _ configure: (inout FakeOwnerCalls.State) -> Void = { _ in }
    ) -> StubMarfaHost {
        let calls = FakeOwnerCalls()
        calls.state.withLock { state in
            state.backups = [
                BackupRecord(instanceID: "i", name: "4", taken: Self.at(hour: 14), bytes: 212_000_000),
                BackupRecord(instanceID: "i", name: "3", taken: Self.at(hour: 13), bytes: 212_000_000),
                BackupRecord(instanceID: "i", name: "2", taken: Self.at(hour: 12), bytes: 211_000_000),
                BackupRecord(instanceID: "i", name: "1", taken: Self.at(hour: 11), bytes: 211_000_000),
            ] + (0..<164).map { BackupRecord(instanceID: "i", name: "o\($0)", taken: Self.at(hour: 10, daysAgo: 1 + $0 / 24), bytes: 210_000_000) }
            state.update = UpdateStatus(
                running: "0.0.84", checksAutomatically: true, latest: UpdateRelease(version: "0.0.85", published: Self.at(hour: 9, daysAgo: 1)),
                available: true, checkFailed: false, updatesItself: true, step: nil, progress: nil,
                last: UpdateOutcome(result: .succeeded, release: "0.0.84", finished: Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: 11, day: 12)), finishedHasTime: false))
            state.jobs = [
                ("backup", 3600, 14, 0, HousekeepingJob.Outcome.succeeded), ("trash-purge", 86_400, 3, 0, .succeeded),
                ("version-thinning", 3600, 14, 0, .succeeded), ("audit-cleanup", 86_400, 3, 10, .succeeded),
                ("blob-orphans", 86_400, 3, 20, .succeeded), ("blob-replicate", 60, 14, 21, .succeeded),
                ("enrichment-sweep", 30, 14, 21, .succeeded), ("release-check", 21_600, 12, 0, .succeeded),
            ].map { HousekeepingJob(name: $0.0, intervalSeconds: $0.1, lastFinished: Self.at(hour: $0.2, minute: $0.3), outcome: $0.4) }
            configure(&state)
        }
        let host = StubMarfaHost(settings: InstanceSettingsModel { nil })
        host.ownerCalls = calls
        host.grants = grants
        host.bindOverview()
        return host
    }

    private func calls(_ host: StubMarfaHost) -> FakeOwnerCalls { host.ownerCalls as! FakeOwnerCalls }

    private func page(
        _ page: MarfaSettingsPage, _ host: StubMarfaHost, subpage: SettingsSubpage? = nil, sheet: AnyView? = nil, badge: Bool = false,
        named: String
    ) async throws {
        try await SettingsRender.png(
            RenderedWindow(
                selection: .marfa(page), sheet: sheet, updatesBadge: badge,
                detail: MarfaSettingsPageView(page: page, host: host).environment(\.settingsSubpage, subpage)),
            size: Self.size, named: named, settle: .milliseconds(1_200))
    }

    private func backupsPage(_ host: StubMarfaHost, model: BackupsModel) -> some View {
        BackupsPage(host: host, showsAll: false, model: model)
    }

    // MARK: Backups

    @Test func backups() async throws {
        let host = host()
        try await page(.backups, host, named: "Backups")
    }

    @Test func allBackups() async throws {
        let host = host()
        try await page(.backups, host, subpage: BackupsPage.allBackups, named: "Backups, all of them")
    }

    @Test func restoringABackup() async throws {
        let host = host()
        let model = BackupsModel(context: OwnerContext(host: host))
        await model.load()
        model.beginRestore(model.backups[1])
        try await SettingsRender.png(
            RenderedWindow(selection: .backups, detail: backupsPage(host, model: model)),
            size: Self.size, named: "Backups, restoring", settle: .milliseconds(1_200))
    }

    @Test func restoringACancelledSignIn() async throws {
        let host = host()
        calls(host).fail("restore", with: .notConfirmed)
        let model = BackupsModel(context: OwnerContext(host: host))
        await model.load()
        model.beginRestore(model.backups[1])
        await model.restore()
        try await SettingsRender.png(
            RenderedWindow(selection: .backups, detail: backupsPage(host, model: model)),
            size: Self.size, named: "Backups, a restore the sign-in cancelled", settle: .milliseconds(1_200))
    }

    @Test func afterARestore() async throws {
        let host = host()
        calls(host).state.withLock {
            $0.restoreAnswer = BackupRestored(leftOut: [], added: 18, alreadyHeld: 1_059, secretsToSet: ["heartbeat_url", "posthog_project_token"])
        }
        let model = BackupsModel(context: OwnerContext(host: host))
        await model.load()
        model.beginRestore(model.backups[1])
        await model.restore()
        try await SettingsRender.png(
            RenderedWindow(selection: .backups, detail: backupsPage(host, model: model)), size: Self.size, named: "Backups, after a restore",
            settle: .milliseconds(1_200))
    }

    @Test func backupsWithNowhereToGo() async throws {
        let host = host {
            $0.backups = []
            $0.upkeep.folder = nil
            $0.health = ServerHealth(
                database: .ok, disk: .ok, files: .ok, backups: BackupsHealth(state: .off, lastBackup: nil, reason: .noDestination),
                housekeeping: HousekeepingHealth(failed: [], hold: nil))
        }
        try await page(.backups, host, named: "Backups, nowhere to go")
    }

    @Test func backupsWithoutThePermission() async throws {
        let host = host(grants: [.instanceRead])
        try await page(.backups, host, named: "Backups, needs a permission")
    }

    @Test func backupsTheServerNotAnswering() async throws {
        let host = host()
        host.connection = .notAnswering(lastAnswered: Self.at(hour: 13))
        try await page(.backups, host, named: "Backups, not answering")
    }

    // MARK: Updates

    @Test func updatesOneIsReady() async throws {
        try await page(.updates, host(), badge: true, named: "Updates, one is ready")
    }

    @Test func updatesWhereTheServerCannotUpdateItself() async throws {
        let host = host {
            $0.update.updatesItself = false
            $0.update.step = "Stop Castell Studio, install 0.0.85 the way it was installed, then start it."
        }
        try await page(.updates, host, badge: true, named: "Updates, where the server can't update itself")
    }

    @Test func updatesWhileUpdating() async throws {
        let host = host {
            $0.update.progress = UpdateProgress(stage: .restarting, release: "0.0.85")
        }
        try await page(.updates, host, named: "Updates, updating")
    }

    @Test func updatesPutBack() async throws {
        let host = host {
            $0.update.last = UpdateOutcome(result: .putBack, release: "0.0.85", finished: Self.at(hour: 14, minute: 20))
        }
        try await page(.updates, host, badge: true, named: "Updates, put back")
    }

    @Test func updatesWithoutThePermission() async throws {
        try await page(.updates, host(grants: []), named: "Updates, needs a permission")
    }

    // MARK: Housekeeping

    @Test func housekeepingWhileTheClockIsHeld() async throws {
        let march = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 3, hour: 14)) ?? .now
        let host = host {
            $0.health = ServerHealth(
                database: .ok, disk: .ok, files: .ok, backups: BackupsHealth(state: .ok, lastBackup: nil),
                housekeeping: HousekeepingHealth(failed: [], hold: ClockHold(clockAt: march, trustedAt: .now, endsAt: nil)))
            $0.jobs = $0.jobs.map { job in
                var job = job
                if ["trash-purge", "version-thinning", "audit-cleanup", "blob-orphans"].contains(job.name) { job.outcome = .held }
                return job
            }
        }
        try await page(.housekeeping, host, named: "Housekeeping")
    }

    @Test func housekeepingWhenAllIsWell() async throws {
        try await page(.housekeeping, host(), named: "Housekeeping, nothing wrong")
    }

    @Test func housekeepingWithoutThePermission() async throws {
        try await page(.housekeeping, host(grants: []), named: "Housekeeping, needs a permission")
    }
}
