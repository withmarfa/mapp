import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// What MAPP lends the Marfa's pages: how the connection reads, what the sign-in holds, Allow More…, and what closing
/// Settings does with a draft. The sign-in is `ScriptedSignIns`, never the Keychain.
@Suite(.hangLimit)
@MainActor struct MarfaSettingsHostTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    private func connected(
        _ bench: HostBench, settings: InstanceSettingsModel? = nil
    ) async throws -> (MAPPMarfaSettingsHost, Libraries, FakeMarfaSource) {
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let adapter = MAPPMarfaSettingsHost(libraries: libraries, launcher: SettingsLauncher(), instanceSettings: settings)
        try await libraries.host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        #expect(await eventually { adapter.connection == .connected })
        return (adapter, libraries, source)
    }

    @Test func withNoServerSetThePagesHaveNoCopyOpen() throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let adapter = MAPPMarfaSettingsHost(libraries: libraries, launcher: SettingsLauncher())
        #expect(adapter.connection == .notConnected)
        #expect(adapter.grants.isEmpty)
    }

    @Test func aSignedOutAndANotAnsweringServerAreToldApart() async throws {
        let bench = try HostBench()
        let (adapter, _, source) = try await connected(bench)
        source.state.set(.offline(reason: nil))
        #expect(await eventually { if case .notAnswering = adapter.connection { true } else { false } })
        source.state.set(.keyRefused)
        #expect(await eventually { adapter.connection == .signedOut })
    }

    @Test func theConnectedPageReadsWhatTheSignInHolds() async throws {
        let bench = try HostBench()
        let (adapter, _, _) = try await connected(bench)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn)
        #expect(adapter.grants.contains(MarfaSettingsPage.overview.permission))
        #expect(!adapter.grants.contains(.backupsManage))
    }

    @Test func allowMoreCancelledChangesNothingAndLeavesThePageMissingIt() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(browser: [.failure(SignInError.canceled)])
        let outcome = await adapter.allowMore([.backupsManage])
        #expect(outcome == .cancelled)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn)
        #expect(libraries.host.notices.waiting.isEmpty, "a sign-in the person stopped needs no telling")
        #expect(bench.signIns.asked.last == SystemSignIns.askedAtSignIn.union([.backupsManage]), "it asked for what was held and the page's own")
    }

    @Test func allowMoreApprovedWithFewerChangesNothingTheOwnerWithheld() async throws {
        let bench = try HostBench()
        let (adapter, _, _) = try await connected(bench)
        bench.signIns.script(approving: [SystemSignIns.askedAtSignIn])
        bench.signIns.script(browser: [.success("again")])
        let outcome = await adapter.allowMore([.backupsManage])
        #expect(outcome == .approvedFewer)
        #expect(!adapter.grants.contains(.backupsManage))
        #expect(adapter.grants == SystemSignIns.askedAtSignIn)
    }

    @Test func allowMoreApprovedInFullOpensThePage() async throws {
        let bench = try HostBench()
        let (adapter, _, _) = try await connected(bench)
        bench.signIns.script(browser: [.success("again")])
        let outcome = await adapter.allowMore([.backupsManage])
        #expect(outcome == .allowed)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn.union([.backupsManage]))
        #expect(!adapter.isAllowingMore)
    }

    @Test func signingInAgainKeepsWhatWasAllowedBefore() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(browser: [.success("again")])
        _ = await adapter.allowMore([.backupsManage])
        await libraries.marfaSettings.start(.signInAgain(usingCode: false)).value
        #expect(bench.signIns.asked.last?.contains(.backupsManage) == true)
        #expect(adapter.grants.contains(.backupsManage))
    }

    @Test func allowMoreNeverAsksForSignInsManageAtSignIn() async throws {
        let bench = try HostBench()
        let (_, _, _) = try await connected(bench)
        #expect(!SystemSignIns.askedAtSignIn.contains(.signInsManage))
        #expect(!SystemSignIns.scopes.contains(InstancePermission.signInsManage.rawValue))
    }

    @Test func closingSettingsHandsAnUnsavedDraftToTheNoticesAndDropsIt() async throws {
        let bench = try HostBench()
        let source = FakeInstanceConfig([.name: .text("Library")])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.test", source: source) }
        await settings.load()
        let (adapter, libraries, _) = try await connected(bench, settings: settings)
        settings.draft[.name] = "Renamed"
        adapter.handOverDrafts()
        let notice = try #require(libraries.host.notices.waiting.last)
        #expect(notice.isNotKept)
        #expect(notice.text == "Name: Renamed")
        #expect(!settings.hasEdits)
        adapter.handOverDrafts()
        #expect(libraries.host.notices.waiting.count == 1, "a second close has nothing more to hand over")
    }

    @Test func aWriteTheServerRefusesKeepsWhatWasTypedWithItsReason() async throws {
        let source = FakeInstanceConfig([.name: .text("Library")])
        source.updateFailure.withLock { $0 = .refused("That name is taken.") }
        let settings = InstanceSettingsModel { .init(id: "https://marfa.test", source: source) }
        await settings.load()
        settings.draft[.name] = "Taken"
        await settings.save()
        #expect(settings.draft[.name] == "Taken")
        #expect(settings.failure == .refused("That name is taken."))
        #expect(settings.isEdited(.name))
    }
}
