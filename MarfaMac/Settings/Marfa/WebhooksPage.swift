import Marfa
import SwiftUI

/// The Webhooks page: every webhook the server lists for this sign-in, grouped by who made it, each opening a page of its
/// own with its address, the events it sends, its deliveries and Delete. The app's own can be changed and a failed delivery sent
/// again; another maker's can only be read and deleted. New Webhook… makes one, and shows its signing secret once.
struct WebhooksPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: WebhooksModel
    @Environment(\.settingsNavigation) private var navigation

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
            .onChange(of: model.seesEvery) { Task { await model.readAgainIfScopeChanged() } }
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
            .onChange(of: model.deleted) { if $1 != nil { navigation?.back() } }
            .accessibilityIdentifier("WebhooksPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .webhooks, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let webhook = model.webhook(id) {
                WebhookDetail(model: model, webhook: webhook, host: host)
            } else {
                SettingsPageState(
                    symbol: "dot.radiowaves.up.forward", title: Text("This Webhook Is Gone"),
                    line: Text("It was deleted, here or somewhere else."), action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if let failure = model.keysFailure {
                OwnerProblem(title: "Couldn’t Check Webhook Keys", failure: failure, page: .webhooks, host: host) {
                    Task { await model.load() }
                }
            }
            if let failure = model.webhooks.lazy.filter(\.active).compactMap({ model.sendingFailures[$0.id] }).first {
                OwnerProblem(title: "Couldn’t Check Webhook Deliveries", failure: failure, page: .webhooks, host: host) {
                    Task { await model.load() }
                }
            }
            if model.webhooks.isEmpty {
                SettingsSection(name: Text("Webhooks")) {
                    SettingsEmptyCard(
                        symbol: "dot.radiowaves.up.forward", title: Text("No Webhooks"),
                        line: Text("A webhook sends events to an address you choose, as they happen."))
                    addRow
                }
            } else {
                let groups = model.groups.filter { $0.isOwn || !$0.webhooks.isEmpty }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    SettingsSection(
                        name: Text(verbatim: model.heading(of: group)),
                        footer: index == groups.count - 1 && model.seesEvery
                            ? Text("You can see and end any webhook. Only the app or key that made one changes it.") : nil
                    ) {
                        ForEach(group.webhooks) { webhook in
                            let state = model.isSending(webhook)
                            SettingsLinkRow(
                                verbatim: WebhooksModel.display(webhook.url), line: model.summary(of: webhook),
                                lead: .well(symbol: "dot.radiowaves.up.forward"), value: Self.title(state), dot: Self.dot(state)
                            ) { navigation?.push(Self.subpage(for: webhook)) }
                        }
                        if group.isOwn { addRow }
                    }
                }
            }
            if !model.seesEvery && model.canMake { othersNeedKeys }
        }
    }

    /// Without Manage Keys the list holds the app's own only, and says what the others need.
    private var othersNeedKeys: some View {
        SettingsSection(name: nil) {
            OwnerProblemRow(
                title: "Other Webhooks Aren’t Listed", failure: .notPermitted(InstancePermission.keysManage.rawValue),
                line: String(localized: "Seeing and ending the webhooks other apps and keys made needs Manage Keys."), page: .webhooks, host: host)
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
        case .unread: String(localized: "Couldn’t Check")
        }
    }

    static func dot(_ state: WebhooksModel.Sending) -> Color {
        switch state {
        case .sending: SettingsTokens.ok
        case .off: SettingsTokens.tertiaryText
        case .failing, .unread: SettingsTokens.warning
        }
    }
}

/// One webhook's page.
private struct WebhookDetail: View {
    let model: WebhooksModel
    let webhook: OwnerWebhook
    let host: any MarfaSettingsHost
    @State private var showsAllEvents = false
    @State private var showsAllDeliveries = false

    private static let firstEvents = 6
    private static let firstDeliveries = 10

    private var isOwn: Bool { model.isOwn(webhook) }

    private var line: String {
        let day = webhook.created.map { OwnerWording.day($0) }
        let maker = webhook.maker == nil ? nil : model.maker(of: webhook)
        switch (maker, day) {
        case (let maker?, let day?): return String(localized: "Made by \(maker), \(day).")
        case (let maker?, nil): return String(localized: "Made by \(maker).")
        case (nil, let day?): return String(localized: "Made \(day).")
        case (nil, nil): return ""
        }
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
                wellSymbol: "dot.radiowaves.up.forward", title: Text(verbatim: WebhooksModel.display(webhook.url)),
                line: line.isEmpty ? nil : Text(verbatim: line))
            if webhook.maker?.kind == .key, let failure = model.keysFailure {
                OwnerProblem(title: "Couldn’t Check the Webhook’s Key", failure: failure, page: .webhooks, host: host) {
                    Task { await model.load() }
                }
            }
            if let failure = model.rowErrors[webhook.id] { OwnerProblem(title: "Not Changed", failure: failure, page: .webhooks, host: host) }
            if isOwn { settings } else { readOnly }
            deliveries
            SettingsSection("Delete") {
                SettingsRow(verbatim: String(localized: "Delete This Webhook"), line: String(localized: "It stops sending at once.")) {
                    SettingsButton("Delete…", role: .destructive) { model.askToDelete(webhook) }
                }
            }
        }
        .task(id: webhook.id) { await model.loadDeliveries(of: webhook.id) }
    }

    /// A webhook the app made: its address, what it is for, Sending and the events can all be changed.
    @ViewBuilder private var settings: some View {
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
    }

    /// A webhook another app or key made: the app shows what it holds and can end it, and changes nothing, as the server
    /// leaves a change to the maker.
    @ViewBuilder private var readOnly: some View {
        SettingsSection(name: Text("Webhook"), line: Text("Only \(model.maker(of: webhook)) can change it. You can end it.")) {
            SettingsRow(verbatim: String(localized: "Address"), line: webhook.url)
            SettingsRow("For") { SettingsValue(verbatim: model.typeTitle(webhook.typeFilter)) }
            SettingsRow("Sending") {
                let state = model.isSending(webhook)
                SettingsValue(verbatim: WebhooksPage.title(state), dot: WebhooksPage.dot(state))
            }
            SettingsRow("Signing Secret") { SettingsValue(verbatim: "••••" + webhook.secretTail) }
        }
        SettingsSection("Events") {
            if webhook.events.isEmpty {
                SettingsRow("Sends No Events", look: .off)
            }
            ForEach(WebhooksModel.ordered(webhook.events), id: \.self) { name in
                SettingsRow(verbatim: WebhookEvent(rawValue: name)?.title ?? name, size: .compact)
            }
        }
    }

    @ViewBuilder private var deliveries: some View {
        let all = model.deliveries[webhook.id] ?? []
        if let failure = model.deliveryErrors[webhook.id] { OwnerProblem(title: "Not Sent Again", failure: failure, page: .webhooks, host: host) }
        SettingsSection(
            name: Text("Deliveries"),
            line: !isOwn
                ? Text("The latest events sent to this address.")
                : webhook.active
                    ? Text("The latest events sent to this address. Only a failed one can be sent again.")
                    : Text("The latest events sent to this address. A failed one can be sent again once this webhook is on.")
        ) {
            if let failure = model.deliveriesFailure[webhook.id] {
                OwnerProblemRow(
                    title: "Deliveries Couldn’t Be Read", failure: failure, page: .webhooks, host: host,
                    retry: { Task { await model.loadDeliveries(of: webhook.id) } })
            }
            if all.isEmpty {
                if model.deliveriesFailure[webhook.id] == nil {
                    SettingsEmptyCard(symbol: "paperplane", title: Text("No Deliveries"), line: Text("Nothing has been sent to this address yet."))
                }
            } else {
                SettingsSectionTable(
                    rows: showsAllDeliveries ? all : Array(all.prefix(Self.firstDeliveries)),
                    columns: [
                        SettingsTableColumn<WebhookDeliveryInfo>("When", width: SettingsTokens.Metric.Column.time) { Text(verbatim: Self.when($0.created)) },
                        SettingsTableColumn("Event") { Text(verbatim: WebhookEvent(rawValue: $0.event)?.title ?? $0.event) },
                        SettingsTableColumn("Answer", width: SettingsTokens.Metric.Column.label) { Text(verbatim: Self.answer($0)) },
                    ],
                    action: isOwn
                        ? SettingsRowAction(
                            title: "Redeliver", isEnabled: { model.canRedeliver($0, of: webhook) },
                            perform: { delivery in Task { await model.redeliver(delivery, of: webhook) } })
                        : nil,
                    total: all.count, showAll: showsAllDeliveries || all.count <= Self.firstDeliveries ? nil : { showsAllDeliveries = true })
            }
        }
    }

    /// "Today, 14:02", or the day and time.
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let format = DateFormat.stored()
        guard calendar.isDate(date, inSameDayAs: now) else { return DateDisplay.text(of: date, place: .value, format: format, now: now, calendar: calendar) }
        return String(localized: "Today, \(DateDisplay.timeOfDay(of: date, format: format, calendar: calendar))")
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
        SettingsSheet(
            title: Text("New Webhook"), line: Text("\(serverName) sends a request to an address you choose."), isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSheetField(label: "Address", error: model.draftError) {
                    SettingsField(
                        title: "Address", text: $model.draft.address, prompt: "https://", isError: model.draftError != nil,
                        width: nil, onSubmit: { Task { await model.make() } })
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
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Create Webhook", role: .confirm) { Task { await model.make() } }
                .disabled(!model.canMakeDraft)
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
            SettingsButton(copied ? "Copied" : "Copy") {
                guard let secret = model.created?.secret else { return }
                OwnerClipboard.copySecret(secret)
                copied = true
            }
            SettingsButton("Done", role: .confirm) { model.closeSheet() }
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
                    width: nil, onSubmit: { Task { await model.saveAddress() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Change Address", role: .confirm) { Task { await model.saveAddress() } }
                .disabled(!model.canSaveAddress)
        }
    }
}
