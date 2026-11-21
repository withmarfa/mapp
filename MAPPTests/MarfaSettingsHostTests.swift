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
        #expect(adapter.grants.contains(.configManage))
        #expect(!adapter.grants.contains(.backupsManage))
    }

    /// `GET /profile` answers a field only to a credential holding its profile read scope, so Signed In As needs it at
    /// sign-in. It is a scope, not an owner permission.
    @Test func aSignInAsksForTheReadOfTheOwnersNameAndItIsNoOwnerPermission() async throws {
        #expect(SystemSignIns.scopes.contains("profile.name:read"))
        #expect(SystemSignIns.profileScopes.allSatisfy { InstancePermission(rawValue: $0) == nil })
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        #expect(bench.signIns.askedScopes.last?.contains("profile.name:read") == true)
        #expect(libraries.host.readsProfile)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn, "the read of the name adds no permission")
    }

    @Test func aSignInMadeBeforeTheNameWasAskedForShowsItAfterAllowMore() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.save("old", for: first.address, profile: false)
        await libraries.host.refreshGrants()
        #expect(!libraries.host.readsProfile)
        let account = ConnectionAccount(
            state: .online, grants: adapter.grants, grantsRead: true, readsProfile: libraries.host.readsProfile, waiting: 0, serverName: "X")
        #expect(account.offersName, "Connection offers to allow it")
        bench.signIns.script(browser: [.success("again")])
        #expect(await adapter.allowMore([]) == .allowed)
        #expect(libraries.host.readsProfile)
        #expect(adapter.grants == SystemSignIns.askedAtSignIn, "what was held is kept")
    }

    @Test func signingInAgainGivesTheNameToASignInThatLackedItAndKeepsItAfter() async throws {
        let bench = try HostBench()
        let (_, libraries, _) = try await connected(bench)
        bench.signIns.save("old", for: first.address, profile: false)
        await libraries.host.refreshGrants()
        #expect(!libraries.host.readsProfile)
        await libraries.marfaSettings.start(.signInAgain(usingCode: false)).value
        #expect(libraries.host.readsProfile)
        bench.signIns.script(codeKey: "by-code")
        await libraries.marfaSettings.start(.signInAgain(usingCode: true)).value
        #expect(libraries.host.readsProfile, "a code sign-in asks for it too")
    }

    @Test func anOwnerWhoLeavesTheNameOutIsOfferedItAgainAndNothingIsTold() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        bench.signIns.script(approvingProfile: false)
        bench.signIns.script(browser: [.success("without")])
        #expect(await adapter.allowMore([]) == .allowed)
        #expect(!libraries.host.readsProfile)
        #expect(libraries.host.notices.waiting.filter { $0.title == Words.permissionsLostTitle }.isEmpty)
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

    @Test func everyPageNamesWhatMAPPMayNotDoThereInItsOwnWords() {
        let pages = MarfaSettingsPage.allCases.filter { $0.permission != nil }
        for page in pages { #expect(page.permissionLine.hasPrefix("MAPP isn’t allowed to "), "\(page)") }
        // Two pages share a line only where they share a permission; here none shares one at all.
        let lines = pages.map(\.permissionLine)
        #expect(Set(lines).count == lines.count)
        for (first, second) in pages.flatMap({ first in pages.map { (first, $0) } }) where first != second && first.permission != second.permission {
            #expect(first.permissionLine != second.permissionLine)
        }
        #expect(MarfaSettingsPage.sources.permissionLine != MarfaSettingsPage.keys.permissionLine)
    }

    @Test func aReadRefusedForThePagesOwnPermissionSaysTheSameAsItsGateAndAnotherOneSaysItsOwn() {
        #expect(OwnerWording.permissionLine("keys.manage", on: .sources) == MarfaSettingsPage.sources.permissionLine)
        #expect(OwnerWording.permissionLine(nil, on: .keys) == MarfaSettingsPage.keys.permissionLine)
        #expect(OwnerWording.permissionLine("backups.manage", on: .sources) == OwnerWording.permissionLine("backups.manage"))
        #expect(OwnerWording.permissionLine("config.manage", on: .account) == OwnerWording.permissionLine("config.manage"))
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

    @Test func closingSettingsHandsBackTheOwnerPagesDrafts() async throws {
        let bench = try HostBench()
        let (adapter, libraries, _) = try await connected(bench)
        let context = OwnerContext(calls: FakeOwnerCalls(), grants: { [.keysMint, .keysManage, .configManage] })
        let addresses = AddressesModel(context: context)
        let keys = KeysModel(context: context)
        adapter.ownerDrafts.register(addresses)
        adapter.ownerDrafts.register(keys)
        await addresses.load()
        addresses.begin(.addAddress)
        addresses.input = "studio.castell.design"
        let before = libraries.host.notices.waiting.count
        adapter.handOverDrafts()
        let notice = try #require(libraries.host.notices.waiting.dropFirst(before).first)
        #expect(notice.isNotKept)
        #expect(notice.title == "Address Not Added")
        #expect(notice.text == "studio.castell.design")
        #expect(notice.message.contains("You closed Settings before this was saved."))
        adapter.handOverDrafts()
        #expect(libraries.host.notices.waiting.count == before + 1, "a second close has nothing more to hand back")
        // A key shown once is told about, with no text to give back.
        keys.beginNewKey()
        keys.draft.name = "Importer"
        keys.draft.source = "importer"
        await keys.make()
        adapter.handOverDrafts()
        let told = try #require(libraries.host.notices.waiting.last { $0.title == "Key Not Copied" })
        #expect(told.isNotKept, "a key's notice holds the quit, as a change not kept does")
        #expect(told.text == nil)
        #expect(told.message.contains("“Importer” was made"))
    }

    @Test func quittingWithAKeysSecretShownTellsThePersonTheKeyExists() async throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let keys = KeysModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.keysMint, .keysManage] }))
        libraries.ownerDrafts.register(keys)
        keys.beginNewKey()
        keys.draft.name = "Importer"
        keys.draft.source = "importer"
        await keys.make()
        libraries.handOffDraftsAtQuit()
        #expect(libraries.host.notices.holdsQuit, "the quit waits to tell the person")
        let told = Mutex<[String]>([])
        let quits = libraries.host.notices.tellBeforeQuitting(copying: { _ in }) { notice in told.withLock { $0.append(notice.title) } }
        #expect(quits)
        #expect(told.withLock { $0 }.contains("Key Not Copied"))
        #expect(!libraries.host.notices.holdsQuit)
    }

    @Test func aKeyMadeAfterSettingsClosedTellsThePersonThroughTheSameNotice() async throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let calls = FakeOwnerCalls()
        let keys = KeysModel(
            context: OwnerContext(
                calls: calls, grants: { [.keysMint, .keysManage] }, lateDraft: { libraries.ownerDrafts.arrive($0) }))
        libraries.ownerDrafts.register(keys)
        keys.beginNewKey()
        keys.draft.name = "Importer"
        keys.draft.source = "importer"
        let gate = calls.hold("create")
        let making = Task { await keys.make() }
        #expect(try await eventuallyAsking { calls.calls.contains("create") })
        libraries.handOffDraftsAtQuit()
        #expect(libraries.host.notices.waiting.filter { $0.title == "Key Not Copied" }.isEmpty)
        gate.open()
        await making.value
        let told = try #require(libraries.host.notices.waiting.last { $0.title == "Key Not Copied" })
        #expect(told.isNotKept)
        #expect(libraries.host.notices.holdsQuit)
    }

    @Test func quittingHandsBackAPasskeyAndKeyRenameTypedAndNotSaved() async throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let calls = FakeOwnerCalls()
        calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "Phone")] }
        let context = OwnerContext(calls: calls, grants: { [.keysMint, .keysManage, .signInsManage] })
        let account = AccountModel(context: context)
        libraries.ownerDrafts.register(account)
        await account.load()
        await account.beginChangePassword()
        account.closePasswordSheet()
        account.beginRename(account.passkeys[0])
        account.renameDraft = "Work phone"
        let before = libraries.host.notices.waiting.count
        libraries.handOffDraftsAtQuit()
        let notice = try #require(libraries.host.notices.waiting.dropFirst(before).first)
        #expect(notice.title == "Passkey Not Renamed")
        #expect(notice.text == "Work phone")
        #expect(notice.message.contains("You quit MAPP before this was saved."))
    }

    @Test func quittingHandsBackTheOwnerPagesDrafts() async throws {
        let bench = try HostBench()
        let defaults = try #require(UserDefaults(suiteName: "MarfaSettingsHostTests-\(UUID().uuidString)"))
        let libraries = Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
        let keys = KeysModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.keysMint, .keysManage] }))
        libraries.ownerDrafts.register(keys)
        keys.beginNewKey()
        keys.draft.name = "Importer"
        keys.draft.source = "importer"
        let before = libraries.host.notices.waiting.count
        libraries.handOffDraftsAtQuit()
        let notice = try #require(libraries.host.notices.waiting.dropFirst(before).first)
        #expect(notice.isNotKept)
        #expect(notice.text == "Name: Importer\nSource: importer")
        #expect(notice.message.contains("You quit MAPP before this was saved."))
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
