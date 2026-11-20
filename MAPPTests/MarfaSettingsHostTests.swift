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

    @Test func signingInAgainWithACodeKeepsWhatWasAllowedBefore() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(browser: [.success("again")])
        _ = await adapter.allowMore([.backupsManage])
        bench.signIns.script(codeKey: "by-code")
        await libraries.marfaSettings.start(.signInAgain(usingCode: true)).value
        #expect(bench.signIns.calls.last == "code http://first.test:8210")
        #expect(bench.signIns.asked.last?.contains(.backupsManage) == true, "the code asks for what the browser asks for")
        #expect(adapter.grants == SystemSignIns.askedAtSignIn.union([.backupsManage]))
        #expect(try bench.signIns.key(for: first.address) == "by-code")
        #expect(libraries.host.notices.waiting.filter { $0.title == Words.permissionsLostTitle }.isEmpty)
    }

    @Test func anApprovalThatDropsAPermissionHeldIsToldAndTheNeedingPageAsksAgain() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(browser: [.success("again")])
        #expect(await adapter.allowMore([.backupsManage]) == .allowed)
        // The owner unticks Backups on the approval page of a later sign-in.
        bench.signIns.script(approving: [SystemSignIns.askedAtSignIn])
        bench.signIns.script(browser: [.success("narrower")])
        await libraries.marfaSettings.start(.signInAgain(usingCode: false)).value
        let notice = try #require(libraries.host.notices.waiting.first { $0.title == Words.permissionsLostTitle })
        #expect(notice.message == "MAPP is no longer allowed to list, make and restore backups. Allow it again from the page that needs it.")
        #expect(!adapter.grants.contains(.backupsManage))
        #expect(adapter.connection == .connected, "the page that asked is gated again by its missing permission")
    }

    @Test func anAllowMoreApprovedWithFewerThanHeldNamesEveryPermissionLost() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(approving: [[.itemsPurge]])
        bench.signIns.script(browser: [.success("narrower")])
        #expect(await adapter.allowMore([.backupsManage]) == .approvedFewer)
        let notice = try #require(libraries.host.notices.waiting.first { $0.title == Words.permissionsLostTitle })
        #expect(notice.message.contains("see and change this Marfa’s settings"))
        #expect(notice.message.contains("choose a type’s icon and change a type’s fields"))
        #expect(!notice.message.contains("permanently delete"), "what is still held is not named")
        #expect(adapter.grants == [.itemsPurge])
    }

    @Test func anApprovalOfFewerThanAskedThatKeepsEverythingHeldTellsNothing() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(approving: [SystemSignIns.askedAtSignIn])
        bench.signIns.script(browser: [.success("again")])
        #expect(await adapter.allowMore([.backupsManage]) == .approvedFewer)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn)
        #expect(libraries.host.notices.waiting.filter { $0.title == Words.permissionsLostTitle }.isEmpty)
    }

    @Test func everyPermissionAPageNeedsIsNamedTheSameWayWhereItIsLost() {
        for page in MarfaSettingsPage.allCases {
            #expect(page.permissionLine == "MAPP isn’t allowed to \(page.permission.allowedTo).")
        }
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
        // Plain http to another machine is told once a run, to whichever test connects first; it is not a handover.
        let before = libraries.host.notices.waiting.count
        adapter.handOverDrafts()
        let notice = try #require(libraries.host.notices.waiting.last)
        #expect(notice.isNotKept)
        #expect(notice.text == "Name: Renamed")
        #expect(!settings.hasEdits)
        #expect(libraries.host.notices.waiting.count == before + 1, "the draft is handed over once")
        adapter.handOverDrafts()
        #expect(libraries.host.notices.waiting.count == before + 1, "a second close has nothing more to hand over")
    }

    @Test func quittingHandsAnUnsavedDraftToTheNoticesAndTheClipboard() async throws {
        let bench = try HostBench()
        let source = FakeInstanceConfig([.name: .text("Library")])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.test", source: source) }
        await settings.load()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) }, instanceSettings: settings)
        let model = libraries.instanceSettings
        model.draft[.name] = "Renamed on quit"
        let before = libraries.host.notices.waiting.count
        libraries.handOffDraftsAtQuit()
        let notice = try #require(libraries.host.notices.waiting.last)
        #expect(notice.isNotKept)
        #expect(notice.text == "Name: Renamed on quit")
        #expect(notice.message.contains("quit MAPP"))
        #expect(!model.hasEdits)
        #expect(libraries.host.notices.waiting.count == before + 1)
        let copied = Mutex<[String]>([])
        let quits = libraries.host.notices.tellBeforeQuitting(copying: { text in copied.withLock { $0.append(text) } }) { _ in }
        #expect(quits)
        #expect(copied.withLock { $0 } == ["Name: Renamed on quit"], "the text reaches the clipboard before the app goes")
        libraries.handOffDraftsAtQuit()
        #expect(libraries.host.notices.waiting.filter(\.isNotKept).isEmpty, "a draft already handed over is not handed over again")
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
