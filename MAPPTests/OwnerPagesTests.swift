import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// What the owner's pages ask of the server, held in memory: it answers as the server does, keeps what it was sent and fails
/// a named call on request.
nonisolated final class FakeOwnerCalls: OwnerCalls {
    struct State {
        var profile = OwnerProfile(username: "mira", emailIsReadable: true, email: nil)
        var passkeys: [OwnerPasskey] = []
        var browsers: [BrowserSignIn] = []
        var password = "old password"
        var apps: [AppAccess] = []
        var names: [String: String] = [:]
        var keys: [KeyInfo] = []
        var settings = AddressSettings(
            instanceID: "instance-1", signIn: "https://marfa.test", addresses: ["https://marfa.test", "https://100.84.12.7"], websites: [])
        var reach = AddressPlan.Reach.notAsked
        var consequences: [AddressPlan.Consequence] = []
        var requiresConfirmation = false
        /// A call by name that fails, until cleared.
        var failures: [String: OwnerFailure] = [:]
        var calls: [String] = []
        var narrowed: [(app: AppAccess, scopes: [String])] = []
        var created: [NewKey] = []
        var changes: [(id: String, change: KeyChange)] = []
        var applied: [AddressPlan] = []
        var websitesSent: [[String]] = []
    }

    let state = Mutex(State())

    func fail(_ call: String, with failure: OwnerFailure?) { state.withLock { $0.failures[call] = failure } }
    var calls: [String] { state.withLock { $0.calls } }

    private func enter(_ call: String) throws(OwnerFailure) {
        let failure = state.withLock { state in
            state.calls.append(call)
            return state.failures[call]
        }
        if let failure { throw failure }
    }

    func profile() async throws(OwnerFailure) -> OwnerProfile {
        try enter("profile")
        return state.withLock { $0.profile }
    }

    func passkeys() async throws(OwnerFailure) -> [OwnerPasskey] {
        try enter("passkeys")
        return state.withLock { $0.passkeys }
    }

    func renamePasskey(_ id: String, to name: String) async throws(OwnerFailure) {
        try enter("renamePasskey")
        state.withLock { state in
            if let index = state.passkeys.firstIndex(where: { $0.id == id }) { state.passkeys[index].name = name }
        }
    }

    func removePasskey(_ id: String) async throws(OwnerFailure) {
        try enter("removePasskey")
        state.withLock { $0.passkeys.removeAll { $0.id == id } }
    }

    func passkeyAddAddress() async throws(OwnerFailure) -> URL {
        try enter("passkeyAddAddress")
        return URL(string: "https://marfa.test/passkeys/add")!
    }

    func browserSignIns() async throws(OwnerFailure) -> [BrowserSignIn] {
        try enter("browserSignIns")
        return state.withLock { $0.browsers }
    }

    func endSignIn(_ id: String) async throws(OwnerFailure) {
        try enter("endSignIn")
        state.withLock { $0.browsers.removeAll { $0.id == id } }
    }

    func changePassword(from current: String, to new: String) async throws(OwnerFailure) -> PasswordOutcome {
        try enter("changePassword")
        return state.withLock { state in
            guard current == state.password else { return .currentWrong }
            guard (8...128).contains(new.count) else { return .newRefused("The password must be 8 to 128 characters.") }
            state.password = new
            state.browsers = []
            return .changed
        }
    }

    func typeNames() async throws(OwnerFailure) -> [String: String] {
        try enter("typeNames")
        return state.withLock { $0.names }
    }

    func apps() async throws(OwnerFailure) -> [AppAccess] {
        try enter("apps")
        return state.withLock { $0.apps }
    }

    func narrow(_ app: AppAccess, to scopes: [String]) async throws(OwnerFailure) {
        try enter("narrow")
        try state.withLock { state throws(OwnerFailure) in
            guard let index = state.apps.firstIndex(where: { $0.id == app.id }) else { throw .notFound }
            guard state.apps[index].scopes == app.scopes else { throw .conflict }
            state.narrowed.append((app, scopes))
            state.apps[index].scopes = scopes
        }
    }

    func disconnect(_ app: AppAccess) async throws(OwnerFailure) {
        try enter("disconnect")
        state.withLock { $0.apps.removeAll { $0.id == app.id } }
    }

    func keys() async throws(OwnerFailure) -> [KeyInfo] {
        try enter("keys")
        return state.withLock { $0.keys }
    }

    func create(_ key: NewKey) async throws(OwnerFailure) -> CreatedKey {
        try enter("create")
        return state.withLock { state in
            state.created.append(key)
            let id = "key-\(state.keys.count + 1)"
            state.keys.append(
                KeyInfo(
                    id: id, label: key.label, source: key.source, permissions: key.permissions, tier: key.tier, types: key.types,
                    created: .now, expires: key.expires, lastUsed: nil, appClientID: nil))
            return CreatedKey(id: id, label: key.label, secret: "marfa_k1_secret")
        }
    }

    func change(_ id: String, _ change: KeyChange) async throws(OwnerFailure) -> KeyInfo {
        try enter("change")
        return try state.withLock { state throws(OwnerFailure) in
            guard let index = state.keys.firstIndex(where: { $0.id == id }) else { throw .notFound }
            state.changes.append((id, change))
            if let label = change.label { state.keys[index].label = label }
            if let tier = change.tier { state.keys[index].tier = tier }
            if let expires = change.expires { state.keys[index].expires = expires }
            if let types = change.types { state.keys[index].types = types }
            if let permissions = change.permissions { state.keys[index].permissions = permissions }
            return state.keys[index]
        }
    }

    func revoke(_ id: String) async throws(OwnerFailure) {
        try enter("revoke")
        try state.withLock { state throws(OwnerFailure) in
            guard state.keys.contains(where: { $0.id == id }) else { throw .notFound }
            state.keys.removeAll { $0.id == id }
        }
    }

    func addresses() async throws(OwnerFailure) -> AddressSettings {
        try enter("addresses")
        return state.withLock { $0.settings }
    }

    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan {
        try enter("check")
        return state.withLock { state in
            AddressPlan(
                askedSignIn: signIn, askedAddresses: addresses, signIn: signIn ?? state.settings.signIn,
                addresses: addresses ?? state.settings.addresses, requiresConfirmation: state.requiresConfirmation,
                consequences: state.consequences, reach: signIn == nil ? .notAsked : state.reach)
        }
    }

    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try enter("apply")
        return try state.withLock { state throws(OwnerFailure) in
            if let instanceID, instanceID != state.settings.instanceID { throw .conflict }
            state.applied.append(plan)
            state.settings.signIn = plan.signIn
            state.settings.addresses = plan.addresses
            return state.settings
        }
    }

    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try enter("setWebsites")
        return state.withLock { state in
            state.websitesSent.append(websites)
            state.settings.websites = websites
            return state.settings
        }
    }
}

/// What a context lends a model in a test, with the grants it holds and what Allow More… answers.
@MainActor final class OwnerBench {
    let calls = FakeOwnerCalls()
    var grants: Set<InstancePermission>
    var allowing: MarfaAllowMoreOutcome = .allowed
    var asked: [Set<InstancePermission>] = []
    var refreshed = 0

    init(grants: Set<InstancePermission> = [.signInsManage, .grantsManage, .keysManage, .keysMint, .configManage]) {
        self.grants = grants
    }

    var context: OwnerContext {
        OwnerContext(
            calls: calls, grants: { [unowned self] in grants },
            allowMore: { [unowned self] permissions in
                asked.append(permissions)
                if allowing == .allowed { grants.formUnion(permissions) }
                return allowing
            },
            refreshGrants: { [unowned self] in refreshed += 1 })
    }
}

@MainActor
@Suite(.hangLimit) struct AccountModelTests {
    private func model(_ bench: OwnerBench) -> AccountModel { AccountModel(context: bench.context) }

    @Test func theProfileIsShownAsTheServerHoldsIt() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        #expect(account.profile == OwnerProfile(username: "mira", emailIsReadable: true, email: nil))
        #expect(account.failure == nil)
    }

    @Test func aWrongCurrentPasswordKeepsWhatWasTypedWithOneLine() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        account.currentPassword = "not the password"
        account.newPassword = "a new password"
        await account.changePassword()
        #expect(account.currentPasswordError == "That isn’t your current password.")
        #expect(account.currentPassword == "not the password")
        #expect(account.newPassword == "a new password")
        #expect(account.sheet == .password)
        #expect(!account.passwordChanged)
    }

    @Test func aNewPasswordTheServerRefusesKeepsWhatWasTypedWithItsReason() async {
        let bench = OwnerBench()
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        account.currentPassword = "old password"
        account.newPassword = String(repeating: "x", count: 129)
        #expect(!account.isNewPasswordLongEnough)
        #expect(!account.canChangePassword, "a password outside 8 to 128 characters is never sent")
        account.newPassword = "short"
        #expect(!account.canChangePassword)
        #expect(!bench.calls.calls.contains("changePassword"))
    }

    @Test func aChangedPasswordEndsTheBrowsersAndIsNeverKept() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari on macOS")] }
        let account = model(bench)
        await account.load()
        #expect(account.browsers.count == 1)
        await account.beginChangePassword()
        account.currentPassword = "old password"
        account.newPassword = "a new password"
        await account.changePassword()
        #expect(account.passwordChanged)
        #expect(account.currentPassword.isEmpty && account.newPassword.isEmpty)
        #expect(account.browsers.isEmpty)
        account.closePasswordSheet()
        #expect(account.sheet == nil)
        #expect(!account.passwordChanged)
    }

    @Test func signInsManageIsAskedForFromChangePasswordAndThenTheSheetOpens() async {
        let bench = OwnerBench(grants: [])
        let account = model(bench)
        await account.load()
        #expect(bench.calls.calls == ["profile"], "the sign-ins are not read without the permission")
        #expect(!account.canManageSignIns)
        await account.beginChangePassword()
        #expect(bench.asked == [[.signInsManage]])
        #expect(account.sheet == .password)
        #expect(bench.calls.calls.contains("passkeys"), "the lists are read once it is held")
    }

    @Test func allowMoreCancelledOpensNothingAndChangesNothing() async {
        let bench = OwnerBench(grants: [])
        bench.allowing = .cancelled
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        #expect(account.sheet == nil)
        #expect(account.note == nil)
        #expect(!account.canManageSignIns)
    }

    @Test func anApprovalWithoutThePermissionSaysSo() async {
        let bench = OwnerBench(grants: [])
        bench.allowing = .approvedFewer
        let account = model(bench)
        await account.load()
        await account.beginChangePassword()
        #expect(account.sheet == nil)
        #expect(account.note?.contains("manage the owner’s sign-ins and passkeys") == true)
    }

    @Test func aWriteTheServerRefusesForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari")] }
        let account = model(bench)
        await account.load()
        bench.calls.fail("endSignIn", with: .notPermitted("sign_ins.manage"))
        await account.end(account.browsers[0])
        #expect(account.rowErrors["b"]?.contains("manage the owner’s sign-ins and passkeys") == true)
        #expect(account.browsers.count == 1)
        #expect(bench.refreshed == 1, "the grants held can be stale, so they are read again")
    }

    @Test func aPasskeyIsRenamedAndRemoved() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "MacBook Pro")] }
        let account = model(bench)
        await account.load()
        account.beginRename(account.passkeys[0])
        account.renameDraft = "Studio Mac"
        await account.rename()
        #expect(account.passkeys[0].name == "Studio Mac")
        #expect(account.sheet == nil)
        await account.remove(account.passkeys[0])
        #expect(account.passkeys.isEmpty)
    }

    @Test func aRefusedRenameKeepsTheTypedName() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.passkeys = [OwnerPasskey(id: "p", name: "MacBook Pro")] }
        let account = model(bench)
        await account.load()
        account.beginRename(account.passkeys[0])
        account.renameDraft = "Studio Mac"
        bench.calls.fail("renamePasskey", with: .refused("Use a shorter name."))
        await account.rename()
        #expect(account.renameDraft == "Studio Mac")
        #expect(account.renameError == "Use a shorter name.")
        #expect(account.sheet == .renamePasskey("p"))
    }

    @Test func aSignInThatWasEndedElsewhereLeavesTheList() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.browsers = [BrowserSignIn(id: "b", name: "Safari")] }
        let account = model(bench)
        await account.load()
        bench.calls.fail("endSignIn", with: .notFound)
        await account.end(account.browsers[0])
        #expect(account.browsers.isEmpty)
        #expect(account.rowErrors["b"] == nil)
    }

    @Test func aServerThatDoesNotAnswerIsTheWholePage() async {
        let bench = OwnerBench()
        bench.calls.fail("profile", with: .unreachable)
        let account = model(bench)
        await account.load()
        #expect(account.failure == .unreachable)
        #expect(account.hasLoaded)
    }

    @Test func addingAPasskeyOpensTheServersOwnAddress() async {
        let bench = OwnerBench()
        let account = model(bench)
        #expect(await account.passkeyAddress() == URL(string: "https://marfa.test/passkeys/add"))
        bench.calls.fail("passkeyAddAddress", with: .notPermitted("sign_ins.manage"))
        #expect(await account.passkeyAddress() == nil)
        #expect(account.note != nil)
    }

    @Test func theLinesUnderAPasskeySayWhenItWasAddedAndUsed() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let line = AccountPage.line(added: now.addingTimeInterval(-86_400 * 40), used: now, now: now, calendar: calendar)
        #expect(line.hasPrefix("Added "))
        #expect(line.hasSuffix("Used today."))
        #expect(AccountPage.line(added: nil, used: nil, now: now, calendar: calendar) == "Never used.")
    }
}

@MainActor
@Suite(.hangLimit) struct AppsModelTests {
    private func app(scopes: [String] = ["*:read", "*:write", "core.note:read", "keys.manage"]) -> AppAccess {
        AppAccess(id: "g1", clientID: "raycast", kind: .app, name: "Raycast", origins: [], scopes: scopes, granted: nil, lastUsed: nil)
    }

    private func bench(_ app: AppAccess) -> OwnerBench {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.apps = [app]
            $0.names = ["core.note": "Note"]
        }
        return bench
    }

    @Test func narrowingAsksFirstAndSendsTheAccessItWasReadAs() async throws {
        let read = app()
        let bench = bench(read)
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .read)
        let question = try #require(model.question)
        #expect(question.title == "Narrow Raycast’s access?")
        #expect(bench.calls.state.withLock { $0.narrowed.isEmpty }, "nothing is sent before the owner agrees")
        await model.confirm(question)
        let sent = bench.calls.state.withLock { $0.narrowed }
        #expect(sent.first?.app.scopes == read.scopes, "the version read goes with the change")
        #expect(sent.first?.scopes == ["*:read", "core.note:read", "keys.manage"])
        #expect(model.apps[0].scopes == ["*:read", "core.note:read", "keys.manage"])
    }

    @Test func aCancelledNarrowingSendsNothing() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .none)
        model.cancelQuestion()
        #expect(model.question == nil)
        #expect(!bench.calls.calls.contains("narrow"))
    }

    @Test func nothingIsAskedWhereNothingWouldChange() async {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .write)
        #expect(model.question == nil)
    }

    @Test func aChangeMadeElsewhereIsToldAndTheAccessIsReadAgain() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToNarrow(model.apps[0], pattern: "*", to: .read)
        let question = try #require(model.question)
        bench.calls.state.withLock { $0.apps[0].scopes = ["core.note:read"] }
        await model.confirm(question)
        #expect(model.rowErrors["g1"] == OwnerWording.line(.conflict))
        #expect(model.apps[0].scopes == ["core.note:read"], "what the server holds is what shows")
    }

    @Test func aPermissionIsRemovedByNarrowing() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToRemove(permission: "keys.manage", from: model.apps[0])
        await model.confirm(try #require(model.question))
        #expect(model.apps[0].scopes == ["*:read", "*:write", "core.note:read"])
    }

    @Test func disconnectingAsksFirstAndSaysItsKeysStay() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(model.apps[0])
        let question = try #require(model.question)
        #expect(question.message.contains("The keys it made keep working."))
        #expect(question.message.contains("Its webhooks are deleted."))
        #expect(!bench.calls.calls.contains("disconnect"))
        await model.confirm(question)
        #expect(model.apps.isEmpty)
        #expect(model.disconnected == "g1")
    }

    @Test func aRefusalForWantOfAPermissionNamesItAndReadsTheGrantsAgain() async throws {
        let bench = bench(app())
        let model = AppsModel(context: bench.context)
        await model.load()
        model.askToDisconnect(model.apps[0])
        bench.calls.fail("disconnect", with: .notPermitted("grants.manage"))
        await model.confirm(try #require(model.question))
        #expect(model.rowErrors["g1"]?.contains("list, narrow and revoke other apps’ access") == true)
        #expect(bench.refreshed == 1)
        #expect(model.apps.count == 1)
    }

    @Test func theKeysAnAppMadeAreListedOnlyWhereKeysCanBeListed() async {
        let bench = bench(app())
        bench.calls.state.withLock {
            $0.keys = [KeyInfo(id: "k", label: "Raycast capture", source: "raycast", permissions: [], tier: .feed, types: [:], appClientID: "raycast")]
        }
        let model = AppsModel(context: bench.context)
        await model.load()
        #expect(model.keysMade["raycast"]?.map(\.label) == ["Raycast capture"])
        bench.grants = [.grantsManage]
        await model.load()
        #expect(model.keysMade.isEmpty)
    }

    @Test func scopesAreNarrowedAndNeverWidened() {
        let scopes = ["*:read", "*:write", "core.note:read", "keys.manage"]
        #expect(AccessScopes.narrowed(scopes, pattern: "*", to: .read) == ["*:read", "core.note:read", "keys.manage"])
        #expect(AccessScopes.narrowed(scopes, pattern: "*", to: .none) == ["core.note:read", "keys.manage"])
        #expect(AccessScopes.narrowed(scopes, pattern: "core.note", to: .write) == scopes, "a read is never made a write")
        let parsed = AccessScopes.parse(scopes)
        #expect(parsed.entries.map(\.pattern) == ["*", "core.note"])
        #expect(parsed.entries.map(\.level) == [.write, .read])
        #expect(parsed.permissions == ["keys.manage"])
    }

    @Test func aPatternIsNamedByTheTypeOrByWhatItReaches() {
        let names = ["core.note": "Note"]
        #expect(AccessScopes.title(of: "core.note", names: names) == "Note")
        #expect(AccessScopes.title(of: "*", names: names) == "All Data")
        #expect(AccessScopes.title(of: "core.*", names: names) == "Core Types")
        #expect(AccessScopes.title(of: "edge.*", names: names) == "All Links")
        #expect(AccessScopes.title(of: "app.mine", names: names) == "app.mine")
    }
}

@MainActor
@Suite(.hangLimit) struct KeysModelTests {
    private func key(_ id: String = "k1", expires: Date? = nil, types: [String: AccessLevel] = ["*": .write, "core.note": .read]) -> KeyInfo {
        KeyInfo(id: id, label: "Importer", source: "importer", permissions: ["items.purge"], tier: .feed, types: types, expires: expires, appClientID: nil)
    }

    private func bench(_ keys: [KeyInfo]) -> OwnerBench {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.keys = keys }
        return bench
    }

    @Test func keysAreSplitIntoTheOwnersAndTheAppsAndNewKeyNeedsKeysMint() async {
        let bench = bench([key(), KeyInfo(id: "a", label: "App key", source: "app", permissions: [], tier: .feed, types: [:], appClientID: "raycast")])
        let model = KeysModel(context: bench.context)
        await model.load()
        #expect(model.ownersKeys.map(\.id) == ["k1"])
        #expect(model.appKeys.map(\.id) == ["a"])
        #expect(model.canMake)
        bench.grants.remove(.keysMint)
        #expect(!model.canMake, "listing and revoking are keys.manage, and making a key is a different permission")
    }

    @Test func aRefusedNewKeyKeepsTheSheetsInput() async {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        model.draft.exceptions["core.note"] = .write
        bench.calls.fail("create", with: .refused("That source is taken by another key."))
        await model.make()
        #expect(model.draftError == "That source is taken by another key.")
        #expect(model.draft.name == "Lisbon zine importer")
        #expect(model.draft.exceptions == ["core.note": .write])
        #expect(model.sheet == .new)
        #expect(model.created == nil)
    }

    @Test func aMadeKeyIsShownOnceAndDroppedWhenTheSheetCloses() async throws {
        let bench = bench([])
        let model = KeysModel(context: bench.context)
        model.beginNewKey()
        model.draft.name = "Lisbon zine importer"
        model.draft.source = "lisbon-zine"
        model.draft.permissions = ["items.purge"]
        await model.make()
        #expect(model.sheet == .shown)
        #expect(model.created?.secret == "marfa_k1_secret")
        let sent = try #require(bench.calls.state.withLock { $0.created.first })
        #expect(sent.types == ["*": .read])
        #expect(sent.permissions == ["items.purge"])
        #expect(sent.expires != nil, "a new key expires in 90 days unless the owner says otherwise")
        #expect(model.keys.map(\.label) == ["Lisbon zine importer"])
        model.closeSheet()
        #expect(model.created == nil)
        #expect(model.sheet == nil)
    }

    @Test func theSourceFollowsTheNameUntilItIsChanged() {
        #expect(KeysModel.source(from: "Lisbon zine importer!") == "lisbon-zine-importer")
        #expect(KeysModel.source(from: "  ") == "")
    }

    @Test func aKeyIsOnlyNarrowed() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        await model.narrow(model.keys[0], pattern: "core.note", to: .write)
        #expect(bench.calls.state.withLock { $0.changes.isEmpty }, "a wider level is never sent")
        await model.narrow(model.keys[0], pattern: "*", to: .read)
        let sent = bench.calls.state.withLock { $0.changes }
        #expect(sent.first?.change.types == ["*": .read, "core.note": .read])
    }

    @Test func aKeyIsMadeToExpireSoonerAfterAskingAndNeverLater() async throws {
        let ends = Date.now.addingTimeInterval(86_400 * 30)
        let bench = bench([key(expires: ends)])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToExpire(model.keys[0], on: ends.addingTimeInterval(86_400))
        #expect(model.question == nil, "a later date is not offered")
        let sooner = ends.addingTimeInterval(-86_400 * 10)
        model.askToExpire(model.keys[0], on: sooner)
        let question = try #require(model.question)
        #expect(!bench.calls.calls.contains("change"))
        await model.confirm(question)
        #expect(model.keys[0].expires == sooner)
    }

    @Test func revokingAsksFirstAndGoesBack() async throws {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        model.askToRevoke(model.keys[0])
        let question = try #require(model.question)
        #expect(!bench.calls.calls.contains("revoke"))
        await model.confirm(question)
        #expect(model.keys.isEmpty)
        #expect(model.revoked == "k1")
    }

    @Test func aKeyRevokedElsewhereWhileItsPageIsOpenIsToldGone() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        bench.calls.state.withLock { $0.keys = [] }
        await model.setTier(.library, of: model.keys[0])
        #expect(model.key("k1") == nil)
        #expect(model.isGone("k1"))
        await model.load()
        #expect(model.key("k1") == nil)
    }

    @Test func aRefusedChangeNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = bench([key()])
        let model = KeysModel(context: bench.context)
        await model.load()
        bench.calls.fail("change", with: .notPermitted("keys.manage"))
        await model.setTier(.library, of: model.keys[0])
        #expect(model.rowErrors["k1"]?.contains("list and revoke keys") == true)
        #expect(bench.refreshed == 1)
        #expect(model.keys[0].tier == .feed)
    }

    @Test func aNewKeyOffersOnlyThePermissionsMAPPHolds() {
        let bench = OwnerBench(grants: [.keysMint, .keysManage, .itemsPurge])
        #expect(KeysModel(context: bench.context).givablePermissions == ["items.purge", "keys.manage", "keys.mint"])
    }
}

@MainActor
@Suite(.hangLimit) struct AddressesModelTests {
    private func model(_ bench: OwnerBench = OwnerBench()) async -> (AddressesModel, OwnerBench) {
        let model = AddressesModel(context: bench.context)
        await model.load()
        return (model, bench)
    }

    @Test func anAddressIsAnOriginWithNoPath() {
        #expect(AddressesModel.origin(from: "Studio.Castell.design") == "https://studio.castell.design")
        #expect(AddressesModel.origin(from: "http://castell-studio.local:8210/") == "http://castell-studio.local:8210")
        #expect(AddressesModel.origin(from: "https://marfa.test/path") == nil)
        #expect(AddressesModel.origin(from: "ftp://marfa.test") == nil)
        #expect(AddressesModel.origin(from: "marfa test") == nil)
        #expect(AddressesModel.origin(from: "") == nil)
        #expect(AddressesModel.display("https://marfa.test") == "marfa.test")
        #expect(AddressesModel.display("http://marfa.test:8210") == "http://marfa.test:8210")
        #expect(AddressesModel.kind(of: "https://100.84.12.7") == "An IP address.")
        #expect(AddressesModel.kind(of: "http://castell-studio.local") == "On the local network.")
        #expect(AddressesModel.kind(of: "https://studio.castell.design") == nil)
    }

    @Test func theSignInAddressIsLeftOutOfTheOthers() async {
        let (model, _) = await model()
        #expect(model.signInAddress == "https://marfa.test")
        #expect(model.otherAddresses == ["https://100.84.12.7"])
    }

    @Test func anAddressIsCheckedBeforeItIsAddedAndThenAdded() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        #expect(bench.calls.calls.contains("check"))
        #expect(model.canConfirm)
        #expect(bench.calls.state.withLock { $0.applied.isEmpty }, "nothing is written by a check")
        await model.confirm()
        #expect(model.settings?.addresses == ["https://marfa.test", "https://100.84.12.7", "https://studio.castell.design"])
        #expect(model.sheet == nil)
    }

    @Test func anAddressTheCheckRefusesSaysWhyInOneLineAndKeepsTheInput() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "not an address"
        await model.check()
        #expect(model.inputError == "Use an address like https://marfa.example, with no path.")
        #expect(!model.canConfirm)
        model.input = "studio.castell.design"
        bench.calls.fail("check", with: .refused("An address can’t hold a path."))
        await model.check()
        #expect(model.inputError == "An address can’t hold a path.")
        #expect(model.input == "studio.castell.design")
        #expect(!model.canConfirm)
        await model.confirm()
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
    }

    @Test func anAddressAlreadyHeldIsToldNotChecked() async {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "https://100.84.12.7"
        await model.check()
        #expect(model.inputError == "It’s already an address.")
        #expect(!bench.calls.calls.contains("check"))
    }

    @Test func aSignInAddressThatDoesNotAnswerCannotBeChosenAndSaysWhy() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .notAnswering(reason: "not_this_instance"); $0.requiresConfirmation = true }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        #expect(model.inputError == "Something answers there, but not this Marfa.")
        #expect(!model.canConfirm)
    }

    @Test func movingTheSignInAddressShowsWhatChangesAndWritesExactlyThat() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.reach = .answers
            $0.requiresConfirmation = true
            $0.consequences = [.init(code: "browser_sessions_end", sentence: "Every browser signs in again.", count: 2)]
        }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        #expect(model.plan?.consequences.map(\.code) == ["browser_sessions_end"])
        #expect(model.canConfirm)
        await model.confirm()
        let applied = try #require(bench.calls.state.withLock { $0.applied.first })
        #expect(applied.askedSignIn == "https://studio.castell.design")
        #expect(applied.requiresConfirmation)
        #expect(model.settings?.signIn == "https://studio.castell.design")
    }

    @Test func aMoveTheOwnerDidNotConfirmKeepsTheSheetAndTheInput() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.reach = .answers; $0.requiresConfirmation = true }
        let (model, _) = await model(bench)
        model.begin(.changeSignIn)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.fail("apply", with: .notConfirmed)
        await model.confirm()
        #expect(model.inputError == "Nothing was changed: the sign-in wasn’t confirmed.")
        #expect(model.input == "studio.castell.design")
        #expect(model.sheet == .changeSignIn)
        #expect(model.settings?.signIn == "https://marfa.test")
    }

    @Test func removingAnAddressChecksThenAsksThenWrites() async throws {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.consequences = [.init(code: "address_removed", sentence: "Links that use 100.84.12.7 stop working.", count: nil)] }
        let (model, _) = await model(bench)
        await model.askToRemove(address: "https://100.84.12.7")
        let question = try #require(model.question)
        #expect(question.message == "Links that use 100.84.12.7 stop working.")
        #expect(bench.calls.state.withLock { $0.applied.isEmpty })
        await model.confirm(question)
        #expect(model.settings?.addresses == ["https://marfa.test"])
    }

    @Test func anotherInstanceAnsweringIsToldAndNothingIsWritten() async throws {
        let (model, bench) = await model()
        model.begin(.addAddress)
        model.input = "studio.castell.design"
        await model.check()
        bench.calls.state.withLock { $0.settings.instanceID = "instance-2" }
        await model.confirm()
        #expect(model.inputError == OwnerWording.line(.conflict))
        #expect(model.input == "studio.castell.design")
    }

    @Test func aWebsiteIsAddedAndRemovedAfterAsking() async throws {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        await model.confirm()
        #expect(model.settings?.websites == ["https://castell.studio"])
        model.askToRemove(website: "https://castell.studio")
        let question = try #require(model.question)
        #expect(bench.calls.state.withLock { $0.websitesSent.count } == 1)
        await model.confirm(question)
        #expect(model.settings?.websites == [])
    }

    @Test func aRefusedWebsiteKeepsTheInputWithTheServersLine() async {
        let (model, bench) = await model()
        model.begin(.addWebsite)
        model.input = "castell.studio"
        await model.check()
        bench.calls.fail("setWebsites", with: .notPermitted("config.manage"))
        await model.confirm()
        #expect(model.inputError?.contains("see and change this Marfa’s settings") == true)
        #expect(model.input == "castell.studio")
        #expect(bench.refreshed == 1)
    }
}

@MainActor
@Suite struct OwnerWordingTests {
    @Test func everyFailureSaysSomethingInOneLine() {
        let failures: [OwnerFailure] = [
            .unreachable, .signedOut, .notPermitted("grants.manage"), .notPermitted(nil), .notPermitted("odd.scope"), .notFound,
            .conflict, .notConfirmed, .refused("Because."), .failed("Broken."),
        ]
        for failure in failures { #expect(!OwnerWording.line(failure).isEmpty) }
        #expect(OwnerWording.line(.notPermitted("odd.scope")).contains("odd.scope"))
    }

    @Test func whenIsToldByDayAndNeverByTimeAlone() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(OwnerWording.used(now, now: now, calendar: calendar) == "Used today")
        #expect(OwnerWording.used(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Used yesterday")
        #expect(OwnerWording.used(now.addingTimeInterval(-86_400 * 3), now: now, calendar: calendar) == "Used 3 days ago")
        #expect(OwnerWording.used(nil, now: now, calendar: calendar) == "Never used")
    }

    @Test func theNewPagesAreInTheSidebarInTheBoardsOrder() {
        #expect(MarfaSettingsPage.groups == [[.overview], [.account, .apps, .keys, .addresses], [.recentlyDeleted]])
        for page in [MarfaSettingsPage.account, .apps, .keys, .addresses] {
            #expect(SettingsPage.marfa(page).matches(page.title))
        }
        #expect(SettingsPage.marfa(.account).matches("Passkeys"))
    }
}
