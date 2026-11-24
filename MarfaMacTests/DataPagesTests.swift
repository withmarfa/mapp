import Foundation
import Marfa
import MarfaAPI
import Synchronization
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct InstanceSettingChoiceTests {
    private func loaded(_ values: [InstanceSetting: InstanceValue] = [:]) async -> (InstanceSettingsModel, FakeInstanceConfig) {
        let source = FakeInstanceConfig(values)
        let model = InstanceSettingsModel { .init(id: "https://marfa.test", source: source) }
        await model.load()
        return (model, source)
    }

    @Test func aPageSavesOnlyTheSettingsItShows() async {
        let (model, source) = await loaded([.name: .text("Library"), .auditRetentionDays: .number(90)])
        // Another page's field was typed and left.
        model.draft[.auditRetentionDays] = "30"
        model.draft[.name] = "Home"
        await model.save([.name])
        #expect(source.sent == [InstanceConfigPatch(values: [.name: .text("Home")])])
        // What the other page holds is still its own draft.
        #expect(model.draft[.auditRetentionDays] == "30")
        #expect(model.canSave([.auditRetentionDays]))
    }

    @Test func aSettingWithAProblemBlocksOnlyItsOwnPage() async {
        let (model, _) = await loaded()
        model.draft[.versionMaxVersions] = "0"
        model.draft[.name] = "Home"
        #expect(!model.canSave([.versionMaxVersions]))
        #expect(model.canSave([.name]))
    }

    @Test func aSwitchIsSentAsASwitchAndAnEmptyOneRemovesTheSetting() async {
        let (model, source) = await loaded([.enrichmentEnabled: .flag(true)])
        model.draft[.enrichmentEnabled] = "false"
        model.draft[.mcpFetchEnabled] = "true"
        await model.save([.enrichmentEnabled, .mcpFetchEnabled])
        #expect(source.sent == [InstanceConfigPatch(values: [.enrichmentEnabled: .flag(false), .mcpFetchEnabled: .flag(true)])])
        model.draft[.enrichmentEnabled] = ""
        await model.save([.enrichmentEnabled])
        #expect(source.sent.last == InstanceConfigPatch(clear: [.enrichmentEnabled]))
    }

    @Test func aLogRetentionShortenedAsksFirstAndSaysWhatItRemoves() async {
        let (model, source) = await loaded([.auditRetentionDays: .number(90)])
        model.draft[.auditRetentionDays] = "30"
        await model.save([.auditRetentionDays])
        #expect(source.sent.isEmpty)
        let words = model.pending.map { $0.shortenings.map(InstanceWording.consequence).joined() } ?? ""
        #expect(words.contains("30 days"))
        #expect(words.contains("activity and webhook deliveries"))
        #expect(words.contains("can’t be recovered"))
        model.agree(model.pending!)
        #expect(model.pending == nil)
        #expect(await eventually { source.sent.count == 1 })
        #expect(source.sent == [InstanceConfigPatch(values: [.auditRetentionDays: .number(30)])])
    }

    @Test func noLimitOnALogIsTheFurthestAndAsksNothing() async {
        let (model, _) = await loaded([.auditRetentionDays: .number(90)])
        model.draft[.auditRetentionDays] = "0"
        await model.save([.auditRetentionDays])
        #expect(model.pending == nil)
        #expect(model.loaded?.number(.auditRetentionDays) == 0)
    }

    @Test func fewerCopiesAskNothingButLessFreeDiskDoes() async {
        let (model, source) = await loaded([.blobMinCopies: .number(3), .diskReserveMegabytes: .number(128)])
        model.draft[.blobMinCopies] = "1"
        model.draft[.diskReserveMegabytes] = "16"
        await model.save(Set(InstanceSetting.fileSettings))
        #expect(source.sent.isEmpty)
        #expect(model.pending?.shortenings == [.init(setting: .diskReserveMegabytes, change: .shorter(from: 128, to: 16))])
        if let pending = model.pending { await model.confirm(pending) }
        #expect(source.sent == [InstanceConfigPatch(values: [.blobMinCopies: .number(1), .diskReserveMegabytes: .number(16)])])
    }

    @Test func megabytesAreSentAsBytesAndReadBack() {
        let patch = InstanceConfigPatch(values: [.diskReserveMegabytes: .number(128), .mcpFetchMaxMegabytes: .number(50)])
        let body = MarfaServerCalls.patch(patch)
        #expect(body.diskReserveBytes == .value(134_217_728))
        #expect(body.mcpFetchMaxBytes == .value(52_428_800))
        #expect(MarfaServerCalls.patch(InstanceConfigPatch(clear: [.blobCleanupEnabled])).blobCleanupEnabled == .null)
        #expect(body.versionMaxVersions == nil)
    }

    @Test func theChoicesKeepAValueTheServerHoldsAndAlwaysOfferDefault() {
        let held = InstanceChoices.options(for: .versionRecentDays, holding: 45)
        #expect(held.first == InstanceChoices.Option(value: nil, title: "Default (30 Days)"))
        #expect(InstanceChoices.options(for: .name, holding: nil).first?.title == "Default")
        #expect(held.contains { $0.value == 45 && $0.title == "45 Days" })
        let values = held.dropFirst().compactMap(\.value)
        #expect(values == values.sorted())
        // Zero days means no limit where it keeps things, and is never offered for a version window.
        #expect(InstanceChoices.options(for: .auditRetentionDays, holding: nil).contains { $0.value == 0 && $0.title == "No Limit" })
        #expect(!InstanceChoices.options(for: .versionRecentDays, holding: nil).contains { $0.value == 0 })
        #expect(InstanceChoices.title(.versionRecentDays, 365) == "1 Year")
        #expect(InstanceChoices.title(.versionMaxVersions, 500) == "500 Versions")
        #expect(InstanceChoices.title(.blobCleanupGraceSeconds, 86_400) == "1 Day")
        #expect(InstanceChoices.title(.blobCleanupGraceSeconds, 3_600) == "1 Hour")
    }

    @Test func aPopUpShowsTheDefaultsValueWhereTheServerHoldsNone() {
        #expect(InstanceChoices.shown(for: .trashRetentionDays, holding: nil) == 60)
        #expect(InstanceChoices.title(.trashRetentionDays, 60) == "60 Days")
        #expect(InstanceChoices.shown(for: .trashRetentionDays, holding: 14) == 14)
        #expect(InstanceChoices.shown(for: .name, holding: nil) == nil)
        // The menu still offers the server's default by its own item, which says what it is.
        #expect(InstanceChoices.options(for: .trashRetentionDays, holding: 60).first?.title == "Default (60 Days)")
    }

    @Test func eachPageNamesThePermissionItNeeds() {
        #expect(MarfaSettingsPage.overview.permission == .instanceRead)
        #expect(MarfaSettingsPage.history.permission == .configManage)
        #expect(MarfaSettingsPage.fileStorage.permission == .configManage)
        #expect(MarfaSettingsPage.sources.permission == .keysManage)
        #expect(MarfaSettingsPage.recentlyDeleted.permission == .itemsPurge)
        #expect(Set(MarfaSettingsPage.groups.flatMap { $0 }) == Set(MarfaSettingsPage.allCases))
    }
}

@MainActor
@Suite(.hangLimit) struct OverviewModelTests {
    private func bench(grants: Set<InstancePermission> = [.instanceRead]) -> OwnerBench { OwnerBench(grants: grants) }

    @Test func theCountOfWhatNeedsAttentionIsTheSidebarsBadge() async {
        let bench = bench()
        bench.calls.state.withLock {
            $0.concerns = [
                AttentionConcern(kind: .key, reference: "key-1", title: "Backup script expires on Monday"),
                AttentionConcern(kind: .connector, reference: "rss", title: "RSS reports a problem"),
            ]
        }
        let model = OverviewModel(context: bench.context)
        await model.load()
        #expect(model.attentionCount == 2)
        #expect(model.hasLoaded)
    }

    @Test func noConcernsLeavesTheSectionToGoAndTheBadgeEmpty() async {
        let bench = bench()
        let model = OverviewModel(context: bench.context)
        await model.load()
        #expect(model.concerns.isEmpty)
        #expect(model.attentionCount == 0)
        #expect(model.health(of: .database).condition == .ok)
        #expect(model.backups.state == .ok)
    }

    private func overview(health: ServerHealth?, concerns: [AttentionConcern] = []) async -> OverviewModel {
        let bench = bench()
        bench.calls.state.withLock {
            $0.health = health
            $0.concerns = concerns
        }
        let model = OverviewModel(context: bench.context)
        await model.load()
        return model
    }

    private func standing(
        database: Condition = .ok, disk: Condition = .ok, files: Condition = .ok, backups: BackupsHealth = BackupsHealth(state: .ok, lastBackup: nil)
    ) -> ServerHealth {
        ServerHealth(database: database, disk: disk, files: files, backups: backups, housekeeping: nil)
    }

    @Test func eachPartTakesItsStatusFromTheServersHealthAndNeverFromAConcernsTitle() async {
        let model = await overview(
            health: standing(database: .down, disk: .degraded, files: .ok),
            concerns: [
                AttentionConcern(kind: .health, reference: "disk", title: "Disk is down"),
                AttentionConcern(kind: .health, reference: "blob_storage", title: "Blob storage is down"),
            ])
        #expect(model.health(of: .database).condition == .down)
        #expect(model.health(of: .disk).condition == .degraded)
        #expect(model.health(of: .files).condition == .ok)
        #expect(model.concerns.count == 2, "the concerns still say what needs attention")
    }

    @Test func aHealthTheServerCouldNotGiveIsNeverShownAsWorking() async {
        let model = await overview(health: nil)
        #expect(model.health(of: .database).condition == .unknown)
        #expect(model.health(of: .disk).condition == .unknown)
        #expect(model.health(of: .files).condition == .unknown)
        #expect(model.backups.state == .unknown)
        #expect(OverviewPage.backupsWord(model.backups) == "Couldn’t Check")
        #expect(OverviewPage.word(.unknown) == "Couldn’t Check")
    }

    @Test func aDatabaseThatReadsButCannotWriteIsNotWorking() {
        let wire = InstanceHealth(
            status: .down, claimed: true,
            components: .init(
                database: .init(status: .ok), databaseWrite: .init(status: .down, error: "disk full"), disk: .init(status: .ok),
                blobStorage: .init(status: .other("slow"))),
            backups: .init(status: .ok))
        let health = ServerHealth(wire)
        #expect(health.database == .down)
        #expect(health.files == .unknown, "a status the app does not know is never working")
        #expect(health.housekeeping == nil)
    }

    @Test func theBackupsRowFollowsTheServersOwnAccountOfThem() async {
        let off = await overview(health: standing(backups: BackupsHealth(state: .off, lastBackup: nil, reason: .noDestination)))
        #expect(off.backups.state == .off)
        let failing = await overview(
            health: standing(backups: BackupsHealth(state: .failing, lastBackup: nil, faults: [.runFailed(count: 2)])),
            concerns: [AttentionConcern(kind: .backup, reference: "something_new", title: "A notice")])
        #expect(failing.backups.state == .failing)
        let quiet = await overview(
            health: standing(), concerns: [AttentionConcern(kind: .backup, reference: "store", title: "The backup folder is not there")])
        #expect(quiet.backups.state == .ok, "a concern's reference no longer decides the row")
    }

    @Test func overviewReadsTheSameHealthAsTheOtherPages() async {
        let bench = bench()
        let health = ServerHealthModel(context: bench.context)
        let model = OverviewModel(context: bench.context, health: health)
        await model.load()
        #expect(health.hasLoaded)
        #expect(bench.calls.calls.filter { $0 == "health" }.count == 1)
    }

    @Test func aRefusalForWantOfAPermissionShowsTheStateAndReadsTheGrantsAgain() async {
        let bench = bench()
        bench.calls.fail("attention", with: .notPermitted("instance.read"))
        let model = OverviewModel(context: bench.context)
        await model.load()
        #expect(model.failure == .notPermitted("instance.read"))
        #expect(bench.refreshed == 1)
        #expect(model.concerns.isEmpty)
    }

    @Test func theServerNotAnsweringShowsItAndKeepsNothingOld() async {
        let bench = bench()
        let model = OverviewModel(context: bench.context)
        await model.load()
        bench.calls.fail("attention", with: .unreachable)
        await model.load()
        #expect(model.failure == .unreachable)
    }

    @Test func whatTheServerSaysOfItselfIsKeptButNeverRequired() async {
        let bench = bench()
        bench.calls.state.withLock {
            $0.metrics = InstanceMetricsReading(version: "0.0.89", databaseBytes: 214_000_000, fileBytes: 3_400_000_000)
            $0.update.running = "0.0.89"
            $0.update.available = true
            $0.update.latest = UpdateRelease(version: "0.0.90")
        }
        let model = OverviewModel(context: bench.context)
        await model.load()
        #expect(model.updateReady == "0.0.90")
        #expect(model.owner == "mira")
    }

    @Test func aDevelopmentBuildHasNoVersionToShow() async {
        let bench = bench()
        bench.calls.state.withLock { $0.update.running = "0.0.0" }
        let model = OverviewModel(context: bench.context)
        await model.load()
        #expect(model.releaseVersion == nil)
        bench.calls.state.withLock { $0.update.running = "0.0.89" }
        await model.load()
        #expect(model.releaseVersion == "0.0.89")
    }

    @Test func aFailedReleaseReadIsToldAndKeepsTheLastRelease() async {
        let bench = bench()
        let metrics = InstanceMetricsReading(version: "0.0.89", databaseBytes: 214_000_000, fileBytes: 3_400_000_000)
        bench.calls.state.withLock {
            $0.metrics = metrics
            $0.update.running = "0.0.89"
            $0.update.available = true
            $0.update.latest = UpdateRelease(version: "0.0.90")
        }
        let model = OverviewModel(context: bench.context)
        bench.calls.fail("instanceMetrics", with: .unreachable)
        bench.calls.fail("updateStatus", with: .unreachable)
        await model.load()
        #expect(model.failure == nil)
        #expect(model.releaseVersion == nil)
        #expect(model.releaseFailure == .unreachable)
        #expect(model.metricsFailure == .unreachable)

        bench.calls.fail("instanceMetrics", with: nil)
        bench.calls.fail("updateStatus", with: nil)
        await model.load()
        #expect(model.releaseFailure == nil)
        #expect(model.metricsFailure == nil)
        #expect(model.releaseVersion == "0.0.89")
        #expect(model.updateReady == "0.0.90")

        bench.calls.fail("instanceMetrics", with: .unreachable)
        bench.calls.fail("updateStatus", with: .unreachable)
        await model.load()
        #expect(model.releaseFailure == .unreachable)
        #expect(model.metricsFailure == .unreachable)
        #expect(model.releaseVersion == "0.0.89")
        #expect(model.updateReady == "0.0.90")
        #expect(model.metrics == metrics)
    }

    @Test func aConcernIsToldByItsTitleAndALineTheAppWordsNeverTheServersMessage() {
        let backup = AttentionConcern(kind: .backup, reference: "no_backup_destination", title: "No backups are kept")
        #expect(backup.shownTitle == "No backups are kept")
        #expect(backup.shownLine == "There is nowhere to keep backups.")
        let secret = AttentionConcern(kind: .setting, reference: "object_store_secret_key", title: "Set object_store_secret_key again")
        #expect(secret.shownTitle == "Set a Secret Again", "a setting the app has no name for is never told by its key")
        #expect(secret.shownLine?.contains("_") == false)
        let token = AttentionConcern(kind: .setting, reference: "posthog_project_token", title: "Set posthog_project_token again")
        #expect(token.shownTitle == "Set PostHog Project Token Again")
        let connector = AttentionConcern(kind: .connector, reference: "rss", title: "RSS reports problems")
        #expect(connector.shownLine == "It reports problems.")
        // No wording for the kind and reference: the title alone.
        #expect(AttentionConcern(kind: .backup, reference: "something_new", title: "A new notice").shownLine == nil)
        #expect(AttentionConcern(kind: .connector, reference: "x", title: "Something else").shownLine == nil)
        // Every kind with wording says nothing a person can't read: no backticks, no setting keys, no request paths.
        for kind in [AttentionConcern.Kind.health, .job, .folder, .key, .fault, .unavailable] {
            let line = AttentionConcern(kind: kind, reference: "x_y", title: "T").shownLine ?? ""
            #expect(!line.contains("`") && !line.contains("_") && !line.contains("PATCH"))
        }
    }

    @Test func twoTypesThatShareALabelAreToldApartByTheirParent() {
        let names = OwnerWording.typeNames([
            (id: "core.task", label: "Task", parent: nil),
            (id: "tickets.task", label: "Task", parent: "tickets.ticket"),
            (id: "tickets.ticket", label: "Ticket", parent: nil),
            (id: "core.note", label: "Note", parent: nil),
            (id: "a.thing", label: "Thing", parent: nil),
            (id: "b.thing", label: "Thing", parent: nil),
        ])
        #expect(names["tickets.task"] == "Task (Ticket)")
        #expect(names["core.task"] == "Task")
        #expect(names["core.note"] == "Note")
        #expect(names["a.thing"] == "Thing (a.thing)")
        #expect(Set(names.values).count == names.count)
    }

    @Test func theSelectionIsCountedInTheFootOfAPageTable() {
        #expect(SettingsPageTable<MarfaDeletedItem, EmptyView, EmptyView>.selectedText(2, of: 1_204) == "2 of 1,204 selected")
        #expect(SettingsPageTable<MarfaDeletedItem, EmptyView, EmptyView>.selectedText(0, of: 1_204) == "None selected")
    }

    @Test func theBackupsWordsAreWhatTheServerHolds() {
        let noon = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now) ?? .now
        #expect(OverviewPage.backupsWord(BackupsHealth(state: .off)) == "Off")
        #expect(OverviewPage.backupsWord(BackupsHealth(state: .failing)) == "Failing")
        #expect(OverviewPage.backupsWord(BackupsHealth(state: .ok, lastBackup: nil)) == "Working")
        #expect(OverviewPage.backupsWord(BackupsHealth(state: .ok, lastBackup: noon), now: noon).hasPrefix("Last at"))
    }
}

@MainActor
@Suite(.hangLimit) struct FileStorageModelTests {
    @Test func whereFilesAreComesFromTheServer() async {
        let bench = OwnerBench(grants: [.instanceRead, .configManage])
        bench.calls.state.withLock {
            $0.fileStores = FileStores(
                stores: [FileStoreRow(id: "a", kind: .disk, locator: "/var/lib/marfa/files", error: nil)],
                orphanCount: 3, orphanBytes: 12_000_000, firstFound: nil, orphansComplete: true)
            $0.metrics.fileBytes = 3_400_000_000
        }
        let model = FileStorageModel(context: bench.context)
        await model.load()
        #expect(model.stores?.stores.count == 1)
        #expect(model.stores?.orphanCount == 3)
    }

    @Test func aRefusalForWantOfAPermissionIsToldAndTheGrantsReadAgain() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.fail("fileStores", with: .notPermitted("instance.read"))
        let model = FileStorageModel(context: bench.context)
        await model.load()
        #expect(model.stores == nil)
        #expect(model.failure == .notPermitted("instance.read"))
        #expect(bench.refreshed == 1)
    }
}

@MainActor
@Suite(.hangLimit) struct SourceLimitModelTests {
    private func model(_ bench: OwnerBench, sources: [MarfaSourceRow] = []) -> SourceLimitModel {
        SourceLimitModel(context: bench.context, sources: { sources })
    }

    private let rows = [
        MarfaSourceRow(code: "readwise", name: "Readwise", mark: nil, count: 127, hasChosenName: false),
        MarfaSourceRow(code: "rss", name: "RSS", mark: nil, count: 156, hasChosenName: false),
    ]

    @Test func theLimitIsReadWithTheTypesAndSourcesItNames() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock {
            $0.sourceLimit = SourceLimit(instanceID: "instance-1", isOn: true, types: ["core.highlight"], sources: ["readwise"], strictTypes: nil, allowlist: nil)
            $0.names = ["core.highlight": "Highlights", "core.bookmark": "Bookmarks", "system.view": "Views"]
        }
        let model = model(bench, sources: rows)
        await model.load()
        #expect(model.isOn)
        #expect(model.types == ["core.highlight"])
        #expect(model.checkedSources == ["readwise"])
        #expect(model.typeChoices.map(\.title) == ["Bookmarks", "Highlights"])
        #expect(model.sourceChoices.map(\.code) == ["readwise", "rss"])
        #expect(!model.hasEdits)
    }

    @Test func aSourceTheLimitNamesThatHoldsNoItemsIsStillListedSoSavingNeverDropsIt() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock {
            $0.sourceLimit = SourceLimit(instanceID: "instance-1", isOn: true, types: ["core.note"], sources: ["gone"], strictTypes: nil, allowlist: nil)
        }
        let model = model(bench, sources: rows)
        await model.load()
        #expect(model.sourceChoices.map(\.code).contains("gone"))
    }

    @Test func savingSendsTheCheckedTypesAndSourcesAndKeepsTheOtherLevers() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["rss", "readwise"]
        #expect(model.canSave)
        await model.save()
        let sent = bench.calls.state.withLock { $0.limitsSent }
        #expect(sent.count == 1)
        #expect(sent.first??.types == ["core.note"])
        #expect(sent.first??.sources == ["readwise", "rss"])
        #expect(model.isOn)
        #expect(!model.hasEdits)
    }

    @Test func aLimitNamingTypesButNoSourceWaitsRatherThanHidingEverything() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        #expect(!model.canSave)
        await model.save()
        #expect(bench.calls.state.withLock { $0.limitsSent.isEmpty })
    }

    @Test func turningItOffRemovesTheFilter() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock {
            $0.sourceLimit = SourceLimit(instanceID: "instance-1", isOn: true, types: ["core.note"], sources: ["rss"], strictTypes: nil, allowlist: nil)
        }
        let model = model(bench, sources: rows)
        await model.load()
        await model.turnOff()
        let sent = bench.calls.state.withLock { $0.limitsSent }
        #expect(sent.count == 1)
        #expect(sent.first! == nil)
        #expect(!model.isOn)
        #expect(model.types.isEmpty)
    }

    @Test func aLimitChangedElsewhereIsToldAndWhatWasChosenStays() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["rss"]
        // Another device changed the limit after it was read.
        bench.calls.state.withLock { $0.sourceLimit.types = ["core.highlight"] }
        await model.save()
        #expect(model.line?.contains("changed somewhere else") == true)
        #expect(model.types == ["core.note"])
        #expect(model.checkedSources == ["rss"])
        #expect(model.limit?.types == ["core.highlight"])
        #expect(bench.calls.state.withLock { $0.limitsSent.isEmpty })
    }

    @Test func anotherMarfaAnsweringAtTheWriteIsToldAndTheDraftStartsAgainFromIt() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock {
            $0.sourceLimit = SourceLimit(instanceID: "instance-1", isOn: true, types: ["core.note"], sources: ["rss"], strictTypes: nil, allowlist: nil)
            $0.names = ["core.note": "Notes"]
        }
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note", "core.bookmark"]
        model.checkedSources = ["rss", "readwise"]
        // Between the read and the write, another Marfa takes the address and refuses the write.
        bench.calls.state.withLock { [calls = bench.calls] in
            $0.beforeLimitWrite = {
                calls.state.withLock {
                    $0.sourceLimit = SourceLimit(instanceID: "instance-2", isOn: true, types: ["core.highlight"], sources: ["readwise"], strictTypes: nil, allowlist: nil)
                    $0.names = ["core.highlight": "Highlights"]
                    $0.beforeLimitWrite = nil
                }
            }
        }
        await model.save()

        #expect(model.line == InstanceConfigFailure.instanceChanged.message)
        #expect(model.limit?.instanceID == "instance-2")
        #expect(model.types == ["core.highlight"])
        #expect(model.checkedSources == ["readwise"])
        #expect(!model.hasEdits)
        #expect(model.typeChoices.map(\.code) == ["core.highlight"])
        #expect(bench.calls.state.withLock { $0.limitsSent.isEmpty })
    }

    @Test func anotherMarfaFoundWhenTheLimitIsReadBeforeTheWriteGetsNoWrite() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["rss"]
        bench.calls.state.withLock {
            $0.sourceLimit = SourceLimit(instanceID: "instance-2", isOn: true, types: ["core.highlight"], sources: ["readwise"], strictTypes: nil, allowlist: nil)
        }
        await model.save()

        #expect(model.line == InstanceConfigFailure.instanceChanged.message)
        #expect(model.types == ["core.highlight"])
        #expect(model.checkedSources == ["readwise"])
        #expect(!model.hasEdits)
        #expect(bench.calls.state.withLock { $0.limitsSent.isEmpty })
        // Saving again sends nothing of the first instance's choice.
        #expect(!model.canSave)
    }

    @Test func aRefusalForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["rss"]
        bench.calls.fail("setSourceLimit", with: .notPermitted("config.manage"))
        await model.save()
        #expect(bench.refreshed == 1)
        #expect(model.line == OwnerWording.line(.notPermitted("config.manage")))
        #expect(model.types == ["core.note"])
    }

    @Test func whatWasChosenAndNotSavedIsHandedBackWhenSettingsCloses() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench, sources: rows)
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["rss"]
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        #expect(!model.hasEdits)
        #expect(model.takeDrafts().isEmpty)
    }

    @Test func theServerNotAnsweringShowsItWithNothingChosen() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.fail("sourceLimit", with: .unreachable)
        let model = model(bench)
        await model.load()
        #expect(model.failure == .unreachable)
        #expect(model.limit == nil)
    }
}

@MainActor
@Suite(.hangLimit) struct SourcesModelTests {
    /// A host's sources and the changes it was asked to make.
    @MainActor final class Server {
        var rows = [
            MarfaSourceRow(code: "rss", name: "RSS", mark: "lucide:rss", count: 156, hasChosenName: false),
            MarfaSourceRow(code: "github", name: "GitHub", mark: nil, count: 318, hasChosenName: true),
        ]
        var refusal: OwnerFailure?
        var changes: [(String, MarfaSourceChange)] = []

        var access: SourceAccess {
            SourceAccess(
                rows: { self.rows }, refresh: {},
                change: { code, change in
                    self.changes.append((code, change))
                    if let refusal = self.refusal { return refusal }
                    if case .rename(let name) = change, let index = self.rows.firstIndex(where: { $0.code == code }) {
                        let row = self.rows[index]
                        self.rows[index] = MarfaSourceRow(code: row.code, name: name, mark: row.mark, count: row.count, hasChosenName: true)
                    }
                    return nil
                },
                marks: { query, _ in ["lucide:inbox", "lucide:rss", "lucide:book-open"].filter { query.isEmpty || $0.contains(query) } })
        }
    }

    private let sets = [MarfaMarkSet(id: "lucide", title: "Lucide"), MarfaMarkSet(id: "simple-icons", title: "Simple Icons")]

    @Test func aRenameIsSentAndClosesTheSheet() async {
        let server = Server()
        let model = SourcesModel(access: server.access, markSets: sets)
        model.beginRename("rss")
        #expect(model.name == "RSS")
        #expect(!model.canRename)
        model.name = "  Feeds  "
        #expect(model.canRename)
        await model.rename()
        #expect(server.changes.count == 1)
        #expect(server.changes[0].0 == "rss")
        #expect(server.changes[0].1 == .rename("Feeds"))
        #expect(model.sheet == nil)
        #expect(model.row("rss")?.name == "Feeds")
    }

    @Test func aRefusedNameKeepsWhatWasTypedWithTheServersLine() async {
        let server = Server()
        server.refusal = .refused("A name is at most 200 characters.")
        let model = SourcesModel(access: server.access, markSets: sets)
        model.beginRename("rss")
        model.name = "Feeds"
        await model.rename()
        #expect(model.sheet == .name(code: "rss"))
        #expect(model.name == "Feeds")
        #expect(model.failure == "A name is at most 200 characters.")
        #expect(!model.isWorking)
    }

    @Test func theDefaultNameCanBeTakenBackOnlyWhereOneWasSet() async {
        let server = Server()
        let model = SourcesModel(access: server.access, markSets: sets)
        model.beginRename("rss")
        #expect(!model.canUseDefaultName)
        model.close()
        model.beginRename("github")
        #expect(model.canUseDefaultName)
        await model.useDefaultName()
        #expect(server.changes.first?.1 == .useDefaultName)
    }

    @Test func aMarkIsChosenFromTheSetAndRemovedOnlyWhereOneIsSet() async {
        let server = Server()
        let model = SourcesModel(access: server.access, markSets: sets)
        model.beginMark("rss")
        #expect(model.markSet.id == "lucide")
        #expect(model.canRemoveMark)
        #expect(model.markChoices.contains("lucide:inbox"))
        await model.choose(mark: "lucide:inbox")
        #expect(server.changes.first?.1 == .setMark("lucide:inbox"))
        model.beginMark("github")
        #expect(!model.canRemoveMark)
    }

    @Test func aChangeFromTheMenuTellsItsRefusalAboveTheList() async {
        let server = Server()
        server.refusal = .refused("Sources are named on your server.")
        let model = SourcesModel(access: server.access, markSets: sets)
        await model.removeMark("rss")
        #expect(model.listFailure == .refused("Sources are named on your server."))
    }

    @Test func aNameTypedAndNotSentIsHandedBackWhenSettingsCloses() {
        let server = Server()
        let model = SourcesModel(access: server.access, markSets: sets)
        model.beginRename("rss")
        model.name = "Feeds"
        #expect(model.takeDrafts() == [.typed(title: "Source Name Not Kept", text: "Feeds")])
        #expect(model.sheet == nil)
        // An unchanged name is nothing to hand back.
        model.beginRename("rss")
        #expect(model.takeDrafts().isEmpty)
    }

    @Test func howASourceGotItsNameIsToldInOneLine() {
        #expect(SourcesPage.naming(MarfaSourceRow(code: "a", name: "A", mark: nil, count: 1, hasChosenName: true)) == "Named by you.")
        #expect(SourcesPage.naming(MarfaSourceRow(code: "a", name: "a", mark: nil, count: 1, hasChosenName: false)) == "Not named yet.")
        #expect(SourcesPage.naming(MarfaSourceRow(code: "a", name: "RSS", mark: nil, count: 1, hasChosenName: false)) == "Named by its app or key.")
    }
}
