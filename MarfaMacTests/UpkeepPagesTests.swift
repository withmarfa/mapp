import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MarfaMac

nonisolated private let someday = Date(timeIntervalSince1970: 1_800_000_000)

nonisolated private func record(_ name: String, hoursAgo: Int = 0) -> BackupRecord {
    BackupRecord(instanceID: "instance-1", name: name, taken: someday.addingTimeInterval(Double(-hoursAgo) * 3600), bytes: 212_000_000)
}

@MainActor
@Suite(.hangLimit) struct ServerHealthTests {
    private func wire(
        backups: InstanceHealth.Backups = .init(status: .ok), housekeeping: InstanceHealth.Housekeeping? = nil
    ) -> InstanceHealth {
        InstanceHealth(
            status: .ok, claimed: true,
            components: .init(
                database: .init(status: .ok), databaseWrite: .init(status: .ok), disk: .init(status: .degraded, error: "/var/lib/marfa is 98% full"),
                blobStorage: .init(status: .ok)),
            backups: backups, housekeeping: housekeeping)
    }

    @Test func aSignInWithoutInstanceReadGetsNoHousekeepingDetail() {
        #expect(ServerHealth(wire()).housekeeping == nil)
    }

    @Test func theSharedReaderKeepsNothingWhenAReadFails() async {
        let bench = OwnerBench(grants: [.instanceRead])
        let reader = ServerHealthModel(context: bench.context)
        await reader.load()
        #expect(reader.health != nil)
        bench.calls.fail("health", with: .unreachable)
        await reader.load()
        #expect(reader.health == nil)
        #expect(reader.failure == .unreachable)
        bench.calls.fail("health", with: .notPermitted("instance.read"))
        await reader.load()
        #expect(bench.refreshed == 1)
    }
}

@MainActor
@Suite(.hangLimit) struct BackupsModelTests {
    @Test func anUnreportedBackupIntervalHasNoNumericValue() {
        let interval: Int? = ClientOwnerCalls.upkeep(.init(instanceId: "instance-1")).intervalSeconds
        #expect(interval == nil)
        #expect(ClientOwnerCalls.upkeep(.init(instanceId: "instance-1", backupIntervalSeconds: 0)).intervalSeconds == 0)
    }

    private func bench(grants: Set<InstancePermission> = [.backupsManage, .configManage]) -> OwnerBench {
        let bench = OwnerBench(grants: grants)
        bench.calls.state.withLock { $0.backups = [record("c", hoursAgo: 0), record("b", hoursAgo: 1), record("a", hoursAgo: 2)] }
        return bench
    }

    @Test func anEmptyBackupListHasNoLastBackupAndAnUnreachableServerHasAPageFailure() async {
        let bench = OwnerBench(grants: [.backupsManage])
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.lastBackupLine(health: nil) == "None yet.")
        bench.calls.fail("backups", with: .unreachable)
        await model.load()
        #expect(model.failure == .unreachable)
    }

    @Test func anUnavailableDestinationLeavesItsSettingsAvailable() async {
        let bench = bench()
        bench.calls.fail("backups", with: .refused("Backup destination unavailable."))
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.failure == nil)
        #expect(model.listFailure != nil)
        #expect(model.place == .folder)
        #expect(model.backups.isEmpty)
    }

    @Test func aFailedFolderBackupNamesTheDestinationProblemAndKeepsTheLastSuccessfulDate() {
        let taken = Date(timeIntervalSince1970: 1234)
        let health = BackupsHealth(
            state: .failing, lastBackup: taken, reason: .destinationUnusable, destination: .folder,
            faults: [.runFailed(count: 1), .destinationRefusing])
        let problem = BackupsPage.failedRun(health)
        #expect(problem?.contains("backup folder") == true)
        #expect(problem?.contains("Connect") == true)
        let model = BackupsModel(context: bench().context)
        #expect(model.lastBackupLine(health: health) == UpkeepWording.moment(taken))
    }

    @Test func itReadsTheBackupsAndWhereTheyGoWhereTheSignInMayChangeSettings() async {
        let bench = bench()
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.backups.count == 3)
        #expect(model.settings?.folder == "/Volumes/Studio Backup")
        #expect(model.place == .folder)
        #expect(model.latest?.name == "c")
    }

    @Test func withoutConfigManageItNeverAsksForTheSettings() async {
        let bench = bench(grants: [.backupsManage])
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.settings == nil)
        #expect(model.place == nil)
        #expect(!bench.calls.calls.contains("upkeepSettings"))
    }

    @Test func aRefusedReadShowsTheStateAndReadsTheGrantsAgain() async {
        let bench = bench()
        bench.calls.fail("backups", with: .notPermitted("backups.manage"))
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.failure == .notPermitted("backups.manage"))
        #expect(bench.refreshed == 1)
    }

    @Test func backUpNowWithNowhereToGoAsksNothingOfTheServerAndSaysWhy() async {
        let bench = bench()
        bench.calls.state.withLock { $0.upkeep.folder = nil }
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.place == .nowhere)
        await model.backUpNow(reason: .noDestination)
        #expect(!bench.calls.calls.contains("backUpNow"))
        #expect(model.backUpError == "Choose where to keep backups first.")
    }

    @Test func backUpNowTakesOneAndShowsItFirst() async {
        let bench = bench()
        let model = BackupsModel(context: bench.context)
        await model.load()
        await model.backUpNow(reason: nil)
        #expect(bench.calls.state.withLock { $0.backupsTaken } == 1)
        #expect(model.backups.count == 4)
        #expect(model.latest?.name == "now-1.json")
        #expect(model.backUpError == nil)
    }

    @Test func aRunningBackupChangesTheButtonAndRejectsASecondRequest() async {
        let bench = bench()
        let model = BackupsModel(context: bench.context)
        await model.load()
        let gate = bench.calls.hold("backUpNow")
        let running = Task { await model.backUpNow(reason: nil) }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["backUpNow"] == 1 } })
        #expect(model.backUpButtonTitle == "Backing Up…")
        await model.backUpNow(reason: nil)
        #expect(bench.calls.calls.filter { $0 == "backUpNow" }.count == 1)
        gate.open()
        await running.value
        #expect(model.backUpButtonTitle == "Back Up Now")
    }

    @Test func aBackUpRefusedForWantOfAPermissionSaysSoOnTheRowAndReadsTheGrantsAgain() async {
        let bench = bench()
        bench.calls.fail("backUpNow", with: .notPermitted("backups.manage"))
        let model = BackupsModel(context: bench.context)
        await model.load()
        await model.backUpNow(reason: nil)
        #expect(model.backUpError == OwnerWording.line(.notPermitted("backups.manage"), on: .backups))
        #expect(bench.refreshed == 1)
    }

    @Test func aRestoreAsksFirstThenShowsWhatItDid() async {
        let bench = bench()
        bench.calls.state.withLock { $0.restoreAnswer = BackupRestored(leftOut: ["sign_in"], added: 18, alreadyHeld: 1059, secretsToSet: ["posthog_project_token"]) }
        let model = BackupsModel(context: bench.context)
        await model.load()
        model.beginRestore(model.backups[1])
        #expect(model.sheet == .restore(model.backups[1]))
        #expect(bench.calls.state.withLock { $0.restores }.isEmpty, "asking restores nothing")
        await model.restore()
        #expect(bench.calls.state.withLock { $0.restores.map(\.name) } == ["b"])
        #expect(model.sheet == nil)
        #expect(model.restored?.outcome.added == 18)
        #expect(
            UpkeepWording.secretsLine(["posthog_project_token"], serverName: "Castell Studio")
                == "The PostHog project token.")
    }

    @Test func aRestoreCancelledAtTheSignInSheetRestoresNothingAndTheSheetStays() async {
        let bench = bench()
        bench.calls.fail("restore", with: .notConfirmed)
        let model = BackupsModel(context: bench.context)
        await model.load()
        model.beginRestore(model.backups[0])
        await model.restore()
        #expect(model.sheet == .restore(model.backups[0]))
        #expect(model.restored == nil)
        #expect(model.sheetError == "Nothing was changed: the sign-in wasn’t confirmed.")
        bench.calls.fail("restore", with: nil)
        await model.restore()
        #expect(model.restored != nil, "trying again after the owner confirms works")
    }

    @Test func aFolderThatIsNotAbsoluteIsNeverSent() async {
        let bench = bench()
        let model = BackupsModel(context: bench.context)
        await model.load()
        model.beginFolder()
        model.folderDraft = "Backups"
        #expect(!model.canSaveFolder)
        model.folderDraft = "/Volumes/../etc"
        #expect(!model.canSaveFolder)
        model.folderDraft = "/Volumes/New Backups"
        #expect(model.canSaveFolder)
        await model.saveFolder()
        #expect(bench.calls.state.withLock { $0.upkeepChanges } == [UpkeepSettingsChange(folder: .set("/Volumes/New Backups"))])
        #expect(model.sheet == nil)
        #expect(model.settings?.folder == "/Volumes/New Backups")
    }

    @Test func aFolderTheServerRefusesStaysInItsSheetWithTheLine() async {
        let bench = bench()
        bench.calls.fail("changeUpkeep", with: .refused("That folder does not exist."))
        let model = BackupsModel(context: bench.context)
        await model.load()
        model.beginFolder()
        model.folderDraft = "/Volumes/Gone"
        await model.saveFolder()
        #expect(model.sheet == .folder)
        #expect(model.folderDraft == "/Volumes/Gone")
        #expect(model.sheetError == "The server didn’t accept that folder. It must already exist on the machine it runs on.", "never the server's own text")
        #expect(model.takeDrafts() == [.typed(title: "Backup Folder Not Kept", text: "/Volumes/Gone")])
    }

    @Test func theIntervalAndNowhereAreSentAlone() async {
        let bench = bench()
        let model = BackupsModel(context: bench.context)
        await model.load()
        await model.setInterval(86_400)
        await model.setInterval(86_400)
        await model.keepNowhere()
        #expect(
            bench.calls.state.withLock { $0.upkeepChanges }
                == [UpkeepSettingsChange(intervalSeconds: 86_400), UpkeepSettingsChange(folder: .remove)])
        #expect(model.place == .nowhere)
    }

    @Test func anyRefusalOrFaultTheServerWordsItselfIsToldInTheAppsWordsNotTheServers() async {
        let bench = bench()
        bench.calls.fail("backups", with: .failed("ENOENT /var/lib/marfa/backups"))
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.failure == .failed("The server couldn’t do that."))
        bench.calls.fail("backups", with: nil)
        bench.calls.fail("backUpNow", with: .refused("backup_path /x is not a directory"))
        await model.load()
        await model.backUpNow(reason: nil)
        #expect(model.backUpError == "The server couldn’t do that.")
    }

    @Test func anObjectStoreIsShownAndNeverChangedFromHere() async {
        let bench = bench()
        bench.calls.state.withLock { $0.upkeep.objectStore = true }
        let model = BackupsModel(context: bench.context)
        await model.load()
        #expect(model.place == .objectStore)
    }

    @Test func eachBackupProblemIsTheAppsOwnWordsFromWhatTheServerCounts() {
        #expect(UpkeepWording.problems(BackupsHealth(state: .off, lastBackup: nil, reason: .noDestination)).map(\.title) == ["No backups are kept"])
        #expect(UpkeepWording.problems(BackupsHealth(state: .off, lastBackup: nil, reason: .turnedOff)).map(\.title) == ["Backups are turned off"])
        #expect(UpkeepWording.problems(BackupsHealth(state: .ok, lastBackup: nil)).isEmpty)
        #expect(UpkeepWording.problems(BackupsHealth(state: .failing, lastBackup: nil)).count == 1, "a failing status the server gave no count for still says so")
    }
}

@MainActor
@Suite(.hangLimit) struct UpdatesModelTests {
    private func ready(itself: Bool = true) -> UpdateStatus {
        UpdateStatus(
            running: "0.0.84", checksAutomatically: true, latest: UpdateRelease(version: "0.0.85", published: someday), available: true,
            checkFailed: false, updatesItself: itself, step: itself ? nil : "Stop it, install 0.0.85, then start it.", progress: nil, last: nil)
    }

    private func bench(_ status: UpdateStatus, grants: Set<InstancePermission> = [.instanceRead, .instanceMaintain, .configManage]) -> OwnerBench {
        let bench = OwnerBench(grants: grants)
        bench.calls.state.withLock { $0.update = status }
        return bench
    }

    @Test func updateIsOfferedOnlyWhereAReleaseIsReadyAndTheServerCanUpdateItself() async {
        let itself = bench(ready())
        let model = UpdatesModel(context: itself.context, pause: .zero)
        await model.load()
        #expect(model.canUpdate)
        let manualBench = bench(ready(itself: false))
        let manual = UpdatesModel(context: manualBench.context, pause: .zero)
        await manual.load()
        #expect(!manual.canUpdate)
        let noneBench = bench(
            UpdateStatus(
                running: "0.0.84", checksAutomatically: true, latest: nil, available: false, checkFailed: false, updatesItself: true, step: nil,
                progress: nil, last: nil))
        let none = UpdatesModel(context: noneBench.context, pause: .zero)
        await none.load()
        #expect(!none.canUpdate)
    }

    @Test func anUpdateStartsOnceAndIsFollowedThroughItsStepsToTheEnd() async {
        let bench = bench(ready())
        var restarting = ready()
        restarting.progress = UpdateProgress(stage: .restarting, release: "0.0.85")
        var finished = ready()
        finished.running = "0.0.85"
        finished.available = false
        finished.last = UpdateOutcome(result: .succeeded, release: "0.0.85", finished: someday)
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        bench.calls.state.withLock { $0.updateReads = [restarting, finished] }
        await model.update()
        #expect(bench.calls.state.withLock { $0.updatesStarted } == 1)
        #expect(model.status?.running == "0.0.85")
        #expect(!model.isUpdating)
        #expect(model.undone == nil)
    }

    @Test func aServerThatNeverComesBackIsGivenUpOnAndSaidSo() async {
        let bench = bench(ready())
        let model = UpdatesModel(context: bench.context, pause: .zero, patience: 3)
        await model.load()
        bench.calls.fail("updateStatus", with: .unreachable)
        await model.update()
        #expect(model.lostTrack)
        #expect(!model.isUpdating)
    }

    @Test func anUpdatePutBackIsToldAndOffersTryAgainWithNoSecondUpdate() async {
        var status = ready()
        status.last = UpdateOutcome(result: .putBack, release: "0.0.85", finished: someday)
        let putBack = bench(status)
        let model = UpdatesModel(context: putBack.context, pause: .zero)
        await model.load()
        #expect(model.undone?.release == "0.0.85")
        #expect(model.canUpdate, "Try Again starts it again")
        #expect(model.ready == nil, "and the Marfa row offers no second Update")
        var done = status
        done.running = "0.0.85"
        done.last = UpdateOutcome(result: .succeeded, release: "0.0.85", finished: someday)
        let doneBench = bench(done)
        let after = UpdatesModel(context: doneBench.context, pause: .zero)
        await after.load()
        #expect(after.undone == nil)
    }

    @Test func aStaleReadAfterAnUpdateWasPutBackLeavesTryAgainOnlyAndNoSecondStart() async {
        let bench = bench(ready())
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        let gate = bench.calls.hold("updateStatus")
        let stale = Task { await model.load() }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["updateStatus"] == 1 } })
        var putBack = ready()
        putBack.last = UpdateOutcome(result: .putBack, release: "0.0.85", finished: someday)
        bench.calls.state.withLock {
            $0.gates["updateStatus"] = nil
            $0.updateReads = [putBack]
        }
        async let first: Void = model.confirmUpdate()
        async let second: Void = model.confirmUpdate()
        _ = await (first, second)
        #expect(bench.calls.state.withLock { $0.updatesStarted } == 1)
        #expect(model.undone?.release == "0.0.85")
        bench.calls.state.withLock { $0.updateReads = [ready()] }
        gate.open()
        await stale.value
        #expect(model.undone?.release == "0.0.85", "the read that began before the update was put back is dropped")
        #expect(model.ready == nil, "so no second Update is offered")
        #expect(model.canUpdate, "only Try Again")
        #expect(bench.calls.state.withLock { $0.updatesStarted } == 1)
    }

    @Test func retryingARolledBackUpdateRequiresMaintainAtConfirmation() async {
        var status = ready()
        status.last = UpdateOutcome(result: .putBack, release: "0.0.85", finished: someday)
        let owner = bench(status)
        let model = UpdatesModel(context: owner.context, pause: .zero)
        await model.load()
        #expect(model.canUpdate)
        owner.grants.remove(.instanceMaintain)
        #expect(!model.canUpdate)
        #expect(!model.canCheck)
        owner.calls.fail("startUpdate", with: .notPermitted("instance.maintain"))
        await model.confirmUpdate()
        await model.checkForUpdates()
        #expect(!owner.calls.calls.contains("startUpdate"))
        #expect(!owner.calls.calls.contains("checkForUpdates"))
    }

    @Test func anUpdateRefusedForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async {
        let bench = bench(ready())
        bench.calls.fail("startUpdate", with: .notPermitted("instance.maintain"))
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        await model.update()
        #expect(model.error == .notPermitted("instance.maintain"))
        #expect(!model.isStarting)
        #expect(bench.refreshed == 1)
    }

    @Test func checkAutomaticallyIsChangedOnlyWhereSettingsAreRead() async {
        let allowed = bench(ready())
        let model = UpdatesModel(context: allowed.context, pause: .zero)
        await model.load()
        await model.setChecksAutomatically(false)
        #expect(allowed.calls.state.withLock { $0.upkeepChanges } == [UpkeepSettingsChange(checksForUpdates: false)])
        #expect(model.status?.checksAutomatically == false)
        let without = bench(ready(), grants: [.instanceRead])
        let readOnly = UpdatesModel(context: without.context, pause: .zero)
        await readOnly.load()
        await readOnly.setChecksAutomatically(false)
        #expect(without.calls.state.withLock { $0.upkeepChanges }.isEmpty)
    }

    @Test func aRefusedReadShowsTheState() async {
        let bench = bench(ready())
        bench.calls.fail("updateStatus", with: .notPermitted("instance.read"))
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        #expect(model.failure == .notPermitted("instance.read"))
        #expect(bench.refreshed == 1)
    }
}

@MainActor
@Suite(.hangLimit) struct HousekeepingModelTests {
    private func job(_ name: String, every: Int, _ outcome: HousekeepingJob.Outcome? = .succeeded) -> HousekeepingJob {
        HousekeepingJob(name: name, intervalSeconds: every, lastFinished: someday, outcome: outcome)
    }

    private func bench(grants: Set<InstancePermission> = [.instanceRead, .instanceMaintain]) -> OwnerBench {
        let bench = OwnerBench(grants: grants)
        bench.calls.state.withLock {
            $0.jobs = [
                job("heartbeat", every: 60), job("version-thinning", every: 3600, .held), job("backup", every: 3600),
                job("enrichment-sweep", every: 30), job("event-log-cleanup", every: 3600),
            ]
        }
        return bench
    }

    @Test func theJobsComeFromTheServerIncludingNewJobsAndFailedRuns() async {
        let bench = bench()
        let model = HousekeepingModel(context: bench.context)
        bench.calls.state.withLock { $0.jobs = [] }
        await model.load()
        #expect(model.hasLoaded && model.listed.isEmpty)
        let failed = job("new-job", every: 73, .failed)
        bench.calls.state.withLock { $0.jobs = [failed] }
        await model.load()
        #expect(model.listed == [failed])
        #expect(UpkeepWording.result(model.listed.first?.outcome) == "Failed")
    }

    @Test func confirmingAsksFirstAndSendsNothingUntilTheOwnerAgrees() async {
        let bench = bench()
        let model = HousekeepingModel(context: bench.context)
        let health = ServerHealthModel(context: bench.context)
        await model.load()
        model.askToConfirm(clock: someday)
        #expect(model.confirming == someday)
        model.cancelConfirming()
        #expect(model.confirming == nil)
        #expect(bench.calls.state.withLock { $0.clocksConfirmed } == 0)
        model.askToConfirm(clock: someday)
        await model.confirm(date: someday, health: health)
        #expect(bench.calls.state.withLock { $0.clocksConfirmed } == 1)
        #expect(model.confirming == nil)
        #expect(health.hasLoaded, "the hold is read again")
    }

    @Test func aDateTheServerRefusesToConfirmIsToldAndReadsTheGrantsAgain() async {
        let bench = bench()
        bench.calls.fail("confirmClock", with: .notPermitted("instance.maintain"))
        let model = HousekeepingModel(context: bench.context)
        await model.load()
        model.askToConfirm(clock: someday)
        await model.confirm(date: someday, health: ServerHealthModel(context: bench.context))
        #expect(model.confirmError == .notPermitted("instance.maintain"))
        #expect(bench.refreshed == 1)
        #expect(model.confirming == nil)
    }

    @Test func aRefusedListShowsTheState() async {
        let bench = bench()
        bench.calls.fail("housekeepingJobs", with: .notPermitted("instance.read"))
        let model = HousekeepingModel(context: bench.context)
        await model.load()
        #expect(model.failure == .notPermitted("instance.read"))
        #expect(bench.refreshed == 1)
    }

    @Test func upkeepPagesNameTheirPermissions() {
        let lines = [MarfaSettingsPage.backups, .housekeeping].map(\.permissionLine)
        #expect(Set(lines).count == 2)
        #expect(MarfaSettingsPage.backups.permission == .backupsManage)
        #expect(MarfaSettingsPage.housekeeping.permission == .instanceRead)
    }
}

@MainActor
@Suite(.hangLimit) struct UpkeepReviewFixTests {
    private func ready() -> UpdateStatus {
        UpdateStatus(
            running: "0.0.84", checksAutomatically: true, latest: UpdateRelease(version: "0.0.85", published: someday), available: true,
            checkFailed: false, updatesItself: true, step: nil, progress: nil, last: nil)
    }

    @Test func confirmDateSendsEvenWhenTheAlertsBindingClearedTheAskFirst() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain])
        let model = HousekeepingModel(context: bench.context)
        let health = ServerHealthModel(context: bench.context)
        model.askToConfirm(clock: someday)
        model.cancelConfirming()
        await model.confirm(date: someday, health: health)
        #expect(bench.calls.state.withLock { $0.clocksConfirmed } == 1)
    }

    @Test func confirmDateReadsTheHealthAgainAndAsksAboutTheDateTheClockReadsNow() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain])
        let later = someday.addingTimeInterval(86_400 * 3)
        bench.calls.state.withLock {
            $0.health?.housekeeping = HousekeepingHealth(failed: [], hold: ClockHold(clockAt: later, trustedAt: nil, endsAt: nil))
        }
        let model = HousekeepingModel(context: bench.context)
        let health = ServerHealthModel(context: bench.context)
        await model.askToConfirm(health: health)
        #expect(model.confirming == later, "the date is the one just read, not an earlier reading")
        bench.calls.state.withLock { $0.health?.housekeeping = HousekeepingHealth(failed: [], hold: nil) }
        model.cancelConfirming()
        await model.askToConfirm(health: health)
        #expect(model.confirming == nil, "nothing is asked once the hold has gone")
    }

    @Test func aServerThatConfirmedAnotherDateThanTheOneShownSaysSo() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain])
        let model = HousekeepingModel(context: bench.context)
        let health = ServerHealthModel(context: bench.context)
        bench.calls.state.withLock { $0.clockConfirmedAt = someday.addingTimeInterval(86_400 * 2) }
        await model.confirm(date: someday, health: health)
        #expect(model.confirmedInstead?.shown == someday)
        #expect(model.confirmedInstead?.confirmed == someday.addingTimeInterval(86_400 * 2))
        bench.calls.state.withLock { $0.clockConfirmedAt = someday }
        await model.confirm(date: someday, health: health)
        #expect(model.confirmedInstead == nil)
    }

    @Test func aFolderRefusedInItsSheetLeavesNoLineOnThePage() async {
        let bench = OwnerBench(grants: [.backupsManage, .configManage])
        bench.calls.fail("changeUpkeep", with: .refused("no"))
        let model = BackupsModel(context: bench.context)
        await model.load()
        model.beginFolder()
        model.folderDraft = "/Volumes/Gone"
        await model.saveFolder()
        #expect(model.rowError == nil)
        bench.calls.fail("changeUpkeep", with: .refused("no"))
        await model.setInterval(86_400)
        #expect(model.rowError != nil, "the interval pop-up's refusal does stand on the page")
        model.beginFolder()
        #expect(model.rowError == nil)
        await model.setInterval(900)
        model.close()
        #expect(model.rowError == nil)
    }

    @Test func updateIsNotReadyAgainWhileTheServerMayStillBeUpdating() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain, .configManage])
        bench.calls.state.withLock { $0.update = ready() }
        let model = UpdatesModel(context: bench.context, pause: .zero, patience: 2)
        await model.load()
        bench.calls.fail("updateStatus", with: .unreachable)
        await model.update()
        #expect(model.lostTrack)
        #expect(!model.canUpdate)
        #expect(model.ready == nil)
    }
}

@MainActor
@Suite(.hangLimit) struct UpkeepReviewWordingTests {
    @Test func aRestoreNamesTheSecretsMonitoringHoldsAndCountsTheOthersNeverTellingTheirKeys() {
        let line = UpkeepWording.secretsLine(["heartbeat_url", "posthog_project_token"], serverName: "Castell Studio")
        #expect(line == "The heartbeat address and the PostHog project token.")
        let more = UpkeepWording.secretsLine(["heartbeat_url", "object_store_secret_key", "other_key"], serverName: "Castell Studio")
        #expect(more == "The heartbeat address. 2 other settings are set on the machine Castell Studio runs on.")
        let one = UpkeepWording.secretsLine(["object_store_secret_key"], serverName: "Castell Studio")
        #expect(one == "1 setting is set on the machine Castell Studio runs on.")
        #expect(!more.contains("_") && !one.contains("_"))
    }
}

@MainActor
@Suite(.hangLimit) struct UpdatesReviewFixTests {
    private func ready(checks: Bool = true) -> UpdateStatus {
        UpdateStatus(
            running: "0.0.84", checksAutomatically: checks, latest: UpdateRelease(version: "0.0.85", published: someday), available: true,
            checkFailed: false, updatesItself: true, step: nil, progress: nil, last: nil)
    }

    @Test func checkForUpdatesIsOffWhileCheckAutomaticallyIsOffAndAsksTheServerNothing() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain, .configManage])
        bench.calls.state.withLock { $0.update = ready(checks: false) }
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        #expect(!model.canCheck)
        await model.checkForUpdates()
        #expect(bench.calls.state.withLock { $0.updatesChecked } == 0)
    }

    @Test func withoutInstanceMaintainTheModelSaysAllowMoreIsNeededBeforeAnyCall() async {
        let bench = OwnerBench(grants: [.instanceRead])
        bench.calls.state.withLock { $0.update = ready() }
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        #expect(model.needsMaintain)
        bench.grants.insert(.instanceMaintain)
        #expect(!model.needsMaintain)
    }

    @Test func theFollowerOutlivesThePageAndEndsWhenSettingsCloses() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain, .configManage])
        var running = ready()
        running.progress = UpdateProgress(stage: .swapping, release: "0.0.85")
        bench.calls.state.withLock { $0.update = running }
        let model = UpdatesModel(context: bench.context, pause: .milliseconds(5))
        let loading = Task { await model.load() }
        #expect(await eventually { bench.calls.calls.filter { $0 == "updateStatus" }.count >= 3 })
        loading.cancel()
        let read = bench.calls.calls.filter { $0 == "updateStatus" }.count
        #expect(await eventually { bench.calls.calls.filter { $0 == "updateStatus" }.count > read }, "a page that goes leaves it following")
        #expect(model.isFollowing)
        model.stop()
        await loading.value
        #expect(!model.isFollowing)
        let reads = bench.calls.calls.filter { $0 == "updateStatus" }.count
        try? await Task.sleep(for: .milliseconds(60))  // long enough for any follower that is still alive to read again
        #expect(bench.calls.calls.filter { $0 == "updateStatus" }.count == reads, "no read is made after the page has gone")
    }

    @Test func closingDuringTheSettingsReadDoesNotStartAnotherFollower() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain, .configManage])
        var running = ready()
        running.progress = UpdateProgress(stage: .swapping, release: "0.0.85")
        var finished = running
        finished.running = "0.0.85"
        finished.available = false
        finished.progress = nil
        bench.calls.state.withLock { $0.updateReads = [running, finished] }
        let settings = bench.calls.hold("upkeepSettings")
        let model = UpdatesModel(context: bench.context, pause: .zero)
        let loading = Task { await model.load() }

        #expect(await eventually { bench.calls.state.withLock { $0.waiting["upkeepSettings"] == 1 } })
        #expect(model.hasLoaded)
        model.stop()
        loading.cancel()
        let reads = bench.calls.calls.filter { $0 == "updateStatus" }.count
        settings.open()
        await loading.value

        #expect(!model.isFollowing)
        #expect(bench.calls.calls.filter { $0 == "updateStatus" }.count == reads)
    }

    @Test func anUpdateStartedWhileAnotherRunsFollowsTheOneThatRuns() async {
        let bench = OwnerBench(grants: [.instanceRead, .instanceMaintain, .configManage])
        var running = ready()
        running.progress = UpdateProgress(stage: .fetching, release: "0.0.85")
        bench.calls.state.withLock { $0.update = ready() }
        let model = UpdatesModel(context: bench.context, pause: .zero)
        await model.load()
        var done = ready()
        done.running = "0.0.85"
        done.available = false
        bench.calls.state.withLock { $0.updateReads = [done] }
        await model.update()
        #expect(model.status?.running == "0.0.85")
        #expect(bench.calls.state.withLock { $0.updatesStarted } == 1)
    }
}
