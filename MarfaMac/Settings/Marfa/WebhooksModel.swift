import Foundation
import Marfa
import Observation

/// The Webhooks page: each webhook with its address, the events it sends, its deliveries and Delete. A sign-in holding
/// Manage Webhooks and Manage Keys sees every app's and key's webhooks, grouped by who made them, and may delete any;
/// only the maker changes one or sends a delivery again. The model keeps the list, edits, delivery actions and secret
/// sheet together so they use the same ownership and scope checks.
@Observable @MainActor final class WebhooksModel: OwnerDraftHolding {
    /// Whether a maker still stands.
    enum Standing: Equatable {
        case standing
        /// A key past its expiry.
        case expired
        case unread
        /// A key that is gone, or an app that is no longer connected: the server has no name for it.
        case gone

        /// Where a group stands in the list: makers that stand, then expired ones, then those that are gone.
        var rank: Int {
            switch self {
            case .standing: 0
            case .expired: 1
            case .gone, .unread: 2
            }
        }
    }

    /// The webhooks one maker made. This sign-in's own are one group, first, whoever's name they carry.
    struct Group: Identifiable, Equatable {
        let id: String
        let maker: OwnerWebhook.Maker?
        let name: String?
        let standing: Standing
        let isOwn: Bool
        let webhooks: [OwnerWebhook]
    }

    /// Whether a webhook is sending, as the list says it.
    enum Sending: Equatable {
        case checking, sending, off, failing, unread
    }

    struct Draft: Equatable {
        var address = ""
        var events: Set<String> = Self.starting
        /// The type, with its subtypes, or the pattern; nil sends item events of every type.
        var type: String?

        static let starting: Set<String> = [
            WebhookEvent.itemCreated.rawValue, WebhookEvent.itemUpdated.rawValue, WebhookEvent.itemTrashed.rawValue,
        ]
    }

    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case turnOff(String)
            case delete(String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
    }

    enum Sheet: Equatable {
        case new
        case secret
        case address(String)
    }

    static let cap = 100

    private let context: OwnerContext

    private(set) var webhooks: [OwnerWebhook] = []
    /// Who the app is signed in as, which tells its own webhooks from the others'. Read only where the list holds others'.
    private(set) var identity: OwnIdentity?
    /// Whether the list on show was read with every maker's webhooks in it. The grants may change under a list already read,
    /// so what the list holds is told by this, not by the grants now.
    private var listedEvery = false
    /// Set where the permissions changed while a read was under way, which then reads again.
    private var scopeChangedWhileLoading = false
    /// The keys, which tell an expired maker from one that stands. Read only where the list holds others'.
    private var keys: [KeyInfo] = []
    private(set) var typeNames: [String: String] = [:]
    private let loader = OwnerLoader()
    private var isReadingDetails = false
    private let keysRead = OwnerLoader.ReadStatus()
    var keysFailure: OwnerFailure? { listedEvery ? keysRead.failure : nil }
    var failure: OwnerFailure? { loader.failure }
    private var isLoading: Bool { loader.isLoading || isReadingDetails }
    var hasLoaded: Bool { loader.hasLoaded }
    private(set) var sendingFailures: [String: OwnerFailure] = [:]
    /// Whether each webhook is sending, read from its latest delivery after the list shows.
    private(set) var sending: [String: Sending] = [:]
    /// One line under a webhook's rows whose change was refused, by the webhook's id.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    var question: Question?
    var sheet: Sheet?
    var draft = Draft()
    /// Why the server refused the new webhook, in one line; the sheet keeps what was typed.
    private(set) var draftError: String?
    private(set) var isMaking = false
    /// The webhook just made, shown once and dropped when the sheet closes.
    private(set) var created: CreatedWebhook?
    var addressDraft = ""
    private(set) var addressError: String?
    private(set) var isSavingAddress = false
    /// The webhooks that were found gone while their page was open.
    private(set) var gone: Set<String> = []
    /// The webhook just deleted, so the page it was shown on can go back.
    private(set) var deleted: String?
    /// The deliveries of each webhook whose page was opened, newest first.
    private(set) var deliveries: [String: [WebhookDeliveryInfo]] = [:]
    private(set) var deliveriesFailure: [String: OwnerFailure] = [:]
    /// One line under a webhook's deliveries whose redelivery was refused, by the webhook's id.
    private(set) var deliveryErrors: [String: OwnerFailure] = [:]
    private(set) var redelivering: Set<String> = []
    private var closedWhileMaking = false

    init(context: OwnerContext) {
        self.context = context
    }

    func webhook(_ id: String) -> OwnerWebhook? { webhooks.first { $0.id == id } }

    var canMake: Bool { context.grants().contains(.webhooksManage) }

    var atCap: Bool { webhooks.filter(isOwn).count >= Self.cap }

    /// Whether the server lists and ends every maker's webhooks for this sign-in: it needs both permissions.
    var seesEvery: Bool { context.grants().isSuperset(of: [.webhooksManage, .keysManage]) }

    /// Whether this sign-in made `webhook`, which alone may change it or send a delivery again. Where the list holds only
    /// this sign-in's, all of it is; where it holds every maker's, the maker is matched with who the app is signed in as, by
    /// identity (`OwnIdentity.made`).
    func isOwn(_ webhook: OwnerWebhook) -> Bool {
        guard listedEvery else { return true }
        guard let maker = webhook.maker, let identity else { return false }
        return identity.made(maker)
    }

    private func standing(of maker: OwnerWebhook.Maker?) -> Standing {
        guard let maker else { return .standing }
        guard maker.name != nil else { return .gone }
        if maker.kind == .key {
            if let key = keys.first(where: { $0.id == maker.id }) {
                if let ends = key.expires, ends <= .now { return .expired }
            } else if keysFailure != nil {
                return .unread
            }
        }
        return .standing
    }

    /// Groups this sign-in’s webhooks first, then the other apps and keys. Expired or missing makers come last.
    /// Each group lists its oldest webhook first.
    var groups: [Group] {
        let sorted = webhooks.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
        let own = sorted.filter(isOwn)
        let ownName = own.compactMap { $0.maker?.name }.first
        var groups = [Group(id: "own", maker: nil, name: ownName, standing: .standing, isOwn: true, webhooks: own)]
        var order: [String] = []
        var members: [String: [OwnerWebhook]] = [:]
        for webhook in sorted where !isOwn(webhook) {
            let key = (webhook.maker?.kind == .key ? "key:" : "app:") + (webhook.maker?.id ?? "")
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(webhook)
        }
        let others = order.map { key -> Group in
            let maker = members[key]?.first?.maker
            return Group(
                id: key, maker: maker, name: maker?.name, standing: standing(of: maker), isOwn: false, webhooks: members[key] ?? [])
        }
        groups += others.sorted { lhs, rhs in
            if lhs.standing.rank != rhs.standing.rank { return lhs.standing.rank < rhs.standing.rank }
            if (lhs.maker?.kind == .app) != (rhs.maker?.kind == .app) { return lhs.maker?.kind == .app }
            return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
        }
        return groups
    }

    // MARK: Who made it

    /// Who made a webhook, in words that follow "Made by": the app, "the key" and its name, or what became of the maker.
    func maker(of webhook: OwnerWebhook) -> String {
        guard let maker = webhook.maker else { return String(localized: "this sign-in") }
        return Self.phrase(maker: maker, standing: standing(of: maker))
    }

    static func phrase(maker: OwnerWebhook.Maker, standing: Standing) -> String {
        switch (maker.kind, maker.name, standing) {
        case (.key, nil, _): String(localized: "a revoked key")
        case (.app, nil, _): String(localized: "an app that’s no longer connected")
        case (.key, let name?, .expired): String(localized: "the key \(name) (expired)")
        case (.key, let name?, .unread): String(localized: "the key \(name) (status unknown)")
        case (.key, let name?, _): String(localized: "the key \(name)")
        case (.app, let name?, _): name
        }
    }

    /// The name above a group: "Made by the app", "Made by the key Lisbon zine importer".
    func heading(of group: Group) -> String {
        if group.isOwn {
            guard let name = group.name else { return String(localized: "Made by This Sign-In") }
            return String(localized: "Made by \(name)")
        }
        guard let maker = group.maker else { return String(localized: "Made by This Sign-In") }
        return String(localized: "Made by \(Self.phrase(maker: maker, standing: group.standing))")
    }

    // MARK: Words

    /// A webhook's address as a row shows it: without the scheme.
    static func display(_ address: String) -> String {
        for scheme in ["https://", "http://"] where address.hasPrefix(scheme) { return String(address.dropFirst(scheme.count)) }
        return address
    }

    /// What a webhook sends item events for, in words.
    func typeTitle(_ type: String?) -> String {
        guard let type else { return String(localized: "All Types") }
        return AccessScopes.title(of: type, names: typeNames)
    }

    /// "Jobs. 3 events.", the line under a webhook in the list.
    func summary(of webhook: OwnerWebhook) -> String {
        let count = webhook.events.count
        let events = count == 1 ? String(localized: "1 event.") : String(localized: "\(count) events.")
        return String(localized: "\(typeTitle(webhook.typeFilter)). \(events)")
    }

    func isSending(_ webhook: OwnerWebhook) -> Sending {
        guard webhook.active else { return .off }
        if sendingFailures[webhook.id] != nil { return .unread }
        return sending[webhook.id] ?? .checking
    }

    // MARK: Reading

    /// The list is available while the app reads type names and checks the latest deliveries.
    func load() async {
        guard !isLoading else { return }
        isReadingDetails = true
        await readList()
        if failure == nil, seesEvery == listedEvery, !Task.isCancelled {
            await loader.read(.quiet { [self] () throws(OwnerFailure) in
                typeNames = try await context.calls.typeNames()
            }, in: context)
            if seesEvery == listedEvery, !Task.isCancelled { await loadSending() }
        }
        isReadingDetails = false
        await reloadIfScopeChanged()
    }

    /// A create can refresh the list while an earlier load still reads its details.
    private func readList(waitForPrevious: Bool = false) async {
        await loader.load(in: context, waitForPrevious: waitForPrevious, primary: { () throws(OwnerFailure) in
            let every = seesEvery
            let listed = try await context.calls.webhooks()
            if every && !listed.isEmpty {
                if identity == nil { identity = try await context.calls.identity() }
            } else {
                (identity, keys) = (nil, [])
            }
            webhooks = listed
            listedEvery = every
            gone = gone.filter { id in !webhooks.contains { $0.id == id } }
        }, secondary: [
            .required(keysRead) { [self] () throws(OwnerFailure) in
                if listedEvery && webhooks.contains(where: { $0.maker?.kind == .key }) {
                    keys = try await context.calls.keys()
                }
            },
        ], showBeforeFinishing: true)
    }

    private func reloadIfScopeChanged() async {
        if !isLoading, scopeChangedWhileLoading || (failure == nil && seesEvery != listedEvery) {
            scopeChangedWhileLoading = false
            await readAgainIfScopeChanged()
        }
    }

    /// Reads the list again where the permissions changed what it holds, such as Manage Keys lost or gained: the list read
    /// before is dropped, not shown as the new scope's.
    func readAgainIfScopeChanged() async {
        guard hasLoaded, seesEvery != listedEvery else { return }
        guard !isLoading else {
            scopeChangedWhileLoading = true
            return
        }
        webhooks = []
        sending = [:]
        sendingFailures = [:]
        await load()
    }

    private func mayChange(_ id: String) -> Bool { canMake && webhook(id).map(isOwn) == true }

    /// Checks the latest deliveries a few at a time, after the list is available.
    private func loadSending() async {
        let calls = context.calls
        let every = listedEvery
        await readEach(
            of: webhooks.filter(\.active).map(\.id),
            read: { id -> Result<WebhookDeliveryInfo?, OwnerFailure> in
                do throws(OwnerFailure) { return .success(try await calls.deliveries(of: id, limit: 1).first) } catch { return .failure(error) }
            },
            take: { id, answer in
                guard seesEvery == every, listedEvery == every, webhook(id)?.active == true else { return }
                switch answer {
                case .success(let latest):
                    recordLatest(latest, of: id)
                case .failure(let failure):
                    sendingFailures[id] = failure
                    await context.learn(from: failure)
                }
            })
    }

    private func recordLatest(_ delivery: WebhookDeliveryInfo?, of id: String) {
        sendingFailures[id] = nil
        let failed = delivery?.status == .failed || (delivery?.status == .pending && delivery?.error != nil)
        sending[id] = failed ? .failing : .sending
    }

    func loadDeliveries(of id: String) async {
        do {
            let latest = try await context.calls.deliveries(of: id, limit: 50)
            deliveries[id] = latest
            recordLatest(latest.first, of: id)
            deliveriesFailure[id] = nil
        } catch {
            deliveriesFailure[id] = error
            await context.learn(from: error)
        }
    }

    // MARK: Changing a webhook

    private func change(_ id: String, _ change: WebhookChange) async {
        guard mayChange(id) else { return }
        rowErrors[id] = nil
        do {
            try await apply(id, change)
        } catch {
            rowErrors[id] = error
        }
    }

    /// Changes the events from the webhook as the server holds it just now, not as the page last read it, so an event
    /// another app turned on or off in between is kept. The server takes no version for a webhook, so a change in the moment
    /// between this read and the send can still be replaced.
    private func changeEvents(of id: String, _ build: (OwnerWebhook) -> [String]) async {
        guard mayChange(id) else { return }
        rowErrors[id] = nil
        do throws(OwnerFailure) {
            let current: OwnerWebhook
            do throws(OwnerFailure) {
                current = try await context.calls.webhook(id)
            } catch {
                if error == .notFound { markGone(id) }
                await context.learn(from: error)
                throw error
            }
            try await apply(id, WebhookChange(events: build(current)))
        } catch {
            rowErrors[id] = error
        }
    }

    /// Sends a change and takes the webhook as the server answers it. A webhook that is gone is told so.
    private func apply(_ id: String, _ change: WebhookChange) async throws(OwnerFailure) {
        do {
            take(try await context.calls.change(webhook: id, change))
        } catch {
            if error == .notFound { markGone(id) }
            await context.learn(from: error)
            throw error
        }
    }

    private func take(_ webhook: OwnerWebhook) {
        if let index = webhooks.firstIndex(where: { $0.id == webhook.id }) {
            var updated = webhook
            updated.maker = webhooks[index].maker
            webhooks[index] = updated
        }
    }

    private func markGone(_ id: String) {
        gone.insert(id)
        webhooks.removeAll { $0.id == id }
    }

    func isGone(_ id: String) -> Bool { gone.contains(id) }

    /// Turns one event on or off. The webhook keeps every event this build doesn't know, which another app may have set.
    func setEvent(_ event: WebhookEvent, on: Bool, for webhook: OwnerWebhook) async {
        await changeEvents(of: webhook.id) { current in
            var events = current.events.filter { $0 != event.rawValue }
            if on { events.append(event.rawValue) }
            return Self.ordered(events)
        }
    }

    func setAllEvents(on: Bool, for webhook: OwnerWebhook) async {
        await changeEvents(of: webhook.id) { current in
            let unknown = current.events.filter { WebhookEvent(rawValue: $0) == nil }
            return on ? Self.ordered(WebhookEvent.allCases.map(\.rawValue) + unknown) : unknown
        }
    }

    /// Events in the order the page lists them, with any this build doesn't know after them.
    static func ordered(_ events: [String]) -> [String] {
        let known = WebhookEvent.allCases.map(\.rawValue).filter(events.contains)
        return known + events.filter { WebhookEvent(rawValue: $0) == nil }
    }

    func setType(_ type: String?, for webhook: OwnerWebhook) async {
        guard type != webhook.typeFilter else { return }
        await change(webhook.id, WebhookChange(typeFilter: .some(type)))
    }

    func turnOn(_ webhook: OwnerWebhook) async {
        await change(webhook.id, WebhookChange(active: true))
        if self.webhook(webhook.id)?.active == true { await loadDeliveries(of: webhook.id) }
    }

    func askToTurnOff(_ webhook: OwnerWebhook) {
        question = Question(
            action: .turnOff(webhook.id), title: String(localized: "Turn off “\(Self.display(webhook.url))”?"),
            message: String(localized: "Deliveries waiting to be sent are dropped, and nothing more is sent until you turn it on."),
            confirm: String(localized: "Turn Off"))
    }

    func askToDelete(_ webhook: OwnerWebhook) {
        question = Question(
            action: .delete(webhook.id), title: String(localized: "Delete This Webhook?"),
            message: isOwn(webhook)
                ? String(localized: "\(Self.display(webhook.url)) stops sending at once, and its deliveries and signing secret are gone. This can’t be undone.")
                : String(localized: "\(Self.display(webhook.url)) stops sending at once, and its deliveries and signing secret are gone. It was made by \(maker(of: webhook)). This can’t be undone."),
            confirm: String(localized: "Delete"))
    }

    func cancelQuestion() { question = nil }

    func confirm(_ asked: Question) async {
        question = nil
        switch asked.action {
        case .turnOff(let id):
            await change(id, WebhookChange(active: false))
        case .delete(let id):
            rowErrors[id] = nil
            do {
                try await context.calls.delete(webhook: id)
                webhooks.removeAll { $0.id == id }
                deliveries[id] = nil
                deleted = id
            } catch {
                if error == .notFound {
                    markGone(id)
                } else {
                    rowErrors[id] = error
                }
                await context.learn(from: error)
            }
        }
    }

    // MARK: Address

    func beginChangeAddress(_ webhook: OwnerWebhook) {
        addressDraft = webhook.url
        addressError = nil
        sheet = .address(webhook.id)
    }

    var canSaveAddress: Bool {
        guard case .address(let id)? = sheet, let webhook = webhook(id) else { return false }
        let typed = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed != webhook.url && !isSavingAddress
    }

    func saveAddress() async {
        guard case .address(let id)? = sheet, canSaveAddress, mayChange(id) else { return }
        isSavingAddress = true
        defer { isSavingAddress = false }
        do {
            try await apply(id, WebhookChange(url: Self.normalized(addressDraft)))
            sheet = nil
            addressError = nil
        } catch {
            addressError = OwnerWording.line(error)
        }
    }

    /// An address as typed, with `https://` where it has no scheme.
    static func normalized(_ typed: String) -> String {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.contains("://") ? text : "https://" + text
    }

    // MARK: Redelivery

    /// Whether a delivery can be sent again: only a failed one of a webhook the app made, and only while it is on, as the server
    /// refuses both other ways (`events/redeliver-inactive`, `events/webhook-owner-no-change`).
    func canRedeliver(_ delivery: WebhookDeliveryInfo, of webhook: OwnerWebhook) -> Bool {
        isOwn(webhook) && webhook.active && delivery.status == .failed && !redelivering.contains(delivery.id)
    }

    /// Sends a failed delivery again to the webhook's address as it is now. The server accepts only a failed one.
    func redeliver(_ delivery: WebhookDeliveryInfo, of webhook: OwnerWebhook) async {
        guard canRedeliver(delivery, of: webhook) else { return }
        redelivering.insert(delivery.id)
        defer { redelivering.remove(delivery.id) }
        deliveryErrors[webhook.id] = nil
        do {
            let queued = try await context.calls.redeliver(delivery.id, of: webhook.id)
            if let index = deliveries[webhook.id]?.firstIndex(where: { $0.id == queued.id }) {
                deliveries[webhook.id]?[index] = queued
            }
            if let latest = deliveries[webhook.id]?.first { recordLatest(latest, of: webhook.id) }
        } catch {
            deliveryErrors[webhook.id] = error
            if error == .notFound { markGone(webhook.id) }
            await context.learn(from: error)
            if error == .redeliveryRefused(.webhookInactive), let current = try? await context.calls.webhook(webhook.id) {
                take(current)
            }
            await loadDeliveries(of: webhook.id)
        }
    }

    // MARK: New webhook

    func beginNew() {
        draft = Draft()
        draftError = nil
        sheet = .new
    }

    var canMakeDraft: Bool {
        !draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.events.isEmpty && !isMaking
    }

    func make() async {
        guard canMakeDraft else { return }
        isMaking = true
        draftError = nil
        let request = NewWebhook(
            url: Self.normalized(draft.address), events: WebhookEvent.allCases.map(\.rawValue).filter(draft.events.contains),
            typeFilter: draft.type)
        let made: CreatedWebhook
        do {
            made = try await context.calls.create(request)
        } catch {
            isMaking = false
            if closedWhileMaking {
                closedWhileMaking = false
                sheet = nil
                if let typed = typedDraft() { context.lateDraft(typed) }
            }
            draftError = OwnerWording.line(error)
            await context.learn(from: error)
            return
        }
        // The call has answered, so a close from here on finds the secret on show and tells about it.
        isMaking = false
        if closedWhileMaking {
            closedWhileMaking = false
            sheet = nil
            context.lateDraft(Self.creationNotice(made.webhook.url))
        } else {
            created = made
            sheet = .secret
        }
        recordLatest(nil, of: made.webhook.id)
        await readList(waitForPrevious: true)
        await reloadIfScopeChanged()
    }

    private static func creationNotice(_ address: String) -> OwnerDraft {
        .told(
            title: String(localized: "Webhook Created"),
            message: String(localized: "The webhook “\(display(address))” was made, and its signing secret can’t be shown again. If you didn’t copy it, delete the webhook on the Webhooks page and make it again."))
    }

    /// Closes the sheet; the signing secret goes with it, as it is shown only once.
    func closeSheet() {
        guard !isMaking, !isSavingAddress else { return }
        sheet = nil
        created = nil
        draftError = nil
        addressError = nil
    }

    // MARK: Closing

    /// What the sheet holds, which the app gives back when Settings closes: the address typed for a new webhook or a new
    /// address, never a signing secret. A webhook already made is told about instead. One still being made is told about
    /// when the call ends.
    func takeDrafts() -> [OwnerDraft] {
        if isMaking {
            closedWhileMaking = true
            return []
        }
        defer {
            sheet = nil
            created = nil
            draftError = nil
            addressError = nil
        }
        switch sheet {
        case .secret:
            return created.map { [Self.creationNotice($0.webhook.url)] } ?? []
        case .new:
            return typedDraft().map { [$0] } ?? []
        case .address(let id):
            let typed = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty, typed != webhook(id)?.url else { return [] }
            return [.typed(title: String(localized: "Webhook Address Not Changed"), text: typed)]
        case nil:
            return []
        }
    }

    private func typedDraft() -> OwnerDraft? {
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        return .typed(title: String(localized: "Webhook Not Made"), text: String(localized: "Address: \(address)"))
    }
}
