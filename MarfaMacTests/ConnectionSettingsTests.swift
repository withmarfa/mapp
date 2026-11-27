import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// General’s settings in each state, and Disconnect’s choice to remove them first.
@Suite(.hangLimit)
@MainActor struct ConnectionSettingsTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    private func words(_ standing: PreferencesSync.Standing) -> ConnectionSettings {
        ConnectionSettings(standing: standing, name: "Home")
    }

    // MARK: The section

    @Test func withoutAPermissionTheySayTheyStayOnThisMacAndOfferAllowMore() {
        let needing = words(.off(.needsPermission))
        #expect(needing.title == "Kept on this Mac only")
        #expect(needing.line == "The app isn’t allowed to keep them in Home yet. Once it is, every Mac that connects uses them.")
        #expect(needing.action == .allowMore && needing.actionTitle == "Allow More…")
    }

    @Test func removedSettingsStayOnThisMacUntilThePersonKeepsThemAgain() {
        let removed = words(.off(.removed))
        #expect(removed.title == "Kept on this Mac only")
        #expect(removed.line == "They were removed from Home. This Mac keeps its own.")
        #expect(removed.action == .keepAgain && removed.actionTitle == "Keep in Marfa Again")
    }

    @Test func removingAsksFirstAndSaysEveryMacLosesThem() {
        let syncing = words(.syncing)
        #expect(syncing.removeTitle == "Remove This App’s Settings from Home?")
        #expect(syncing.removeMessage == "Every Mac that connects to Home loses them. This Mac keeps its own, and your items stay.")
        #expect(syncing.title == "Kept in this Marfa")
        #expect(syncing.line == "Every Mac that connects to it uses them.")
        #expect(syncing.actionTitle == "Remove…")
    }

    /// The section's state is the sync's own, so Allow More… moving it on needs nothing else.
    @Test func theSectionFollowsTheSyncsStanding() async throws {
        let defaults = ThrowawayDefaults.make("ConnectionSettingsTests")
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: false, tablesWhole: false, instance: "instance-1"))
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        #expect(ConnectionSettings(standing: sync.standing, name: "Home").action == .allowMore)

        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-1"))
        await sync.flush()
        #expect(ConnectionSettings(standing: sync.standing, name: "Home").action == .remove)
    }

    // MARK: Disconnect

    /// A model on a host with a connection, whose settings are kept or not, and what removing them did.
    private func connected(
        keeps: Bool = true, removal: @escaping @MainActor (Bool) async throws -> Void = { _ in },
        waiting: @escaping @MainActor (Set<String>) async -> Bool = { _ in false }
    ) async throws -> (MarfaSettingsModel, HostBench) {
        let bench = HostBench()
        let model = MarfaSettingsModel(host: bench.host())
        model.address = "http://first.test:8210"
        _ = model.host.scripted("key-1")
        await model.connect()
        model.settingsKept = MarfaSettingsModel.SettingsKept(isKept: { keeps }, remove: removal, isRemovalWaiting: waiting)
        return (model, bench)
    }

    @MainActor final class Log {
        var steps: [String] = []
    }

    @Test func theChoiceIsOffWhenAskedAndOnlyOfferedWhereTheSettingsAreKept() async throws {
        let (kept, _) = try await connected()
        kept.alsoRemovesSettings = true
        kept.requestDisconnect()
        #expect(kept.offersSettingsRemoval)
        #expect(!kept.alsoRemovesSettings, "off each time the person asks")
        #expect(kept.isConfirmingDisconnect)

        let (notKept, _) = try await connected(keeps: false)
        notKept.requestDisconnect()
        #expect(!notKept.offersSettingsRemoval)
    }

    @Test func leavingWithoutTheChoiceRemovesNothing() async throws {
        let log = Log()
        let (model, bench) = try await connected(removal: { _ in log.steps.append("remove") })
        model.requestDisconnect()
        await model.disconnect()
        #expect(log.steps.isEmpty)
        #expect(!model.isConnected)
        #expect(!bench.hasCopy(first))
    }

    @Test func leavingWithTheChoiceRemovesThemBeforeTheSignOut() async throws {
        let log = Log()
        var connectedWhenRemoving: Bool?
        var model: MarfaSettingsModel!
        (model, _) = try await connected(removal: { _ in
            log.steps.append("remove")
            connectedWhenRemoving = model.isConnected
        })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(log.steps == ["remove"])
        #expect(connectedWhenRemoving == true, "the sign-in is still held when they are removed")
        #expect(!model.isConnected)
        #expect(model.settingsRemovalFailure == nil)
    }

    @Test func anOldQueueCountDoesNotLoseTheCheckedSettingsChoice() async throws {
        let log = Log()
        let (model, bench) = try await connected(removal: { sendsOtherChanges in
            log.steps.append(sendsOtherChanges ? "send everything" : "remove settings")
        })
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 1, queueRead: true))
        source.unsentCount.withLock { $0 = 0 }
        try #require(await eventually { model.host.waitingChanges == 1 })

        model.requestDisconnect()
        try #require(await eventually { model.isConfirmingDisconnect })
        model.alsoRemovesSettings = true
        await model.disconnect()

        #expect(log.steps == ["remove settings"])
        #expect(!model.isConnected)
    }

    @Test func aRemovalThatFailsSignsNothingOutAndAsks() async throws {
        struct Refused: Error {}
        let (model, bench) = try await connected(removal: { _ in throw Refused() })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(model.isConnected, "never silently")
        #expect(model.settingsRemovalFailure == .init(reason: .notDone, choice: nil))
        #expect(model.notice == nil)
        #expect(bench.hasCopy(first))

        model.stayConnected()
        #expect(model.settingsRemovalFailure == nil && model.isConnected)
    }

    @Test func disconnectingAnywayAfterAFailureLeavesWithoutTryingAgain() async throws {
        struct Refused: Error {}
        let log = Log()
        let (model, _) = try await connected(removal: { _ in
            log.steps.append("remove")
            throw Refused()
        })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(log.steps == ["remove"])

        await model.disconnectAnyway()
        #expect(log.steps == ["remove"])
        #expect(!model.isConnected)
        #expect(model.settingsRemovalFailure == nil)
    }

    @Test func withChangesWaitingTheQuestionComesBeforeAnythingIsRemoved() async throws {
        let log = Log()
        let (model, bench) = try await connected(removal: { _ in log.steps.append("remove") })
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        #expect(await eventually { model.departure != nil })
        #expect(log.steps.isEmpty, "a person who cancels the question has removed nothing")
        #expect(model.alsoRemovesSettings, "the choice stays with the question")

        model.cancelDeparture()
        #expect(log.steps.isEmpty && !model.alsoRemovesSettings && model.isConnected)

        model.requestDisconnect()
        model.alsoRemovesSettings = true
        #expect(await eventually { model.departure != nil })
        await model.answer(.keepCopy)
        #expect(log.steps == ["remove"])
        #expect(!model.isConnected)
    }

    // MARK: Failed removals

    @Test func afterAFailedRemovalTheChoiceIsOfferedOnlyWhereTheSettingsAreStillKept() async throws {
        struct Refused: Error {}
        var kept = true
        let (model, _) = try await connected(removal: { _ in
            kept = false
            throw Refused()
        })
        model.settingsKept?.isKept = { kept }
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(model.settingsRemovalFailure != nil)
        #expect(!model.offersSettingsRemoval && !model.alsoRemovesSettings, "queued and not taken: no longer to offer")

        model.stayConnected()
        kept = true
        model.requestDisconnect()
        #expect(model.offersSettingsRemoval, "asked again, it is read again")
    }

    @Test func aRemovalThatNeverStartedIsStillOffered() async throws {
        let (model, _) = try await connected(removal: { _ in throw PreferencesSync.RemovalError.otherChangesWait })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(model.settingsRemovalFailure?.reason == .discardedChangesWait || model.settingsRemovalFailure?.reason == .notDone)
        #expect(model.offersSettingsRemoval)
    }

    // MARK: Discarding with the choice

    /// What each step of a disconnect sent, over a real sync on a copy that holds a change of the library's.
    private func overSync(_ copy: FakePreferencesCopy, delivers: Bool = true) async throws -> (MarfaSettingsModel, PreferencesSync, HostBench) {
        let defaults = ThrowawayDefaults.make("ConnectionSettingsTests")
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        await copy.setDelivers(delivers)
        let (model, bench) = try await connected(removal: { _ in })
        model.settingsKept = .over(sync)
        return (model, sync, bench)
    }

    @Test func discardingWithTheChoiceNeverSendsWhatWasDiscarded() async throws {
        let copy = FakePreferencesCopy()
        let (model, sync, bench) = try await overSync(copy)
        await copy.queueLibraryWrite()
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        #expect(await eventually { model.departure != nil })
        model.alsoRemovesSettings = true
        await model.answer(.discardCopy)

        #expect(await copy.sentLibraryWrites.isEmpty, "the discarded change never reached the server")
        #expect(await copy.sends == 0)
        #expect(await copy.removed.isEmpty && sync.syncs, "nothing was removed either")
        #expect(model.settingsRemovalFailure == .init(reason: .discardedChangesWait, choice: .discardCopy))
        #expect(model.isConnected)
    }

    @Test func keepingTheCopyWithTheChoiceSendsTheRemovalAndTheWaitingChanges() async throws {
        let copy = FakePreferencesCopy()
        let (model, sync, bench) = try await overSync(copy)
        await copy.queueLibraryWrite()
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        #expect(await eventually { model.departure != nil })
        await model.answer(.keepCopy)
        #expect(await copy.sentLibraryWrites == ["library-write"])
        #expect(sync.standing == .off(.removed))
        #expect(!model.isConnected)
    }

    @Test func aChangeArrivingWhileSignOutIsConfirmedWaitsForKeepCopy() async throws {
        let copy = FakePreferencesCopy()
        let (model, sync, bench) = try await overSync(copy)
        model.requestDisconnect()
        #expect(model.isConfirmingDisconnect)
        model.alsoRemovesSettings = true
        await copy.queueLibraryWrite()
        try #require(bench.servers.last).unsentCount.withLock { $0 = 1 }

        await model.disconnect()

        #expect(model.isConnected && model.alsoRemovesSettings)
        #expect(model.settingsRemovalFailure == nil)
        #expect(model.departure?.unsent?.count == 1)
        #expect(await copy.sentLibraryWrites.isEmpty)
        #expect(await copy.removed.isEmpty && sync.syncs)

        await model.answer(.keepCopy)
        #expect(await copy.sentLibraryWrites == ["library-write"])
        #expect(!model.isConnected)
    }

    @Test func discardingWithoutTheChoiceLeavesTheSettingsAlone() async throws {
        let copy = FakePreferencesCopy()
        let (model, sync, bench) = try await overSync(copy)
        await copy.queueLibraryWrite()
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        model.requestDisconnect()
        #expect(await eventually { model.departure != nil })
        await model.answer(.discardCopy)
        #expect(await copy.sends == 0 && sync.syncs)
        #expect(!model.isConnected)
    }

    // MARK: A removal the server has not taken

    @Test func theDepartureNamesARemovalThatWaitsBecauseItHasNothingToRead() async throws {
        let (model, bench) = try await connected(waiting: { ids in !ids.isEmpty })
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        model.requestDisconnect()
        #expect(await eventually { model.departure != nil })
        #expect(model.departure?.holdsSettingsRemoval == true)

        let words = words(.syncing)
        #expect(words.removalWaiting == "One of them removes this app’s settings from Home. Discard the copy and the settings stay there.")
    }

    @Test func aRemovalQueuedAndNeverDeliveredIsFoundAmongTheUnsentWrites() async throws {
        let defaults = ThrowawayDefaults.make("ConnectionSettingsTests")
        let copy = FakePreferencesCopy()
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        await copy.setDelivers(false)
        await #expect(throws: PreferencesSync.RemovalError.notTaken) { try await sync.remove(confirmed: true) }
        #expect(sync.standing == .off(.removed))
        let queued = try #require(await copy.queuedRemovals.keys.first)
        #expect(await sync.isRemovalWaiting(among: [queued, "another"]))
        #expect(await !sync.isRemovalWaiting(among: ["another"]))
    }

    // MARK: The sync's removal

    private func syncing(_ copy: FakePreferencesCopy) async throws -> (PreferencesSync, UserDefaults) {
        let defaults = ThrowawayDefaults.make("ConnectionSettingsTests")
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        return (sync, defaults)
    }

    @Test func aConfirmedRemovalReturnsOnlyOnceTheServerHasTakenIt() async throws {
        let copy = FakePreferencesCopy()
        let (sync, _) = try await syncing(copy)
        #expect(sync.syncs)

        try await sync.remove(confirmed: true)
        #expect(await copy.sends == 1 && sync.standing == .off(.removed))
    }

    @Test func generalQueuesRemovalAndStopsSyncingWhileOffline() async throws {
        let copy = FakePreferencesCopy()
        let (sync, defaults) = try await syncing(copy)
        let item = try #require(sync.item?.id)
        await copy.setDelivers(false)

        try await sync.remove()
        #expect(sync.standing == .off(.removed) && sync.item == nil)
        #expect(await Set(copy.queuedRemovals.values) == [item])
        #expect(await copy.sends == 0)

        defaults.set("dark", forKey: AppearanceKey.theme)
        await sync.flush()
        #expect(sync.standing == .off(.removed) && sync.item == nil)
        #expect(await copy.writesToBinned == 0)

        try await sync.startAgain()
        #expect(sync.syncs && sync.item != nil && sync.item?.id != item)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.writesToBinned == 0)
    }

    @Test func aRemovalTheServerDidNotTakeThrowsSoDisconnectCanSayIt() async throws {
        let copy = FakePreferencesCopy()
        let (sync, _) = try await syncing(copy)
        await copy.setDelivers(false)
        await #expect(throws: PreferencesSync.RemovalError.notTaken) { try await sync.remove(confirmed: true) }
    }

    @Test func aRemovalNeverSendsTheLibrarysChangesUnlessItMay() async throws {
        let copy = FakePreferencesCopy()
        let (sync, _) = try await syncing(copy)
        await copy.queueLibraryWrite()
        await #expect(throws: PreferencesSync.RemovalError.otherChangesWait) {
            try await sync.remove(confirmed: true, sendsOtherChanges: false)
        }
        #expect(await copy.sends == 0)
        #expect(await copy.sentLibraryWrites.isEmpty)
        #expect(await copy.removed.isEmpty && sync.syncs, "the settings are as they were")

        try await sync.remove(confirmed: true, sendsOtherChanges: true)
        #expect(await copy.sentLibraryWrites == ["library-write"] && sync.standing == .off(.removed))
    }

    @Test func aChangeAnotherWriteMetDoesNotFailTheRemoval() {
        let removal: Set<String> = ["removal"]
        let refusal: Verdict? = .refused(Refusal(reason: "validation"))
        let accepted: Verdict? = .accepted
        let dead: Verdict? = .dead
        let unanswered: Verdict? = nil
        #expect(WorkingCopyPreferences.taken(removal, answers: ["removal": accepted, "library": refusal]))
        #expect(WorkingCopyPreferences.taken(removal, answers: ["library": refusal]), "answered and cleared")
        #expect(!WorkingCopyPreferences.taken(removal, answers: ["removal": refusal]))
        #expect(!WorkingCopyPreferences.taken(removal, answers: ["removal": unanswered]), "not answered")
        #expect(!WorkingCopyPreferences.taken(removal, answers: ["removal": dead]))
    }

    @Test func aStepUnderWayEndsBeforeARemovalAndNoneWritesToTheBin() async throws {
        let copy = FakePreferencesCopy()
        let (sync, defaults) = try await syncing(copy)
        defaults.set("dark", forKey: AppearanceKey.theme)
        await copy.pauseNextItems()
        let stepping = Task { await sync.flush() }
        #expect(try await eventuallyAsking { await copy.isHoldingItems })

        let removing = Task { try await sync.remove() }
        await Task.yield()
        #expect(await copy.removed.isEmpty, "the removal waits for the step under way")
        await copy.resume()
        await stepping.value
        try await removing.value

        #expect(sync.standing == .off(.removed) && sync.item == nil)
        #expect(await copy.writesToBinned == 0)
        await sync.flush()
        #expect(sync.standing == .off(.removed))
    }
}
