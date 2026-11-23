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
            $0.connectorHosts = [ConnectorHostInfo(id: "h1", name: "Mac mini", lastSeen: nil), ConnectorHostInfo(id: "h2", name: "Studio Mac", lastSeen: nil)]
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

    // MARK: Health

    @Test func healthIsDerivedInOrderFromWhatWasChosenWhatWasReportedAndWhatIsMissing() {
        func health(
            paused: Bool = false, host: String? = "h1", missing: [String] = [], registration: ConnectorRegistration? = Self.registration(),
            requested: Date? = nil, seen: Date? = nil
        ) -> ConnectorHealth {
            ConnectorHealth.of(
                control: ConnectorControl(host: host, registration: registration == nil ? nil : "r", paused: paused, runRequested: requested),
                registration: registration, settings: ConnectorSettingsReading(settings: [], missing: missing),
                host: host.map { ConnectorHostInfo(id: $0, name: "Mac mini", lastSeen: seen) }, now: Self.now)
        }
        #expect(health(paused: true, host: nil, missing: ["feeds"]) == .paused)
        #expect(health(host: nil, missing: ["feeds"]) == .needsSetup(missing: ["feeds"]))
        #expect(health(host: nil) == .noMachine)
        #expect(health(registration: nil) == .waiting(machineSeen: false))
        #expect(health(registration: nil, seen: Self.now) == .waiting(machineSeen: true))
        #expect(health(registration: Self.registration(problems: ["x"])) == .problems(count: 1))
        #expect(health(registration: Self.registration(ranAt: Self.now, succeeded: false)) == .lastRunFailed(Self.now))
        #expect(health(requested: Self.now) == .runRequested)
        #expect(health(registration: Self.registration(ranAt: nil)) == .notRunYet)
        #expect(health() == .ran(Self.now.addingTimeInterval(-120)))
        #expect(ConnectorHealth.of(control: nil, registration: nil, settings: nil, host: nil, now: Self.now) == .unread)
    }

    @Test func aConnectorWithNoSignOfLifeForAnHourIsNotHeardFromAndOneHeardLaterIsNot() {
        let old = Self.now.addingTimeInterval(-7200)
        let stale = ConnectorRegistration(lastHeartbeat: old, lastRun: nil, problems: [])
        let control = ConnectorControl(host: "h1", registration: "r", paused: false, runRequested: nil)
        func health(_ seen: Date?) -> ConnectorHealth {
            ConnectorHealth.of(
                control: control, registration: stale, settings: ConnectorSettingsReading(settings: [], missing: []),
                host: ConnectorHostInfo(id: "h1", name: "Mac mini", lastSeen: seen), now: Self.now)
        }
        #expect(health(nil) == .silent(since: old))
        #expect(health(Self.now.addingTimeInterval(-60)) == .notRunYet)
    }

    @Test func theListReadsEachConnectorsOwnState() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = rss(bench)
        await model.load()
        let entry = try! #require(model.entry("rss"))
        #expect(model.health(of: entry, now: Self.now) == .ran(Self.now.addingTimeInterval(-120)))
        #expect(model.hostName(of: entry) == "Mac mini")
        #expect(model.typeName("rss.entry") == "rss.entry")
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
        let model = rss(bench, paused: true)
        await model.load()
        await model.runNow("rss")
        #expect(model.rowErrors["rss"] == .refused("The connector is paused. Resume it to run it."))
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
        model.askToRemoveSecret(feeds, in: "rss")
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
        await model.signIn("google-calendar", returningTo: "com.withmarfa.mapp:/signed-in") { shown.append($0); return true }
        #expect(shown.isEmpty)
        #expect(model.signInProblems["google-calendar"] == "Set Google client ID and Google client secret first.")
    }

    @Test func aSignInIsStartedWithTheAppsRedirectShownInTheSheetAndThenReadBack() async {
        let bench = OwnerBench(grants: [.connectorsManage])
        let model = calendar(bench)
        await model.load()
        var shown: [URL] = []
        await model.signIn("google-calendar", returningTo: "com.withmarfa.mapp:/signed-in") { shown.append($0); return true }
        #expect(bench.calls.state.withLock { $0.signInReturnedTo } == ["com.withmarfa.mapp:/signed-in"])
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

    @Test func theServersSignInRefusalNamesItsSettings() {
        let refusal = MarfaError.server(
            status: 409, code: "connector_sign_in_settings_missing", message: "Set them.",
            details: .object(["settings": .array([.string("google_client_id"), .string("google_client_secret")])]), server: nil)
        #expect(ClientOwnerCalls.signInSettingsMissing(refusal) == ["google_client_id", "google_client_secret"])
        #expect(ClientOwnerCalls.signInSettingsMissing(MarfaError.server(status: 409, code: "connector_paused", message: "No.", details: nil, server: nil)) == nil)
    }

    @Test func aSignInWhoseReturnAddressIsRefusedIsToldWithoutTheParametersName() {
        let refused = MarfaError.validation(
            code: "validation_error", message: "return_to must name a path or an address on this server.", details: nil, server: nil)
        #expect(ClientOwnerCalls.signInReturnRefused(refused))
        #expect(!ClientOwnerCalls.signInReturnRefused(MarfaError.validation(code: "validation_error", message: "Too long.", details: nil, server: nil)))
    }

    @Test func aPluginsSentenceLabelsAreTitledAndAcronymsStay() {
        #expect(ConnectorWording.settingTitle("Google client ID") == "Google Client ID")
        #expect(ConnectorWording.settingTitle("Confirmation of a held batch of deletes") == "Confirmation of a Held Batch of Deletes")
        #expect(ConnectorWording.settingTitle("Private hosts") == "Private Hosts")
        #expect(ConnectorWording.settingTitle("Spacing between requests in milliseconds") == "Spacing Between Requests in Milliseconds")
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

    @Test func aTimeInASentenceHasItsDayInLowercase() {
        let now = Self.now
        let calendar = Calendar(identifier: .gregorian)
        let earlier = now.addingTimeInterval(-300)
        let line = ConnectorWording.head(hostName: nil, run: ConnectorRunInfo(succeeded: true, started: earlier, finished: earlier, summary: nil), now: now)
        #expect(line.hasPrefix("Last run today, "))
        #expect(ConnectorWording.line(.silent(since: earlier), hostName: nil, now: now).hasPrefix("Last heard from today, "))
        #expect(ConnectorWording.line(.lastRunFailed(earlier), hostName: nil, now: now).hasPrefix("Its last run, today, "))
    }

    @Test func theSidebarListsConnectorsBesideWebhooksAndFoldersAndItNeedsConnectorsManage() {
        #expect(MarfaSettingsPage.groups.contains([.connectors, .webhooks, .folders]))
        #expect(MarfaSettingsPage.connectors.permission == .connectorsManage)
        #expect(MarfaSettingsPage.connectors.permissionLine.contains("connectors"))
    }
}
