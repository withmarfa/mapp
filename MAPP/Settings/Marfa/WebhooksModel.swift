import Foundation
import Marfa
import Observation

/// The Webhooks page: the webhooks this sign-in made, each with its address, the events it sends, its deliveries and
/// Delete. A key or an app sees only its own webhooks, so these are the only ones listed; the list is grouped by maker so
/// that a group for every app can join it once the server lists them all.
@Observable @MainActor final class WebhooksModel: OwnerDraftHolding {
    /// The webhooks one maker made.
    struct Group: Identifiable, Equatable {
        let id: String
        let name: String?
        let webhooks: [OwnerWebhook]
    }

    /// Whether a webhook is sending, as the list says it.
    enum Sending: Equatable {
        case sending, off, failing
    }

    /// What the New Webhook sheet holds.
    struct Draft: Equatable {
        var address = ""
        var events: Set<String> = Self.starting
        /// The type, with its subtypes, or the pattern; nil sends item events of every type.
        var type: String?

        static let starting: Set<String> = [
            WebhookEvent.itemCreated.rawValue, WebhookEvent.itemUpdated.rawValue, WebhookEvent.itemTrashed.rawValue,
        ]
    }

    /// A change waiting on the owner's answer.
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

    /// How many webhooks one credential may hold, which the server refuses to pass.
    static let cap = 100

    private let context: OwnerContext

    private(set) var webhooks: [OwnerWebhook] = []
    private(set) var typeNames: [String: String] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
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

    var atCap: Bool { webhooks.count >= Self.cap }

    /// The webhooks grouped by the credential that made them, oldest first within each group.
    var groups: [Group] {
        var order: [String] = []
        var members: [String: [OwnerWebhook]] = [:]
        for webhook in webhooks.sorted(by: { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }) {
            let key = webhook.maker?.id ?? ""
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(webhook)
        }
        return order.map { key in
            Group(id: key, name: members[key]?.compactMap { $0.maker?.name }.first, webhooks: members[key] ?? [])
        }
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
        return sending[webhook.id] ?? .sending
    }

    // MARK: Reading

    /// Reads the list, which the page shows at once, then what each webhook says about itself.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard await readList() else { return }
        typeNames = (try? await context.calls.typeNames()) ?? typeNames
        await loadSending()
    }

    /// Reads only the list, and answers whether it could.
    private func readList() async -> Bool {
        defer { hasLoaded = true }
        do {
            webhooks = try await context.calls.webhooks()
            gone = gone.filter { id in !webhooks.contains { $0.id == id } }
            failure = nil
            return true
        } catch {
            failure = error
            await context.learn(from: error)
            return false
        }
    }

    /// Reads each active webhook's latest delivery, a few at a time, so the list can say which are failing. A webhook whose
    /// deliveries can't be read keeps saying it is sending.
    private func loadSending() async {
        let calls = context.calls
        await readEach(
            of: webhooks.filter(\.active).map(\.id),
            read: { id in try? await calls.deliveries(of: id).first },
            take: { id, latest in
                guard let latest else { return }
                sending[id] = latest.status == .failed ? .failing : .sending
            })
    }

    func loadDeliveries(of id: String) async {
        do {
            deliveries[id] = try await context.calls.deliveries(of: id)
            deliveriesFailure[id] = nil
        } catch {
            deliveriesFailure[id] = error
            await context.learn(from: error)
        }
    }

    // MARK: Changing a webhook

    private func change(_ id: String, _ change: WebhookChange) async {
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
            var updated = try await context.calls.change(webhook: id, change)
            if let index = webhooks.firstIndex(where: { $0.id == id }) {
                updated.maker = webhooks[index].maker
                webhooks[index] = updated
            }
            sending[id] = nil
        } catch {
            if error == .notFound { markGone(id) }
            await context.learn(from: error)
            throw error
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
            message: String(localized: "\(Self.display(webhook.url)) stops sending at once, and its deliveries and signing secret are gone. This can’t be undone."),
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
        guard case .address(let id)? = sheet, canSaveAddress else { return }
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

    /// Whether a delivery can be sent again: only a failed one, and only while its webhook is on, as the server refuses
    /// both other ways (`events/redeliver-inactive`).
    func canRedeliver(_ delivery: WebhookDeliveryInfo, of webhook: OwnerWebhook) -> Bool {
        webhook.active && delivery.status == .failed && !redelivering.contains(delivery.id)
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
            sending[webhook.id] = nil
        } catch {
            deliveryErrors[webhook.id] = error
            if error == .notFound { markGone(webhook.id) }
            await context.learn(from: error)
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
            context.lateDraft(Self.notCopied(made.webhook.url))
        } else {
            created = made
            sheet = .secret
        }
        _ = await readList()
    }

    /// The notice for a webhook made whose signing secret was never copied: it can't be shown again.
    private static func notCopied(_ address: String) -> OwnerDraft {
        .told(
            title: String(localized: "Signing Secret Not Copied"),
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
            return created.map { [Self.notCopied($0.webhook.url)] } ?? []
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
