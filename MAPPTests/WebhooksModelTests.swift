import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

@MainActor
@Suite(.hangLimit) struct WebhooksModelTests {
    private static func hook(
        _ id: String, _ url: String = "https://build.castell.studio/hooks/marfa", type: String? = nil,
        events: [String] = ["item.created", "item.updated"], active: Bool = true, maker: String = "maker", makerName: String? = "MAPP"
    ) -> OwnerWebhook {
        OwnerWebhook(
            id: id, url: url, events: events, typeFilter: type, secretTail: "8f2c", active: active, created: Date(timeIntervalSince1970: 1_700_000_000),
            maker: .init(kind: .app, id: maker, name: makerName))
    }

    private static func delivery(_ id: String, _ status: WebhookDeliveryStatus, code: Int? = nil) -> WebhookDeliveryInfo {
        WebhookDeliveryInfo(id: id, event: "item.updated", status: status, statusCode: code, attempts: 1, error: nil, created: .now)
    }

    private func model(_ bench: OwnerBench, hooks: [OwnerWebhook] = []) -> WebhooksModel {
        bench.calls.state.withLock { $0.webhooks = hooks }
        return WebhooksModel(context: bench.context)
    }

    @Test func theWebhooksAreGroupedByTheirMakerSoAGroupPerAppCanJoin() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a"), Self.hook("b", maker: "other", makerName: "Raycast")])
        await model.load()
        #expect(model.groups.map(\.id) == ["maker", "other"])
        #expect(model.groups.map(\.name) == ["MAPP", "Raycast"])
    }

    @Test func aWebhookSaysItsTypeAndHowManyEventsItSends() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.names = ["core.task": "Tasks"] }
        let model = model(bench, hooks: [Self.hook("a", type: "core.task", events: ["item.created", "item.updated", "item.trashed"])])
        await model.load()
        #expect(model.summary(of: model.webhooks[0]) == "Tasks. 3 events.")
        #expect(model.typeTitle(nil) == "All Types")
    }

    @Test func aWebhookWhoseLatestDeliveryFailedIsFailingAndAnInactiveOneIsOff() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.deliveries["a"] = [Self.delivery("d2", .failed, code: 500), Self.delivery("d1", .succeeded, code: 200)]
            $0.deliveries["b"] = [Self.delivery("d3", .succeeded, code: 200)]
        }
        let model = model(bench, hooks: [Self.hook("a"), Self.hook("b"), Self.hook("c", active: false)])
        await model.load()
        #expect(model.isSending(model.webhooks[0]) == .failing)
        #expect(model.isSending(model.webhooks[1]) == .sending)
        #expect(model.isSending(model.webhooks[2]) == .off)
    }

    @Test func aRefusedReadNamesThePermissionAndReadsTheGrantsAgain() async {
        let bench = OwnerBench()
        bench.calls.fail("webhooks", with: .notPermitted("webhooks.manage"))
        let model = model(bench)
        await model.load()
        #expect(model.failure == .notPermitted("webhooks.manage"))
        #expect(bench.refreshed == 1)
    }

    @Test func aNewWebhookShowsItsSigningSecretOnceAndKeepsNone() async throws {
        let bench = OwnerBench()
        let model = model(bench)
        await model.load()
        model.beginNew()
        model.draft.address = "hooks.ledgerly.app/marfa"
        await model.make()
        #expect(bench.calls.state.withLock { $0.webhooksMade.map(\.url) } == ["https://hooks.ledgerly.app/marfa"])
        #expect(model.sheet == .secret)
        #expect(model.created?.secret == "whsec_3fKq8Vn2Lp7Xr1Tz9Bm4Yc6Wd0Hs5Ja")
        #expect(model.webhooks.count == 1, "the list is read again")
        #expect(model.webhooks[0].secretTail == "8f2c", "a read holds only the last four characters")
        model.closeSheet()
        #expect(model.created == nil)
        #expect(model.sheet == nil)
    }

    @Test func aRefusedNewWebhookKeepsTheSheetWithWhatWasTypedAndOneLine() async {
        let bench = OwnerBench()
        bench.calls.fail("createWebhook", with: .refused("That address isn’t public."))
        let model = model(bench)
        await model.load()
        model.beginNew()
        model.draft.address = "http://10.0.0.5/hook"
        model.draft.events = ["item.created", "edge.created"]
        await model.make()
        #expect(model.draftError == "That address isn’t public.")
        #expect(model.sheet == .new)
        #expect(model.draft.address == "http://10.0.0.5/hook")
        #expect(model.draft.events == ["item.created", "edge.created"])
        #expect(model.created == nil)
    }

    @Test func aWebhookWithNoAddressOrNoEventIsNotSent() async {
        let bench = OwnerBench()
        let model = model(bench)
        model.beginNew()
        #expect(!model.canMakeDraft)
        model.draft.address = "https://x.example/hook"
        #expect(model.canMakeDraft)
        model.draft.events = []
        #expect(!model.canMakeDraft)
        await model.make()
        #expect(!bench.calls.calls.contains("createWebhook"))
    }

    @Test func closingSettingsWhileTheSecretShowsTellsWhichWebhookWasMadeAndHandsOverNoSecret() async throws {
        let bench = OwnerBench()
        let model = model(bench)
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        await model.make()
        let drafts = model.takeDrafts()
        #expect(drafts.count == 1)
        guard case .told(let title, let message) = try #require(drafts.first) else {
            Issue.record("a secret is told about, never handed back")
            return
        }
        #expect(title == "Signing Secret Not Copied")
        #expect(message.contains("hooks.ledgerly.app/marfa"))
        #expect(!message.contains("whsec_"))
        #expect(model.created == nil)
        #expect(model.sheet == nil)
    }

    @Test func closingSettingsWhileTypingHandsTheAddressBack() async {
        let bench = OwnerBench()
        let model = model(bench)
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        #expect(model.takeDrafts() == [.typed(title: "Webhook Not Made", text: "Address: https://hooks.ledgerly.app/marfa")])
        #expect(model.takeDrafts().isEmpty, "a draft is handed over once")
    }

    @Test func aWebhookStillBeingMadeWhenSettingsClosesIsToldAboutWhenTheCallEnds() async throws {
        let bench = OwnerBench()
        let gate = bench.calls.hold("createWebhook")
        let model = model(bench)
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        let making = Task { await model.make() }
        #expect(try await eventuallyAsking { bench.calls.calls.contains("createWebhook") })
        #expect(model.takeDrafts().isEmpty)
        gate.open()
        await making.value
        #expect(bench.late.count == 1)
        if case .told(_, let message)? = bench.late.first { #expect(!message.contains("whsec_")) } else { Issue.record("told") }
        #expect(model.sheet == nil)
        #expect(model.created == nil)
    }

    @Test func turningAnEventOnOrOffSendsEveryEventAndKeepsOnesThisBuildDoesNotKnow() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", events: ["item.created", "item.future"])])
        await model.load()
        await model.setEvent(.itemTrashed, on: true, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.created", "item.trashed", "item.future"])
        await model.setEvent(.itemCreated, on: false, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.trashed", "item.future"])
        #expect(model.webhooks[0].maker?.id == "maker", "a change keeps the maker the server's answer leaves out")
    }

    @Test func allEventsTurnsEveryEventOnOrLeavesOnlyUnknownOnes() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", events: ["item.created", "item.future"])])
        await model.load()
        await model.setAllEvents(on: true, for: model.webhooks[0])
        #expect(Set(model.webhooks[0].events) == Set(WebhookEvent.allCases.map(\.rawValue) + ["item.future"]))
        await model.setAllEvents(on: false, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.future"])
    }

    @Test func theLastEventTheServerWillNotLetGoKeepsTheOldEventsAndSaysWhy() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", events: ["item.created"])])
        await model.load()
        bench.calls.fail("changeWebhook", with: .refused("A webhook needs at least one event."))
        await model.setEvent(.itemCreated, on: false, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.created"])
        #expect(model.rowErrors["a"] == "A webhook needs at least one event.")
    }

    @Test func allTypesSendsAnExplicitNullAndATypeSendsThatType() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", type: "core.task")])
        await model.load()
        await model.setType(nil, for: model.webhooks[0])
        #expect(bench.calls.state.withLock { $0.webhookChanges.last?.change.typeFilter } == .some(nil))
        #expect(model.webhooks[0].typeFilter == nil)
        await model.setType("core.note", for: model.webhooks[0])
        #expect(model.webhooks[0].typeFilter == "core.note")
    }

    @Test func turningSendingOffAsksFirstAndNamesWhatItDrops() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        model.askToTurnOff(model.webhooks[0])
        let question = try #require(model.question)
        #expect(question.message.contains("waiting"))
        #expect(bench.calls.state.withLock { $0.webhookChanges.isEmpty }, "nothing is sent before the owner agrees")
        model.cancelQuestion()
        #expect(model.webhooks[0].active)
        model.askToTurnOff(model.webhooks[0])
        await model.confirm(try #require(model.question))
        #expect(!model.webhooks[0].active)
        await model.turnOn(model.webhooks[0])
        #expect(model.webhooks[0].active)
    }

    @Test func deletingAsksFirstThenRemovesAndTellsThePageToGoBack() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        model.askToDelete(model.webhooks[0])
        #expect(try #require(model.question).message.contains("can’t be undone"))
        #expect(!bench.calls.calls.contains("deleteWebhook"))
        await model.confirm(try #require(model.question))
        #expect(model.webhooks.isEmpty)
        #expect(model.deleted == "a")
    }

    @Test func aWebhookDeletedElsewhereIsToldAsGoneNotAsAnError() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        bench.calls.state.withLock { $0.webhooks = [] }
        await model.setEvent(.itemTrashed, on: true, for: model.webhooks[0])
        #expect(model.isGone("a"))
        #expect(model.webhook("a") == nil)
        #expect(model.rowErrors["a"] == OwnerWording.line(.notFound))
    }

    @Test func aDeleteTheServerRefusesKeepsTheWebhookWithOneLine() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        bench.calls.fail("deleteWebhook", with: .notPermitted("webhooks.manage"))
        model.askToDelete(model.webhooks[0])
        await model.confirm(try #require(model.question))
        #expect(model.webhooks.count == 1)
        #expect(model.deleted == nil)
        #expect(model.rowErrors["a"] == OwnerWording.permissionLine("webhooks.manage"))
        #expect(bench.refreshed == 1)
    }

    @Test func aChangedAddressKeepsWhatWasTypedWhenTheServerRefusesIt() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        model.beginChangeAddress(model.webhooks[0])
        #expect(!model.canSaveAddress, "the address as it is isn’t a change")
        model.addressDraft = "http://127.0.0.1/hook"
        bench.calls.fail("changeWebhook", with: .refused("That address isn’t public."))
        await model.saveAddress()
        #expect(model.addressError == "That address isn’t public.")
        #expect(model.addressDraft == "http://127.0.0.1/hook")
        #expect(model.sheet == .address("a"))
        bench.calls.fail("changeWebhook", with: nil)
        model.addressDraft = "hooks.example.app/new"
        await model.saveAddress()
        #expect(model.webhooks[0].url == "https://hooks.example.app/new")
        #expect(model.sheet == nil)
    }

    @Test func aFailedDeliveryIsSentAgainAndOtherDeliveriesAreRefusedWithOneLine() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.deliveries["a"] = [Self.delivery("d2", .succeeded, code: 200), Self.delivery("d1", .failed, code: 500)]
        }
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        await model.loadDeliveries(of: "a")
        await model.redeliver(model.deliveries["a"]![0], of: model.webhooks[0])
        #expect(model.deliveryErrors["a"] == "Only a failed delivery can be sent again.")
        await model.redeliver(model.deliveries["a"]![1], of: model.webhooks[0])
        #expect(model.deliveryErrors["a"] == nil)
        #expect(model.deliveries["a"]?[1].status == .pending)
    }

    @Test func aRedeliveryThatFailsAgainKeepsTheDeliveryAndSaysSo() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.deliveries["a"] = [Self.delivery("d1", .failed, code: 500)] }
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        await model.loadDeliveries(of: "a")
        bench.calls.fail("redeliver", with: .unreachable)
        await model.redeliver(model.deliveries["a"]![0], of: model.webhooks[0])
        #expect(model.deliveryErrors["a"] == OwnerWording.line(.unreachable))
        #expect(model.deliveries["a"]?[0].status == .failed)
    }

    @Test func theServerNotAnsweringShowsTheFailureNotAnEmptyList() async {
        let bench = OwnerBench()
        bench.calls.fail("webhooks", with: .unreachable)
        let model = model(bench)
        await model.load()
        #expect(model.failure == .unreachable)
        #expect(model.hasLoaded)
    }

    @Test func aSignInAtTheWebhookCapCannotMakeAnother() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: (0..<WebhooksModel.cap).map { Self.hook("h\($0)") })
        await model.load()
        #expect(model.atCap)
    }

    @Test func anAddressWithNoSchemeGetsHttpsAndOneWithASchemeIsLeftAlone() {
        #expect(WebhooksModel.normalized(" hooks.example.app/x ") == "https://hooks.example.app/x")
        #expect(WebhooksModel.normalized("http://hooks.example.app/x") == "http://hooks.example.app/x")
        #expect(WebhooksModel.display("https://hooks.example.app/x") == "hooks.example.app/x")
    }
}
