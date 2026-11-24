import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct ConnectorsModelTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func setting(
        _ name: String, _ label: String, kind: ConnectorSettingKind = .text, secret: Bool = false, required: Bool = false, isSet: Bool = false,
        value: ConnectorSettingValue? = nil, defaultValue: ConnectorSettingValue? = nil
    ) -> ConnectorSetting {
        ConnectorSetting(
            name: name, label: label, kind: kind, choices: [], secret: secret, required: required, defaultValue: defaultValue,
            value: secret ? nil : value, isSet: isSet, unreadable: false)
    }

    private static func summary(_ name: String, signIn: ConnectorSignInDeclaration? = nil, host: String? = nil) -> PluginConnectorSummary {
        PluginConnectorSummary(
            name: name, title: name.capitalized, description: "Entries from feeds.", mark: "lucide:rss", source: name, version: "0.0.13", hostID: host,
            kinds: [ConnectorKind(name: "entry", type: "rss.entry", direction: .into)], signIn: signIn)
    }

    private static let signIn = ConnectorSignInDeclaration(
        provider: "google", clientIDSetting: "google_client_id", clientSecretSetting: "google_client_secret", tokenSetting: "google_refresh_token")

    private static func registration(ranAt: Date? = now.addingTimeInterval(-120), succeeded: Bool = true, problems: [String] = []) -> ConnectorRegistration {
        ConnectorRegistration(
            lastHeartbeat: now.addingTimeInterval(-60),
            lastRun: ranAt.map { ConnectorRunInfo(succeeded: succeeded, started: $0, finished: $0, summary: "created 2") }, problems: problems)
    }

    /// An RSS connector on a machine, which has run, with its feeds set.
    private func rss(_ bench: OwnerBench, paused: Bool = false) -> ConnectorsModel {
        bench.calls.state.withLock {
            $0.connectorPlugins = [Self.summary("rss", host: "h1")]
            $0.connectorControls["rss"] = ConnectorControl(host: "h1", registration: "reg-rss", paused: paused, runRequested: nil)
            $0.connectorRegistrations["reg-rss"] = Self.registration()
            $0.connectorHosts = [
                ConnectorHostInfo(id: "h1", name: "Mac mini", lastSeen: nil, linked: true), ConnectorHostInfo(id: "h2", name: "Studio Mac", lastSeen: nil, linked: true),
            ]
            $0.connectorSettings["rss"] = ConnectorSettingsReading(
                settings: [Self.setting("rss_feeds", "Feeds", secret: true, required: true, isSet: true)], missing: [])
        }
        return ConnectorsModel(context: bench.context)
    }

    /// A Google Calendar connector on no machine with its client settings not set yet.
    private func calendar(_ bench: OwnerBench) -> ConnectorsModel {
        bench.calls.state.withLock {
            $0.connectorPlugins = [Self.summary("google-calendar", signIn: Self.signIn)]
            $0.connectorControls["google-calendar"] = ConnectorControl(host: nil, registration: nil, paused: false, runRequested: nil)
            $0.connectorSettings["google-calendar"] = ConnectorSettingsReading(
                settings: [
                    Self.setting("google_client_id", "Google client ID", required: true),
                    Self.setting("google_client_secret", "Google client secret", secret: true, required: true),
                    Self.setting("google_refresh_token", "Google refresh token", secret: true),
                ], missing: ["google_client_id", "google_client_secret"])
            $0.signInSetsToken = ("google-calendar", "google_refresh_token")
        }
        return ConnectorsModel(context: bench.context)
    }

    // MARK: Pause, Resume, Run Now

    @Test func pausingIsStoredAndClearsARunAskedFor() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        await model.runNow("rss")
        #expect(model.entry("rss")?.control?.runRequested != nil)
        await model.setPaused(true, for: "rss")
        #expect(model.entry("rss")?.control?.paused == true)
        #expect(model.entry("rss")?.control?.runRequested == nil)
        let entry = try #require(model.entry("rss"))
        #expect(model.health(of: entry) == .paused)
        await model.setPaused(false, for: "rss")
        #expect(model.entry("rss")?.control?.paused == false)
    }

    @Test func runNowWhilePausedIsRefusedAsTheServerSaysAndChangesNothing() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        bench.calls.state.withLock { $0.connectorControls["rss"]?.paused = true }
        await model.runNow("rss")
        #expect(model.rowErrors["rss"] == .connectorPaused)
        #expect(model.entry("rss")?.control?.paused == true)
        #expect(model.entry("rss")?.control?.runRequested == nil)
        await model.setPaused(false, for: "rss")
        #expect(model.rowErrors["rss"] == nil)
        await model.runNow("rss")
        #expect(model.rowErrors["rss"] == nil)
        #expect(model.entry("rss")?.control?.runRequested != nil)
    }

    @Test func aRunAskedForIsFollowedUntilTheConnectorHasTakenIt() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        await model.runNow("rss")
        #expect(model.entry("rss")?.control?.runRequested != nil)
        let following = Task { await model.followRun("rss", every: .milliseconds(10), attempts: 100) }
        bench.calls.state.withLock { $0.connectorControls["rss"]?.runRequested = nil }
        await following.value
        #expect(model.entry("rss")?.control?.runRequested == nil)
    }

    @Test func aRefusalForWantOfConnectorsManageHasTheGrantsReadAgain() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        bench.calls.fail("pauseConnector", with: .notPermitted("connectors.manage"))
        await model.setPaused(true, for: "rss")
        #expect(model.rowErrors["rss"] == .notPermitted("connectors.manage"))
        #expect(bench.refreshed == 1)
        #expect(model.entry("rss")?.control?.paused == false)
    }

    @Test func movingToAnotherMachineIsSentAndReadBack() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        await model.assign("rss", toHost: "h2")
        #expect(bench.calls.state.withLock { $0.connectorAssigned.map(\.host) } == ["h2"])
        #expect(model.entry("rss")?.control?.host == "h2")
        await model.assign("rss", toHost: "h2")
        #expect(bench.calls.state.withLock { $0.connectorAssigned.count } == 1)
    }

    @Test func noMachineIsSentAsNullOnlyAfterTheOwnerAgreesWhileTheConnectorRuns() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        await model.chooseNoMachine(for: "rss")
        #expect(bench.calls.state.withLock { $0.connectorAssigned.isEmpty })
        let asked = try #require(model.question)
        #expect(asked.change == .noMachine)
        model.cancelQuestion()
        #expect(bench.calls.state.withLock { $0.connectorAssigned.isEmpty })
        #expect(model.entry("rss")?.control?.host == "h1")

        await model.chooseNoMachine(for: "rss")
        await model.confirm(try #require(model.question))
        #expect(bench.calls.state.withLock { $0.connectorAssigned.map(\.host) } == [nil])
        #expect(model.entry("rss")?.control?.host == nil)
        // The list still names the machine it left, which never stands in for no machine.
        let entry = try #require(model.entry("rss"))
        #expect(model.hostID(of: entry) == nil)
        #expect(model.unplaced.map(\.name) == ["rss"])
    }

    @Test func aReadBegunBeforeNoMachineNeverPutsTheMachineBack() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench, paused: true)
        await model.load()
        let gate = bench.calls.hold("connectorControl")
        let older = Task { await model.reload("rss") }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["connectorControl"] ?? 0 } >= 1 })
        bench.calls.state.withLock { $0.gates["connectorControl"] = nil }
        await model.chooseNoMachine(for: "rss")
        #expect(model.entry("rss")?.control?.host == nil)
        gate.open()
        await older.value
        #expect(model.entry("rss")?.control?.host == nil)
    }

    @Test func noMachineAsksAboutAConnectorResumedElsewhereSinceThePageRead() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench, paused: true)
        await model.load()
        bench.calls.state.withLock { $0.connectorControls["rss"]?.paused = false }
        await model.chooseNoMachine(for: "rss")
        #expect(try #require(model.question).change == .noMachine)
        #expect(bench.calls.state.withLock { $0.connectorAssigned.isEmpty })
    }

    @Test func noMachineOnAPausedConnectorIsSentWithoutAsking() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench, paused: true)
        await model.load()
        await model.chooseNoMachine(for: "rss")
        #expect(model.question == nil)
        #expect(bench.calls.state.withLock { $0.connectorAssigned.map(\.host) } == [nil])
    }

    // MARK: Add a Connector

    /// RSS on no machine, and one machine already linked.
    private func unplacedRSS(_ bench: OwnerBench) -> ConnectorsModel {
        let model = rss(bench)
        bench.calls.state.withLock {
            $0.connectorPlugins = [Self.summary("rss")]
            $0.connectorControls["rss"]?.host = nil
            $0.connectorHosts = [ConnectorHostInfo(id: "h1", name: "Mac mini", lastSeen: nil, linked: true)]
        }
        return model
    }

    @Test func aNewMachinesLinkIsShownOnceAndNotKeptOrHandedOverOnceTheSheetCloses() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        #expect(adding.candidates.map(\.name) == ["rss"])
        adding.machineName = "  Studio Mac "
        await adding.add()
        #expect(bench.calls.state.withLock { $0.hostsMade } == ["Studio Mac"])
        #expect(bench.calls.state.withLock { $0.connectorAssigned.map(\.host) } == ["host-1"])
        let command = try #require(adding.command)
        #expect(command.hasSuffix("| sh -s -- 'https://marfa.castell.studio/connect#code-1'"))
        #expect(!String(describing: try #require(adding.placed?.link)).contains("code-1"))
        #expect(model.entry("rss")?.control?.host == "host-1")

        model.closeAdding()
        #expect(model.adding == nil)
        #expect(adding.placed == nil)
        #expect(adding.command == nil)

        // Closing Settings with the link on show tells that it can't be shown again, and hands over no link.
        bench.calls.state.withLock { $0.connectorControls["rss"]?.host = nil }
        await model.reload("rss")
        model.beginAdding()
        let again = try #require(model.adding)
        again.machineName = "Atlas"
        await again.add()
        #expect(again.command != nil)
        let told = model.takeDrafts()
        #expect(told.count == 1)
        if case .told(_, let message)? = told.first { #expect(!message.contains("code-")) } else { Issue.record("Expected a notice") }
        #expect(model.adding == nil)
        #expect(again.placed == nil)
    }

    @Test func aMachineAlreadyLinkedIsAssignedAndTheSheetClosesWithNoLink() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.place = .host("h1")
        await adding.add()
        #expect(bench.calls.state.withLock { ($0.linksMade, $0.connectorAssigned.map(\.host)) } == (0, ["h1"]))
        #expect(model.adding == nil)
    }

    @Test func aMachineMadeForAConnectorThatCouldNotBePlacedIsKeptAndNeverRemoved() async throws {
        for failure: OwnerFailure in [.notFound, .unreachable] {
            let bench = OwnerBench(grants: [.connectorsManage])
            let model = unplacedRSS(bench)
            await model.load()
            model.beginAdding()
            let adding = try #require(model.adding)
            adding.machineName = "Studio Mac"
            bench.calls.fail("assignConnector", with: failure)
            await adding.add()
            #expect(bench.calls.state.withLock { $0.connectorHosts.map(\.id) } == ["h1", "host-1"])
            #expect(adding.kept?.id == "host-1")
            #expect(adding.placed == nil && !adding.canAdd)
            #expect(model.adding != nil)
            #expect(model.hosts.map(\.id) == ["h1", "host-1"], "the machine kept can be chosen in Runs next time")
            #expect(model.takeDrafts().isEmpty, "the Machine Name was used")
        }
    }

    @Test func aLostAnswerToAnAssignmentThatHeldShowsTheCommand() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.machineName = "Studio Mac"
        bench.calls.state.withLock { $0.assignAnswerLost = .unreachable }
        await adding.add()
        #expect(adding.kept == nil)
        #expect(adding.error == nil)
        #expect(adding.command != nil)
        #expect(bench.calls.state.withLock { $0.connectorControls["rss"]?.host } == "host-1")
    }

    @Test func aKnownMachineIsOnlyAssignedSoTheLinkItWaitsOnStands() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        bench.calls.state.withLock { $0.connectorHosts.append(ConnectorHostInfo(id: "h2", name: "Studio Mac", lastSeen: nil, linked: false)) }
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.place = .host("h2")
        await adding.add()
        #expect(bench.calls.state.withLock { ($0.linksMade, $0.connectorAssigned.map(\.host)) } == (0, ["h2"]))
        let placed = try #require(adding.placed)
        #expect(placed.link == nil && !placed.madeLink)
        #expect(adding.command == nil)

        // Only New Link makes one.
        await adding.renewLink()
        #expect(bench.calls.state.withLock { $0.linksMade } == 1)
        #expect(adding.command != nil)
    }

    @Test func anEndedLinkIsNeverShownOrCopied() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.machineName = "Studio Mac"
        await adding.add()
        let expires = try #require(adding.placed?.link?.expires)
        var copied: [String] = []
        let didCopy = adding.copyCommand(at: expires.addingTimeInterval(1)) { copied.append($0) }
        #expect(!didCopy)
        #expect(copied.isEmpty)
        #expect(adding.liveLink(at: expires) == nil)
        // The ended link is dropped, so the sheet offers New Link.
        #expect(adding.placed?.link == nil)
        #expect(adding.command == nil)
    }

    @Test func aMachineNameTypedForAConnectorNotAddedIsHandedBack() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.machineName = "Studio Mac"
        bench.calls.fail("createConnectorHost", with: .refused("No."))
        await adding.add()
        #expect(adding.error != nil)
        #expect(adding.machineName == "Studio Mac")
        #expect(model.takeDrafts() == [.typed(title: String(localized: "Connector Not Added"), text: "Studio Mac")])

        // Typed, then Runs moved to a machine Marfa knows: still handed back.
        model.beginAdding()
        let again = try #require(model.adding)
        again.machineName = "Atlas"
        again.place = .host("h1")
        #expect(model.takeDrafts() == [.typed(title: String(localized: "Connector Not Added"), text: "Atlas")])
    }

    @Test func aMachineNameEditedWhileACallIsUnderWayIsHandedBackAsItIsNow() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = unplacedRSS(bench)
        await model.load()
        model.beginAdding()
        let adding = try #require(model.adding)
        adding.machineName = "Studio"
        let gate = bench.calls.hold("createConnectorHost")
        let call = Task { await adding.add() }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["createConnectorHost"] ?? 0 } >= 1 })
        adding.machineName = "Studio Mac"
        #expect(model.takeDrafts().isEmpty)
        gate.open()
        await call.value
        // The machine was made as "Studio", so the name as it is now is not one that made a machine.
        #expect(bench.calls.state.withLock { $0.hostsMade } == ["Studio"])
        #expect(bench.late.count == 2)
        #expect(bench.late.last == .typed(title: String(localized: "Connector Not Added"), text: "Studio Mac"))
    }

    @Test func aLinkThatTheShellWouldSplitIsNeverMadeIntoACommand() {
        #expect(AddConnectorModel.command(for: "https://m.example/connect#a'; rm -rf ~ #") == nil)
        #expect(AddConnectorModel.command(for: "https://m.example/connect#a b") == nil)
        #expect(AddConnectorModel.command(for: "file:///connect#abc") == nil)
        #expect(AddConnectorModel.command(for: "https://m.example/connect#abc") != nil)
    }

    // MARK: Settings

    @Test func aSecretIsSetThroughItsSheetAndIsNeverReadBackHeldOrHandedOver() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        let secret = try #require(model.entry("google-calendar")?.settings?.settings.first { $0.name == "google_client_secret" })
        model.beginSecret(secret, in: "google-calendar")
        model.secretDraft = "s3cret-value"
        #expect(model.takeDrafts().isEmpty)
        #expect(model.secretDraft.isEmpty)

        model.beginSecret(secret, in: "google-calendar")
        model.secretDraft = "s3cret-value"
        await model.saveSecret()
        #expect(model.sheet == nil)
        #expect(model.secretDraft.isEmpty)
        let held = try #require(model.entry("google-calendar")?.settings?.settings.first { $0.name == "google_client_secret" })
        #expect(held.isSet)
        #expect(held.value == nil)
        #expect(model.entry("google-calendar")?.settings?.missing == ["google_client_id"])
        #expect(bench.calls.state.withLock { $0.connectorSettingsSent.last?.changes["google_client_secret"] } == .set(.text("s3cret-value")))
        #expect(model.takeDrafts().isEmpty)
    }

    @Test func removingASecretClearsItWithNullAndTheRequiredOneIsMissingAgain() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        let feeds = try #require(model.entry("rss")?.settings?.settings.first)
        model.beginSecret(feeds, in: "rss")
        model.askToRemoveSecret()
        #expect(model.sheet == nil)
        #expect(bench.calls.state.withLock { $0.connectorSettingsSent.isEmpty })
        await model.confirm(try #require(model.question))
        #expect(bench.calls.state.withLock { $0.connectorSettingsSent.last?.changes["rss_feeds"] } == .clear)
        #expect(model.entry("rss")?.settings?.missing == ["rss_feeds"])
        let entry = try #require(model.entry("rss"))
        #expect(model.health(of: entry) == .needsSetup(missing: ["rss_feeds"]))
    }

    @Test func aTypedTextSettingIsKeptWhenTheServerRefusesAndHandedOverWhenSettingsCloses() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        bench.calls.state.withLock {
            $0.connectorPlugins = [Self.summary("github")]
            $0.connectorControls["github"] = ConnectorControl(host: nil, registration: nil, paused: false, runRequested: nil)
            $0.connectorSettings["github"] = ConnectorSettingsReading(settings: [Self.setting("github_organization", "Organization")], missing: [])
        }
        let model = ConnectorsModel(context: bench.context)
        await model.load()
        let organization = try #require(model.entry("github")?.settings?.settings.first)
        bench.calls.fail("changeConnectorSettings", with: .refused("Not accepted."))
        model.drafts["github/github_organization"] = " castell "
        await model.commit(organization, in: "github")
        #expect(model.settingErrors["github/github_organization"] == "Not accepted.")
        #expect(model.text(of: organization, in: "github") == " castell ")
        #expect(model.takeDrafts() == [.typed(title: "Organization Not Saved", text: " castell ")])

        bench.calls.fail("changeConnectorSettings", with: nil)
        model.drafts["github/github_organization"] = " castell "
        await model.commit(organization, in: "github")
        #expect(bench.calls.state.withLock { $0.connectorSettingsSent.last?.changes["github_organization"] } == .set(.text("castell")))
        #expect(model.drafts.isEmpty)
    }

    @Test func aNumberThatIsNotOneIsToldAndNothingIsSent() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        bench.calls.state.withLock {
            $0.connectorPlugins = [Self.summary("github")]
            $0.connectorControls["github"] = ConnectorControl(host: nil, registration: nil, paused: false, runRequested: nil)
            $0.connectorSettings["github"] = ConnectorSettingsReading(
                settings: [Self.setting("github_request_spacing_ms", "Request spacing", kind: .number)], missing: [])
        }
        let model = ConnectorsModel(context: bench.context)
        await model.load()
        let spacing = try #require(model.entry("github")?.settings?.settings.first)
        model.drafts["github/github_request_spacing_ms"] = "soon"
        await model.commit(spacing, in: "github")
        #expect(model.settingErrors["github/github_request_spacing_ms"] == "Enter a number.")
        #expect(bench.calls.state.withLock { $0.connectorSettingsSent.isEmpty })
    }

    // MARK: Vendor sign-in

    @Test func aSignInThatCannotStartNamesTheSettingsItNeedsByTheirLabels() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        bench.calls.fail("startConnectorSignIn", with: .signInNeeds(["google_client_id", "google_client_secret"]))
        var shown: [URL] = []
        await model.signIn("google-calendar", returningTo: "com.withmarfa.marfa:/signed-in") { shown.append($0); return true }
        #expect(shown.isEmpty)
        #expect(model.signInProblems["google-calendar"] == "Set Google client ID and Google client secret first.")
    }

    @Test func aSignInIsStartedWithTheAppsRedirectShownInTheSheetAndThenReadBack() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        var shown: [URL] = []
        await model.signIn("google-calendar", returningTo: "com.withmarfa.marfa:/signed-in") { shown.append($0); return true }
        #expect(bench.calls.state.withLock { $0.signInReturnedTo } == ["com.withmarfa.marfa:/signed-in"])
        #expect(shown == [URL(string: "https://accounts.example.com/sign-in")!])
        #expect(model.signInProblems["google-calendar"] == nil)
        #expect(model.entry("google-calendar").map(model.isSignedIn) == true)
        #expect(model.signingIn == nil)
        // The token is the sign-in's, so the settings list leaves it out.
        #expect(model.entry("google-calendar").map(model.shownSettings)?.map(\.name) == ["google_client_id", "google_client_secret"])
    }

    @Test func aSignInThatFailedIsToldInWordsFromTheServersOutcomeWordAndNeverTheProvidersText() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        bench.calls.state.withLock { $0.signInStatus = .failed(reason: "invalid_client") }
        await model.signIn("google-calendar", returningTo: "x:/y") { _ in true }
        #expect(model.signInProblems["google-calendar"] == "Google didn’t accept the client ID or the client secret.")
        #expect(model.entry("google-calendar").map(model.isSignedIn) == false)
        bench.calls.state.withLock { $0.signInStatus = .pending }
        await model.signIn("google-calendar", returningTo: "x:/y") { _ in false }
        #expect(model.signInProblems["google-calendar"] == "The sign-in didn’t finish.")
    }

    // MARK: The page

    @Test func aSignInReadBackAsAnotherOnesIsToldAsNotFinishedWhateverItsStatus() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        bench.calls.state.withLock { $0.signInReadID = "someone-elses" }
        await model.signIn("google-calendar", returningTo: "x:/y") { _ in true }
        #expect(model.signInProblems["google-calendar"] == "The sign-in didn’t finish.")
        bench.calls.state.withLock { $0.signInReadID = nil }
        await model.signIn("google-calendar", returningTo: "x:/y") { _ in true }
        #expect(model.signInProblems["google-calendar"] == nil)
    }

    @Test func aRegistrationThatCouldNotBeReadIsNotTakenForOneThatHasNotStarted() async throws {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        bench.calls.fail("connectorRegistration", with: .failed("No answer."))
        await model.load()
        let entry = try #require(model.entry("rss"))
        #expect(model.health(of: entry, now: Self.now) == .unread)
        bench.calls.fail("connectorRegistration", with: nil)
        await model.reload("rss")
        let read = try #require(model.entry("rss"))
        #expect(model.health(of: read, now: Self.now) == .ran(Self.now.addingTimeInterval(-120)))
    }

    @Test func theSidebarListsConnectorsBesideWebhooksAndFoldersAndItNeedsConnectorsManage() {
        #expect(MarfaSettingsPage.groups.contains([.connectors, .webhooks, .folders]))
        #expect(MarfaSettingsPage.connectors.permission == .connectorsManage)
        #expect(MarfaSettingsPage.connectors.permissionLine.contains("connectors"))
    }
}
