import Foundation
import Marfa
import Testing
@testable import MAPP

/// Connection's "MAPP’s Settings" section in each state, and Disconnect's choice to remove them first.
@Suite(.hangLimit)
@MainActor struct ConnectionSettingsTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    private func words(_ standing: PreferencesSync.Standing) -> ConnectionSettings {
        ConnectionSettings(standing: standing, name: "Home")
    }

    // MARK: The section

    @Test func syncingSaysWhereTheyAreKeptAndOffersRemove() {
        let syncing = words(.syncing)
        #expect(syncing.isShown)
        #expect(syncing.title == "Kept in Home")
        #expect(syncing.line == "Every Mac that connects to it uses them.")
        #expect(syncing.action == .remove && syncing.actionTitle == "Remove…")
    }

    @Test func withoutAPermissionTheySayTheyStayOnThisMacAndOfferAllowMore() {
        let needing = words(.off(.needsPermission))
        #expect(needing.title == "Kept on This Mac Only")
        #expect(needing.line == "MAPP isn’t allowed to keep them in Home yet. Once it is, every Mac that connects uses them.")
        #expect(needing.action == .allowMore && needing.actionTitle == "Allow More…")
    }

    @Test func whileTheCopyFillsItIsAQuietLineWithNothingToPress() {
        let filling = words(.off(.notFilled))
        #expect(filling.isShown && filling.action == .none && filling.actionTitle == nil)
        #expect(filling.line == "MAPP keeps them in Home once this Mac has finished downloading it.")
    }

    @Test func removedSettingsStayOnThisMacUntilThePersonKeepsThemAgain() {
        let removed = words(.off(.removed))
        #expect(removed.title == "Kept on This Mac Only")
        #expect(removed.line == "They were removed from Home. This Mac keeps its own.")
        #expect(removed.action == .keepAgain && removed.actionTitle == "Keep in Marfa Again")
    }

    @Test func withoutAMarfaTheSectionIsNotShown() {
        #expect(!words(.off(.noMarfa)).isShown)
    }

    @Test func removingAsksFirstAndSaysEveryMacLosesThem() {
        let syncing = words(.syncing)
        #expect(syncing.removeTitle == "Remove MAPP’s Settings from Home?")
        #expect(syncing.removeMessage == "Every Mac that connects to Home loses them. This Mac keeps its own, and your items stay.")
        #expect(ConnectionSettings.footer == "Window sizes and positions, column widths and On This Mac stay on each Mac.")
    }

    /// The section's state is the sync's own, so Allow More… moving it on needs nothing else.
    @Test func theSectionFollowsTheSyncsStanding() async throws {
        let suite = "ConnectionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: false, tablesWhole: false, instance: "instance-1"))
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(10), reload: {})
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
        keeps: Bool = true, removal: @escaping @MainActor () async throws -> Void = {}
    ) async throws -> (MarfaSettingsModel, HostBench) {
        let bench = try HostBench()
        let model = MarfaSettingsModel(host: bench.host())
        model.address = "http://first.test:8210"
        _ = model.host.scripted("key-1")
        await model.connect()
        model.settingsKept = MarfaSettingsModel.SettingsKept(isKept: { keeps }, remove: removal)
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
        let (model, bench) = try await connected(removal: { log.steps.append("remove") })
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
        (model, _) = try await connected(removal: {
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

    @Test func aRemovalThatFailsSignsNothingOutAndAsks() async throws {
        struct Refused: Error {}
        let (model, bench) = try await connected(removal: { throw Refused() })
        model.requestDisconnect()
        model.alsoRemovesSettings = true
        await model.disconnect()
        #expect(model.isConnected, "never silently")
        #expect(model.settingsRemovalFailure == .init(choice: nil))
        #expect(model.notice == nil)
        #expect(bench.hasCopy(first))

        model.stayConnected()
        #expect(model.settingsRemovalFailure == nil && model.isConnected)
    }

    @Test func disconnectingAnywayAfterAFailureLeavesWithoutTryingAgain() async throws {
        struct Refused: Error {}
        let log = Log()
        let (model, _) = try await connected(removal: {
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
        let (model, bench) = try await connected(removal: { log.steps.append("remove") })
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

    // MARK: The sync's removal

    @Test func aConfirmedRemovalReturnsOnlyOnceTheServerHasTakenIt() async throws {
        let suite = "ConnectionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let copy = FakePreferencesCopy()
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        #expect(sync.syncs)

        try await sync.remove(confirmed: true)
        #expect(await copy.sends == 1 && sync.standing == .off(.removed))
    }

    @Test func aRemovalTheServerDidNotTakeThrowsSoDisconnectCanSayIt() async throws {
        let suite = "ConnectionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let copy = FakePreferencesCopy()
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(10), reload: {})
        sync.attach(copy, library: "marfa:https://home", name: { "Home" })
        await sync.flush()
        await copy.setDelivers(false)
        await #expect(throws: (any Error).self) { try await sync.remove(confirmed: true) }
    }
}
