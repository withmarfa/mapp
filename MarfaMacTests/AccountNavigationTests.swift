import Marfa
import Synchronization
import Testing

@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct AccountNavigationTests {
    @Test func signInRowsRequirePermissionWhileAccountRemainsAvailable() {
        #expect(MarfaSettingsPage.account.permission == nil)
        for page in [MarfaSettingsPage.passkeys, .browsers] {
            #expect(page.permission == .signInsManage)
            #expect(page.sidebarEntry == .account)
        }
        #expect(MarfaSettingsPage.network.permission == .configManage)
    }

    @Test func emptySignInListsOnlyReadTheRequestedList() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.passkeys = []
            $0.browsers = []
        }
        for passkeys in [true, false] {
            let model = AccountModel(context: bench.context)
            await model.loadSignIns(passkeysOnly: passkeys)
            #expect(model.hasLoaded && model.failure == nil)
            #expect(model.passkeys.isEmpty && model.browsers.isEmpty)
        }
        #expect(!bench.calls.calls.contains("profile"))
    }

    @Test func aCheckThatDidNotAnswerOpensThePageForThatCheck() {
        #expect(AttentionConcern(kind: .unavailable, reference: "API keys", title: "").repair == .page(.keys))
        #expect(AttentionConcern(kind: .unavailable, reference: "Webhooks", title: "").repair == .page(.webhooks))
        #expect(AttentionConcern(kind: .webhook, reference: "hook-id", title: "").repair == .page(.webhooks))
    }

    @Test func anUnreadableObjectStoreKeyGivesTheCommandInsteadOfOpeningStorage() {
        let concern = AttentionConcern(kind: .setting, reference: "object_store_secret_access_key", title: "")
        #expect(concern.repair == .command("marfa config set object_store_secret_access_key"))
        #expect(concern.shownLine?.contains("marfa config set object_store_secret_access_key") == true)
    }

    @Test func problemsUseTheirSettingsDestinationAndCount() async {
        let bench = OwnerBench()
        let model = AccountOverview(context: bench.context)
        bench.calls.state.withLock { $0.concerns = [] }
        await model.load()
        #expect(model.attentionBadge == nil)
        bench.calls.state.withLock {
            $0.concerns = [
                .init(kind: .key, reference: "key", title: "Key expires"),
                .init(kind: .connector, reference: "rss", title: "RSS has gone quiet"),
                .init(kind: .clock, reference: "clock_ahead", title: "Clock changed"),
            ]
        }
        await model.load()
        #expect(model.attentionBadge == 3)
        #expect(model.concerns.map(\.repair) == [.page(.keys), .page(.connectors), .page(.housekeeping)])
    }
}
