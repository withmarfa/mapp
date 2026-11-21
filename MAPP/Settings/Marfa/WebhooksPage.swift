import SwiftUI

/// The Webhooks page: the webhooks this sign-in made, each opening a page of its own with its address, the events it
/// sends, its deliveries (a failed one can be sent again) and Delete. New Webhook… makes one, and shows its signing secret
/// once.
struct WebhooksPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: WebhooksModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: WebhooksModel(context: OwnerContext(host: host)))
    }

    static func subpage(for webhook: OwnerWebhook) -> SettingsSubpage {
        SettingsSubpage(id: "webhook:" + webhook.id, title: WebhooksModel.display(webhook.url))
    }

    private var openID: String? {
        guard let id = subpage?.id, id.hasPrefix("webhook:") else { return nil }
        return String(id.dropFirst(8))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.closeSheet() }) {
                WebhookSheet(model: model, serverName: host.serverName)
            }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .onChange(of: model.deleted) { if $1 != nil { back() } }
            .accessibilityIdentifier("WebhooksPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let webhook = model.webhook(id) {
                WebhookDetail(model: model, webhook: webhook)
            } else {
                SettingsPageState(
                    symbol: "dot.radiowaves.up.forward", title: Text("This Webhook Is Gone"),
                    line: Text("It was deleted, here or somewhere else."), action: ("Back", back))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if model.groups.isEmpty {
                SettingsSection(name: Text("Webhooks")) {
                    SettingsEmptyCard(
                        symbol: "dot.radiowaves.up.forward", title: Text("No Webhooks"),
                        line: Text("A webhook sends events to an address you choose, as they happen."))
                    addRow
                }
            }
            ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                SettingsSection(
                    name: group.name.map { Text("Made by \($0)") } ?? Text("Made by This Sign-In"),
                    footer: index == model.groups.count - 1 ? Text("Only webhooks this sign-in made are listed. An app or a key sees only its own.") : nil
                ) {
                    ForEach(group.webhooks) { webhook in
                        let state = model.isSending(webhook)
                        SettingsLinkRow(
                            verbatim: WebhooksModel.display(webhook.url), line: model.summary(of: webhook),
                            lead: .tint("dot.radiowaves.up.forward", .gray), value: Self.title(state), dot: Self.dot(state)
                        ) { push(Self.subpage(for: webhook)) }
                    }
                    if index == 0 { addRow }
                }
            }
        }
    }

    @ViewBuilder private var addRow: some View {
        if model.atCap {
            SettingsAddRow(off: "New Webhook…", line: "This sign-in holds \(WebhooksModel.cap) webhooks, the most the server allows.")
        } else {
            SettingsAddRow("New Webhook…") { model.beginNew() }
        }
    }

    static func title(_ state: WebhooksModel.Sending) -> String {
        switch state {
        case .sending: String(localized: "Sending")
        case .off: String(localized: "Off")
        case .failing: String(localized: "Failing")
        }
    }

    static func dot(_ state: WebhooksModel.Sending) -> Color {
        switch state {
        case .sending: SettingsTokens.ok
        case .off: SettingsTokens.tertiaryText
        case .failing: SettingsTokens.warning
        }
    }
}

/// One webhook's page.
private struct WebhookDetail: View {
    let model: WebhooksModel
    let webhook: OwnerWebhook
    @State private var showsAllEvents = false
    @State private var showsAllDeliveries = false

    private static let firstEvents = 6
    private static let firstDeliveries = 10

    private var line: String {
        let made = webhook.created.map { String(localized: "Made \(OwnerWording.day($0)).") }
        let by = webhook.maker?.name.map { String(localized: "Made by \($0).") }
        return [by, made].compactMap { $0 }.joined(separator: " ")
    }

    private var eventNames: [WebhookEvent] {
        showsAllEvents ? WebhookEvent.allCases : Array(WebhookEvent.allCases.prefix(Self.firstEvents))
    }

    private var typeChoices: [(id: String, name: String)] {
        var names = model.typeNames.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
        if let held = webhook.typeFilter, !names.contains(where: { $0.id == held }) {
            names.insert((id: held, name: model.typeTitle(held)), at: 0)
        }
        return names
    }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(
                symbol: "dot.radiowaves.up.forward", tone: .pink, title: Text(verbatim: WebhooksModel.display(webhook.url)),
                line: line.isEmpty ? nil : Text(verbatim: line))
            if let problem = model.rowErrors[webhook.id] { OwnerProblem(title: "Not Changed", line: problem) }
            SettingsSection("Webhook") {
                SettingsRow(verbatim: String(localized: "Address"), line: webhook.url) {
                    SettingsButton("Change…") { model.beginChangeAddress(webhook) }
                }
                SettingsRow("For") {
                    SettingsPopUp(
                        title: "For", selection: Binding<String?> { webhook.typeFilter } set: { type in
                            Task { await model.setType(type, for: webhook) }
                        }
                    ) {
                        Text("All Types").tag(String?.none)
                        if !typeChoices.isEmpty { Divider() }
                        ForEach(typeChoices, id: \.id) { Text(verbatim: $0.name).tag(String?.some($0.id)) }
                    }
                }
                SettingsRow("Sending", line: "Turning it off drops what is waiting.") {
                    SettingsToggle(title: "Sending", isOn: Binding { webhook.active } set: { on in
                        if on { Task { await model.turnOn(webhook) } } else { model.askToTurnOff(webhook) }
                    })
                }
                SettingsRow("Signing Secret", line: "Shown once, when it was made.") {
                    SettingsValue(verbatim: "••••" + webhook.secretTail)
                }
            }
            SettingsSection(
                name: Text("Events"), footer: Text("Changing the events or the type drops waiting deliveries that no longer match.")
            ) {
                SettingsCheckRow(
                    title: Text("All Events"),
                    isOn: Binding { WebhookEvent.allCases.allSatisfy { webhook.events.contains($0.rawValue) } } set: { on in
                        Task { await model.setAllEvents(on: on, for: webhook) }
                    })
                ForEach(eventNames, id: \.self) { event in
                    SettingsCheckRow(
                        title: Text(verbatim: event.title), line: event.line.map { Text(verbatim: $0) },
                        isOn: Binding { webhook.events.contains(event.rawValue) } set: { on in
                            Task { await model.setEvent(event, on: on, for: webhook) }
                        })
                }
                if !showsAllEvents {
                    SettingsShowMoreRow(title: Text("\(WebhookEvent.allCases.count - Self.firstEvents) More")) { showsAllEvents = true }
                }
            }
            deliveries
            SettingsSection("Delete") {
                SettingsRow(verbatim: String(localized: "Delete This Webhook"), line: String(localized: "It stops sending at once.")) {
                    SettingsButton("Delete…", role: .destructive) { model.askToDelete(webhook) }
                }
            }
        }
        .task(id: webhook.id) { await model.loadDeliveries(of: webhook.id) }
    }

    @ViewBuilder private var deliveries: some View {
        let all = model.deliveries[webhook.id] ?? []
        if let problem = model.deliveryErrors[webhook.id] { OwnerProblem(title: "Not Sent Again", line: problem) }
        SettingsSection(name: Text("Deliveries"), line: Text("The latest events sent to this address. Only a failed one can be sent again.")) {
            if let problem = model.deliveriesFailure[webhook.id], all.isEmpty {
                SettingsRow(verbatim: String(localized: "Deliveries Couldn’t Be Read"), line: problem, lead: .tint("exclamationmark.triangle", .orange), lines: nil)
            } else if all.isEmpty {
                SettingsEmptyCard(symbol: "paperplane", title: Text("No Deliveries"), line: Text("Nothing has been sent to this address yet."))
            } else {
                SettingsSectionTable(
                    rows: showsAllDeliveries ? all : Array(all.prefix(Self.firstDeliveries)),
                    columns: [
                        SettingsTableColumn<WebhookDeliveryInfo>("When", width: 150) { Text(verbatim: Self.when($0.created)) },
                        SettingsTableColumn("Event") { Text(verbatim: WebhookEvent(rawValue: $0.event)?.title ?? $0.event) },
                        SettingsTableColumn("Answer", width: 110) { Text(verbatim: Self.answer($0)) },
                    ],
                    action: SettingsRowAction(
                        title: "Redeliver", isEnabled: { $0.status == .failed && !model.redelivering.contains($0.id) },
                        perform: { delivery in Task { await model.redeliver(delivery, of: webhook) } }),
                    total: all.count, showAll: showsAllDeliveries || all.count <= Self.firstDeliveries ? nil : { showsAllDeliveries = true })
            }
        }
    }

    static func when(_ date: Date?) -> String {
        date.map { DateDisplay.text(of: $0, place: .value, format: .stored()) } ?? ""
    }

    /// What the receiver answered, or what became of a delivery with no answer.
    static func answer(_ delivery: WebhookDeliveryInfo) -> String {
        switch delivery.status {
        case .succeeded: delivery.statusCode.map(String.init) ?? String(localized: "Delivered")
        case .failed: delivery.statusCode.map { String(localized: "Failed, \($0)") } ?? String(localized: "No Answer")
        case .pending: String(localized: "Waiting")
        case .canceled: String(localized: "Not Sent")
        }
    }
}

/// The Webhooks page's sheets, which the window shows in its middle: New Webhook, the signing secret shown once and the
/// address change.
struct WebhookSheet: View {
    @Bindable var model: WebhooksModel
    let serverName: String

    var body: some View {
        switch model.sheet {
        case .new?: NewWebhookSheet(model: model, serverName: serverName)
        case .secret?: SecretSheet(model: model)
        case .address?: AddressChangeSheet(model: model)
        case nil: EmptyView()
        }
    }
}

private struct NewWebhookSheet: View {
    @Bindable var model: WebhooksModel
    let serverName: String
    @State private var showsAll = false

    private static let first = 3

    private var types: [(id: String, name: String)] {
        model.typeNames.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var events: [WebhookEvent] {
        showsAll ? WebhookEvent.allCases : Array(WebhookEvent.allCases.prefix(Self.first))
    }

    var body: some View {
        SettingsSheet(title: Text("New Webhook"), line: Text("\(serverName) sends a request to an address you choose.")) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSheetField(label: "Address", error: model.draftError) {
                    SettingsField(
                        title: "Address", text: $model.draft.address, prompt: "https://", isError: model.draftError != nil,
                        isMonospaced: true, width: nil, onSubmit: { Task { await model.make() } })
                }
                SettingsSection("Send") {
                    SettingsRow("For") {
                        SettingsPopUp(title: "For", selection: $model.draft.type) {
                            Text("All Types").tag(String?.none)
                            if !types.isEmpty { Divider() }
                            ForEach(types, id: \.id) { Text(verbatim: $0.name).tag(String?.some($0.id)) }
                        }
                    }
                    ForEach(events, id: \.self) { event in
                        SettingsCheckRow(
                            title: Text(verbatim: event.title), line: event.line.map { Text(verbatim: $0) },
                            isOn: Binding { model.draft.events.contains(event.rawValue) } set: { on in
                                if on { model.draft.events.insert(event.rawValue) } else { model.draft.events.remove(event.rawValue) }
                            })
                    }
                    if !showsAll {
                        SettingsShowMoreRow(title: Text("\(WebhookEvent.allCases.count - Self.first) More Events")) { showsAll = true }
                    }
                }
            }
        } buttons: {
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Create Webhook") { Task { await model.make() } }
                .disabled(!model.canMakeDraft).keyboardShortcut(.defaultAction)
        }
    }
}

private struct SecretSheet: View {
    let model: WebhooksModel
    @State private var copied = false

    var body: some View {
        SettingsSheet(
            title: Text("Copy the Signing Secret Now"), line: Text("It is shown only once. The service checks each request with it.")
        ) {
            if let created = model.created {
                SettingsSheetField(verbatim: WebhooksModel.display(created.webhook.url)) { SettingsReadOnlyValue(text: created.secret) }
            }
        } buttons: {
            Spacer(minLength: 0)
            SettingsButton(copied ? "Copied" : "Copy") {
                guard let secret = model.created?.secret else { return }
                OwnerClipboard.copySecret(secret)
                copied = true
            }
            SettingsButton("Done") { model.closeSheet() }.keyboardShortcut(.defaultAction)
        }
    }
}

private struct AddressChangeSheet: View {
    @Bindable var model: WebhooksModel

    var body: some View {
        SettingsSheet(title: Text("Change Address"), line: Text("Deliveries waiting for the old address are dropped.")) {
            SettingsSheetField(label: "Address", error: model.addressError) {
                SettingsField(
                    title: "Address", text: $model.addressDraft, prompt: "https://", isError: model.addressError != nil,
                    isMonospaced: true, width: nil, onSubmit: { Task { await model.saveAddress() } })
            }
        } buttons: {
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Change Address") { Task { await model.saveAddress() } }
                .disabled(!model.canSaveAddress).keyboardShortcut(.defaultAction)
        }
    }
}
