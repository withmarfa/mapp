import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct WebhooksModelTests {
    private static func hook(
        _ id: String, _ url: String = "https://build.castell.studio/hooks/marfa", type: String? = nil,
        events: [String] = ["item.created", "item.updated"], active: Bool = true, maker: String = Self.me, makerName: String? = "Marfa for Mac"
    ) -> OwnerWebhook {
        OwnerWebhook(
            id: id, url: url, events: events, typeFilter: type, secretTail: "8f2c", active: active, created: Date(timeIntervalSince1970: 1_700_000_000),
            maker: .init(kind: maker == Self.me ? .key : .app, id: maker, name: makerName))
    }

    /// The key the tests sign in with, which its own webhooks name.
    private static let me = "k-me"

    private static func delivery(_ id: String, _ status: WebhookDeliveryStatus, code: Int? = nil) -> WebhookDeliveryInfo {
        WebhookDeliveryInfo(id: id, event: "item.updated", status: status, statusCode: code, attempts: 1, error: nil, created: .now)
    }

    private func model(_ bench: OwnerBench, hooks: [OwnerWebhook] = []) -> WebhooksModel {
        bench.calls.state.withLock {
            $0.webhooks = hooks
            $0.identity.keyID = $0.identity.keyID ?? Self.me
        }
        return WebhooksModel(context: bench.context)
    }

    private static func keyHook(_ id: String, maker: String, name: String?) -> OwnerWebhook {
        OwnerWebhook(
            id: id, url: "https://\(id).example.com/hook", events: ["item.created"], typeFilter: nil, secretTail: "1a2b", active: true,
            created: Date(timeIntervalSince1970: 1_700_000_100), maker: .init(kind: .key, id: maker, name: name))
    }

    private static func key(_ id: String, _ label: String, expires: Date? = nil) -> KeyInfo {
        KeyInfo(id: id, label: label, source: id, permissions: [], tier: .feed, types: [:], expires: expires, appClientID: nil)
    }

    /// Every maker's webhooks as the owner's key lists them: the app's own, an app's, a live key's, an expired key's and a
    /// revoked key's.
    private func everyMaker(_ bench: OwnerBench) -> WebhooksModel {
        bench.calls.state.withLock {
            $0.keys = [Self.key("k-live", "Lisbon zine importer"), Self.key("k-old", "Backup script", expires: .now.addingTimeInterval(-86_400))]
        }
        return model(
            bench,
            hooks: [
                Self.keyHook("revoked", maker: "k-gone", name: nil),
                Self.keyHook("expired", maker: "k-old", name: "Backup script"),
                Self.keyHook("live", maker: "k-live", name: "Lisbon zine importer"),
                Self.hook("raycast", maker: "raycast-client", makerName: "Raycast"),
                Self.hook("mine"),
            ])
    }

    @Test func theWebhooksAreGroupedByWhoMadeThemWithTheAppsOwnFirstAndAMakerThatIsGoneLast() async {
        let bench = OwnerBench()
        let model = everyMaker(bench)
        await model.load()
        #expect(model.seesEvery)
        #expect(model.groups.map(\.id) == ["own", "app:raycast-client", "key:k-live", "key:k-old", "key:k-gone"])
        #expect(model.groups.map { model.heading(of: $0) } == [
            "Made by Marfa for Mac", "Made by Raycast", "Made by the key Lisbon zine importer", "Made by the key Backup script (expired)",
            "Made by a revoked key",
        ])
        #expect(model.groups.map(\.isOwn) == [true, false, false, false, false])
        #expect(model.groups.map(\.standing) == [.standing, .standing, .standing, .expired, .gone])
    }

    @Test func aSignInThatIsAKeyKnowsItsOwnByTheKeysId() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.identity = OwnIdentity(keyID: "k-live", expires: nil) }
        let model = model(bench, hooks: [Self.keyHook("mine", maker: "k-live", name: "Lisbon zine importer"), Self.keyHook("theirs", maker: "k-other", name: "Other")])
        await model.load()
        #expect(model.isOwn(model.webhooks[0]) && !model.isOwn(model.webhooks[1]))
    }

    @Test func withoutManageKeysTheListIsTheAppsOwnAndNothingMoreIsAsked() async {
        let bench = OwnerBench(grants: [.webhooksManage])
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        #expect(!model.seesEvery)
        #expect(model.isOwn(model.webhooks[0]), "the server lists only what this sign-in made")
        #expect(model.groups.map(\.id) == ["own"])
        #expect(!bench.calls.calls.contains("identity") && !bench.calls.calls.contains("keys"))
    }

    @Test func whenWhoTheAppIsCantBeReadThePageShowsTheFailureNotAListOfOnlyOthersWebhooks() async {
        let bench = OwnerBench()
        bench.calls.fail("identity", with: .unreachable)
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        #expect(model.hasLoaded && model.failure == .unreachable, "Try Again reads it again")
        bench.calls.fail("identity", with: nil)
        await model.load()
        #expect(model.failure == nil && model.isOwn(model.webhooks[0]))
    }

    @Test func anotherAppWithTheAppsNameIsNotTheAppsOwnWhateverItIsCalled() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("theirs", maker: "other-client", makerName: "Marfa for Mac"), Self.hook("mine")])
        bench.calls.state.withLock { $0.identity = OwnIdentity(keyID: nil, expires: nil) }
        await model.load()
        #expect(model.webhooks.allSatisfy { !model.isOwn($0) }, "an app sign-in has no identifier to match, so none is taken as its own")
        #expect(!model.atCap)
        let theirs = model.webhooks[0]
        await model.setType("core.task", for: theirs)
        await model.turnOn(theirs)
        #expect(!bench.calls.calls.contains("changeWebhook"), "no change is sent for a webhook that might be another app's")
    }

    @Test func aWebhookOfAnotherKeyIsNotTheSignedInKeys() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.keyHook("theirs", maker: "k-other", name: "Marfa for Mac"), Self.hook("mine")])
        await model.load()
        #expect(model.webhooks.map(model.isOwn) == [false, true], "a key is told by its id, never its name")
    }

    @Test func losingManageKeysDropsEveryMakersListAndReadsOnlyTheAppsOwn() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("theirs", maker: "raycast-client", makerName: "Raycast"), Self.hook("mine")])
        await model.load()
        #expect(model.webhooks.map(model.isOwn) == [false, true])
        bench.calls.state.withLock { $0.webhooks = [$0.webhooks[1]] }
        bench.grants.remove(.keysManage)
        #expect(!model.seesEvery)
        #expect(model.webhooks.map(model.isOwn) == [false, true], "the cached list of others' webhooks is not taken as the app's own")
        await model.readAgainIfScopeChanged()
        #expect(model.webhooks.map(\.id) == ["mine"] && model.isOwn(model.webhooks[0]))
        #expect(model.groups.map(\.id) == ["own"])
    }

    @Test func anotherMakersWebhookCanNeitherBeChangedNorSentAgain() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.deliveries["raycast"] = [Self.delivery("d1", .failed, code: 500)] }
        let model = model(bench, hooks: [Self.hook("raycast", maker: "raycast-client", makerName: "Raycast"), Self.hook("mine")])
        await model.load()
        let theirs = model.webhooks[0]
        #expect(!model.isOwn(theirs) && model.isOwn(model.webhooks[1]))
        await model.setType("core.task", for: theirs)
        await model.turnOn(theirs)
        await model.setEvent(.itemTrashed, on: true, for: theirs)
        await model.setAllEvents(on: false, for: theirs)
        #expect(!bench.calls.calls.contains("changeWebhook") && !bench.calls.calls.contains("getWebhook"), "nothing is sent")
        await model.loadDeliveries(of: "raycast")
        #expect(!model.canRedeliver(model.deliveries["raycast"]![0], of: theirs), "a failed delivery of another maker's webhook can't be sent again")
        await model.redeliver(model.deliveries["raycast"]![0], of: theirs)
        #expect(!bench.calls.calls.contains("redeliver"))
        await model.setType("core.task", for: model.webhooks[1])
        #expect(bench.calls.calls.contains("changeWebhook"), "its own is changed")
    }

    @Test func deletingAnotherMakersWebhookAsksFirstNamingTheMakerThenEndsIt() async throws {
        let bench = OwnerBench()
        let model = everyMaker(bench)
        await model.load()
        let theirs = try #require(model.webhook("live"))
        model.askToDelete(theirs)
        let question = try #require(model.question)
        #expect(question.title == "Delete This Webhook?")
        #expect(question.message.contains("It was made by the key Lisbon zine importer."))
        #expect(!bench.calls.calls.contains("deleteWebhook"), "nothing is sent before the owner agrees")
        await model.confirm(question)
        #expect(bench.calls.calls.contains("deleteWebhook"))
        #expect(model.webhook("live") == nil && model.deleted == "live")
    }

    @Test func aRevokedMakersWebhookCanBeDeleted() async throws {
        let bench = OwnerBench()
        let model = everyMaker(bench)
        await model.load()
        let dead = try #require(model.webhook("revoked"))
        model.askToDelete(dead)
        #expect(try #require(model.question).message.contains("It was made by a revoked key."))
        await model.confirm(try #require(model.question))
        #expect(model.webhook("revoked") == nil)
        #expect(model.groups.map(\.id).contains("key:k-gone") == false)
    }

    @Test func aRefusedDeleteKeepsTheWebhookNamesThePermissionAndReadsTheGrantsAgain() async throws {
        let bench = OwnerBench()
        let model = everyMaker(bench)
        await model.load()
        bench.calls.fail("deleteWebhook", with: .notPermitted("keys.manage"))
        model.askToDelete(try #require(model.webhook("live")))
        await model.confirm(try #require(model.question))
        #expect(model.webhook("live") != nil && model.deleted == nil)
        #expect(model.rowErrors["live"] == .notPermitted("keys.manage"))
        #expect(bench.refreshed == 1)
    }

    @Test func theCapCountsOnlyWhatThisSignInMade() async {
        let bench = OwnerBench()
        let others = (0..<WebhooksModel.cap).map { Self.hook("o\($0)", maker: "other", makerName: "Raycast") }
        let model = model(bench, hooks: others + [Self.hook("mine")])
        await model.load()
        #expect(!model.atCap)
    }

    @Test func emptyWebhooksNeedNoMakerOrDeliveryLookup() async {
        let bench = OwnerBench()
        bench.calls.fail("identity", with: .unreachable)
        let model = model(bench)
        await model.load()
        #expect(model.hasLoaded && model.failure == nil && model.webhooks.isEmpty)
        #expect(!bench.calls.calls.contains("identity") && !bench.calls.calls.contains("deliveries"))
        model.beginNew()
        #expect(model.sheet == .new)
    }

    @Test func aRetryingDeliveryWithARecordedFailureShowsFailingUntilTheLatestDeliverySucceeds() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        var retrying = Self.delivery("d", .pending, code: 503)
        retrying.error = "The receiver answered 503."
        bench.calls.state.withLock { $0.deliveries["a"] = [retrying] }
        await model.load()
        let hook = try #require(model.webhook("a"))
        #expect(model.isSending(hook) == .failing)
        await model.setType("core.note", for: hook)
        #expect(model.isSending(hook) == .failing)
        bench.calls.state.withLock { $0.deliveries["a"] = [Self.delivery("d", .succeeded, code: 200)] }
        await model.loadDeliveries(of: hook.id)
        #expect(model.isSending(hook) == .sending)
    }

    @Test func changingTheAddressShowsTheCanceledDelivery() async {
        let bench = OwnerBench()
        let hook = Self.hook("a")
        let model = model(bench, hooks: [hook])
        var retrying = Self.delivery("d", .pending, code: 503)
        retrying.error = "The receiver answered 503."
        bench.calls.state.withLock { $0.deliveries[hook.id] = [retrying] }
        await model.load()
        await model.loadDeliveries(of: hook.id)
        #expect(model.isSending(hook) == .failing)
        model.beginChangeAddress(hook)
        model.addressDraft = "https://hooks.example.app/new"
        // The server cancels the pending delivery when it accepts the new address.
        bench.calls.state.withLock { $0.deliveries[hook.id]?[0].status = .canceled }
        await model.saveAddress()
        #expect(bench.calls.calls.suffix(2) == ["changeWebhook", "deliveries"])
        #expect(model.webhook(hook.id)?.url == "https://hooks.example.app/new")
        #expect(model.deliveries[hook.id]?.first?.status == .canceled)
        #expect(model.isSending(hook) == .sending)
    }

    @Test(arguments: [false, true], [false, true])
    func aLateListResponseKeepsTheNewerDetailStatus(listFails: Bool, detailFails: Bool) async throws {
        let bench = OwnerBench()
        let hook = Self.hook("a")
        let model = model(bench, hooks: [hook])
        let gate = bench.calls.hold("deliveries")
        bench.calls.state.withLock {
            $0.deliveries[hook.id] = [Self.delivery("d", .failed)]
            if listFails { $0.failures["deliveries"] = .notPermitted("webhooks.manage") }
        }
        let listing = Task { await model.load() }
        defer { gate.open() }
        try #require(await eventually { bench.calls.state.withLock { $0.waiting["deliveries"] == 1 } })
        bench.calls.state.withLock {
            $0.gates["deliveries"] = nil
            $0.failures["deliveries"] = detailFails ? .unreachable : nil
            $0.deliveries[hook.id] = [Self.delivery("d", .succeeded)]
        }
        await model.loadDeliveries(of: hook.id)
        gate.open()
        await listing.value
        #expect(model.isSending(hook) == (detailFails ? .unread : .sending))
        #expect(model.sendingFailures[hook.id] == (detailFails ? .unreachable : nil))
        #expect(model.deliveriesFailure[hook.id] == (detailFails ? .unreachable : nil))
        #expect(bench.refreshed == 0)
    }

    @Test(arguments: [false, true])
    func aNewerReadKeepsTheFullHistoryAnOpenDetailPageRequested(refreshList: Bool) async throws {
        let bench = OwnerBench()
        let hook = Self.hook("a")
        let model = model(bench, hooks: [hook])
        await model.load()
        let gate = bench.calls.hold("deliveries")
        let detail = Task { await model.loadDeliveries(of: hook.id) }
        defer { gate.open() }
        try #require(await eventually { bench.calls.state.withLock { $0.waiting["deliveries"] == 1 } })
        let latest = [Self.delivery("d2", .failed), Self.delivery("d1", .succeeded)]
        bench.calls.state.withLock {
            $0.gates["deliveries"] = nil
            $0.deliveries[hook.id] = latest
        }
        if refreshList { await model.load() } else { await model.loadDeliveries(of: hook.id) }
        gate.open()
        await detail.value
        #expect(model.isSending(hook) == .failing)
        #expect(model.deliveries[hook.id] == latest)
    }

    @Test func anActiveWebhookWithAnExpiredOrRevokedMakerIsOff() async throws {
        let bench = OwnerBench()
        let model = everyMaker(bench)
        await model.load()
        for id in ["expired", "revoked"] {
            let hook = try #require(model.webhook(id))
            #expect(hook.active)
            #expect(model.isSending(hook) == .off)
        }
        #expect(model.isSending(try #require(model.webhook("live"))) == .sending)
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
        #expect(model.created?.secret == "whsec_3fKq8Vn2Lp7Xr1Tz9Bm4Yc6Wd0Hs5Ja2e7b91c4d60a38f5e1b9c2d7a4f08e63b15d9c0a7e24f")
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
        #expect(title == "Webhook Created")
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

    @Test func closingSettingsWhileTheSecretShowsDuringTheReloadAfterTheCreateTellsAndDropsTheSecret() async throws {
        let bench = OwnerBench()
        let model = model(bench)
        await model.load()
        let gate = bench.calls.hold("webhooks")
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        let making = Task { await model.make() }
        #expect(try await eventuallyAsking { model.sheet == .secret })
        let drafts = model.takeDrafts()
        gate.open()
        await making.value
        #expect(drafts.count == 1, "the secret was made and is told about, not forgotten")
        if case .told(let title, let message)? = drafts.first {
            #expect(title == "Webhook Created")
            #expect(!message.contains("whsec_"))
        } else {
            Issue.record("told")
        }
        #expect(model.created == nil)
        #expect(model.sheet == nil)
        #expect(bench.late.isEmpty, "nothing is told twice")
    }

    @Test func aNewWebhookDoesNotWaitForTheDeliveriesOfTheOthers() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        let gate = bench.calls.hold("deliveries")
        model.beginNew()
        model.draft.address = "https://hooks.ledgerly.app/marfa"
        await model.make()
        #expect(model.sheet == .secret)
        #expect(model.webhooks.count == 2, "the list is read again")
        gate.open()
    }

    @Test func aDeliveryCanBeSentAgainOnlyWhenItFailedAndItsWebhookIsOn() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.deliveries["on"] = [Self.delivery("d1", .failed, code: 500), Self.delivery("d2", .succeeded, code: 200)]
            $0.deliveries["off"] = [Self.delivery("d3", .failed, code: 500)]
        }
        let model = model(bench, hooks: [Self.hook("on"), Self.hook("off", active: false)])
        await model.load()
        #expect(model.isSending(model.webhooks[0]) == .failing)
        #expect(model.isSending(model.webhooks[1]) == .off)
        await model.loadDeliveries(of: "on")
        await model.loadDeliveries(of: "off")
        #expect(model.canRedeliver(model.deliveries["on"]![0], of: model.webhooks[0]))
        #expect(!model.canRedeliver(model.deliveries["on"]![1], of: model.webhooks[0]))
        #expect(!model.canRedeliver(model.deliveries["off"]![0], of: model.webhooks[1]), "an off webhook sends nothing")
        await model.redeliver(model.deliveries["off"]![0], of: model.webhooks[1])
        #expect(!bench.calls.calls.contains("redeliver"))
    }

    @Test func anEventChangeIsBuiltOnTheWebhookAsTheServerHoldsItNow() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", events: ["item.created"])])
        await model.load()
        // Another app turned an event on after the page read the list.
        bench.calls.state.withLock { $0.webhooks[0].events = ["item.created", "edge.created"] }
        await model.setEvent(.itemTrashed, on: true, for: model.webhooks[0])
        #expect(Set(model.webhooks[0].events) == ["item.created", "edge.created", "item.trashed"])
        bench.calls.state.withLock { $0.webhooks[0].events.append("item.updated") }
        await model.setAllEvents(on: false, for: model.webhooks[0])
        #expect(model.webhooks[0].events.isEmpty || model.webhooks[0].events.allSatisfy { WebhookEvent(rawValue: $0) == nil })
    }

    @Test func anEventChangeToAWebhookGoneSinceTheLastReadIsToldAsGone() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        bench.calls.state.withLock { $0.webhooks = [] }
        await model.setEvent(.itemTrashed, on: true, for: model.webhooks[0])
        #expect(model.isGone("a"))
        #expect(!bench.calls.calls.contains("changeWebhook"), "nothing is sent for a webhook that is not there")
    }

    @Test func turningAnEventOnOrOffSendsEveryEventAndKeepsOnesThisBuildDoesNotKnow() async {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a", events: ["item.created", "item.future"])])
        await model.load()
        await model.setEvent(.itemTrashed, on: true, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.created", "item.trashed", "item.future"])
        await model.setEvent(.itemCreated, on: false, for: model.webhooks[0])
        #expect(model.webhooks[0].events == ["item.trashed", "item.future"])
        #expect(model.webhooks[0].maker?.id == Self.me, "a change keeps the maker the server's answer leaves out")
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
        #expect(model.rowErrors["a"] == .refused("A webhook needs at least one event."))
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

    @Test func refusingToTurnOffKeepsSendingAndExplainsTheFailure() async throws {
        let bench = OwnerBench()
        let address = "https://castell.studio/" + String(repeating: "studio/", count: 80)
        let model = model(bench, hooks: [Self.hook("a", address)])
        await model.load()
        let webhook = try #require(model.webhook("a"))
        #expect(WebhooksPage.subpage(for: webhook).title == String(address.dropFirst(8)))
        bench.calls.fail("changeWebhook", with: .unreachable)
        model.askToTurnOff(webhook)
        await model.confirm(try #require(model.question))
        #expect(model.webhook("a")?.active == true)
        #expect(model.rowErrors["a"] == .unreachable)
    }

    @Test func deletingAsksFirstThenRemovesAndTellsThePageToGoBack() async throws {
        let bench = OwnerBench()
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        model.askToDelete(model.webhooks[0])
        let asked = try #require(model.question)
        #expect(asked.title == "Delete This Webhook?")
        #expect(asked.message.contains(WebhooksModel.display(model.webhooks[0].url)))
        #expect(asked.message.contains("can’t be undone"))
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
        #expect(model.rowErrors["a"] == .notFound)
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
        #expect(model.rowErrors["a"] == .notPermitted("webhooks.manage"))
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

    @Test func aFailedDeliveryIsSentAgainAndOneTheServerNowRefusesIsToldWithOneLine() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.deliveries["a"] = [Self.delivery("d2", .failed, code: 500), Self.delivery("d1", .failed, code: 500)]
        }
        let model = model(bench, hooks: [Self.hook("a")])
        await model.load()
        await model.loadDeliveries(of: "a")
        // Another app sent the first one again between the page's read and the click.
        bench.calls.state.withLock { $0.deliveries["a"]![0].status = .succeeded }
        await model.redeliver(model.deliveries["a"]![0], of: model.webhooks[0])
        #expect(model.deliveryErrors["a"] == .redeliveryRefused(.deliveryNotFailed))
        bench.calls.state.withLock { $0.webhooks[0].active = false }
        await model.redeliver(model.deliveries["a"]![1], of: model.webhooks[0])
        #expect(model.deliveryErrors["a"] == .redeliveryRefused(.webhookInactive))
        #expect(model.webhooks[0].active == false)
        await model.turnOn(model.webhooks[0])
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
        #expect(model.deliveryErrors["a"] == .unreachable)
        #expect(model.deliveries["a"]?[0].status == .failed)
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
