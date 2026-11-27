import Marfa
import SwiftUI

/// The Connectors page: the connector of each installed plugin, with how it stands, each opening a page of its own with Pause,
/// Run Now, its settings, what it brings and, for one that declares it, its vendor sign-in. Add a Connector… puts a connector
/// no machine runs on one, making the machine's one-time link where it is new. Installing a plugin is the Plugins page's work.
struct ConnectorsPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: ConnectorsModel
    @State private var mappings = ConnectorMappingModels()
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: ConnectorsModel(context: OwnerContext(host: host)))
    }

    static func subpage(for summary: PluginConnectorSummary) -> SettingsSubpage { subpage(plugin: summary.name, title: summary.title) }

    /// The page of the connector of the plugin `name`, for another page to open.
    static func subpage(plugin name: String, title: String) -> SettingsSubpage {
        SettingsSubpage(id: "connector:" + name, title: title)
    }

    static func subpage(for kind: ConnectorKind, of summary: PluginConnectorSummary) -> SettingsSubpage {
        SettingsSubpage(id: "mapping:\(summary.name)/\(kind.name)", title: ConnectorWording.kindTitle(kind.name))
    }

    private var openName: String? {
        guard let id = subpage?.id, id.hasPrefix("connector:") else { return nil }
        return String(id.dropFirst(10))
    }

    /// The connector and kind a mapping page names.
    private var openMapping: (plugin: String, kind: String)? {
        guard let id = subpage?.id, id.hasPrefix("mapping:") else { return nil }
        let parts = id.dropFirst(8).split(separator: "/", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil || model.adding != nil, dismiss: dismissSheet) {
                if let adding = model.adding {
                    AddConnectorSheet(model: adding, serverName: host.serverName, close: { model.closeAdding() })
                } else {
                    ConnectorSecretSheet(model: model)
                }
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
            .toolbar {
                if subpage == nil, model.failure == nil, model.hasLoaded {
                    ToolbarItem(placement: .primaryAction) {
                        SettingsButton("Add a Connector…") { model.beginAdding() }
                            .disabled(model.unplaced.isEmpty)
                    }
                }
            }
            .accessibilityIdentifier("ConnectorsPage")
    }

    private func dismissSheet() {
        if model.adding != nil { model.closeAdding() } else { model.closeSheet() }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .connectors, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let open = openMapping {
            if let entry = model.entry(open.plugin), let kind = entry.summary.kinds.first(where: { $0.name == open.kind }) {
                ConnectorMappingPage(
                    model: mappings.model(for: entry.summary, context: OwnerContext(host: host)), kind: kind,
                    previewBlock: Self.previewBlock(entry, title: entry.summary.title), host: host)
            } else {
                SettingsPageState(
                    symbol: "arrow.triangle.2.circlepath", title: Text("This Connector Is Gone"),
                    line: Text("Its plugin was removed, here or somewhere else."), action: ("Back", { navigation?.back() }))
            }
        } else if let name = openName {
            if let entry = model.entry(name) {
                ConnectorDetail(model: model, entry: entry, host: host)
                    .task(id: name) { await model.reload(name) }
                    .task(id: entry.control?.runRequested) { await model.followRun(name) }
            } else {
                SettingsPageState(
                    symbol: "arrow.triangle.2.circlepath", title: Text("This Connector Is Gone"),
                    line: Text("Its plugin was removed, here or somewhere else."), action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if model.entries.isEmpty {
                SettingsSection(
                    name: nil,
                    footer: Text("A connector comes with its plugin. Its settings and secrets are kept in this Marfa.")
                ) {
                    SettingsEmptyCard(
                        symbol: "arrow.triangle.2.circlepath", title: Text("No Connectors"),
                        line: Text("A connector comes with its plugin."))
                }
            } else {
                SettingsSection(
                    name: nil,
                    footer: Text("A connector comes with its plugin. Its settings and secrets are kept in this Marfa.")
                ) {
                    if let failure = model.hostsFailure {
                        OwnerProblemRow(
                            title: "Couldn’t Read Connector Machines", failure: failure, page: .connectors, host: host,
                            retry: { Task { await model.load() } })
                    }
                    ForEach(model.entries) { entry in
                        let health = model.health(of: entry)
                        SettingsLinkRow(
                            verbatim: entry.summary.title, line: line(of: entry), lead: .well(host.markGlyph(entry.summary.mark)),
                            value: ConnectorWording.title(health), dot: Self.dot(health), lines: 1
                        ) { navigation?.push(Self.subpage(for: entry.summary)) }
                    }
                }
            }
        }
    }

    private func line(of entry: ConnectorsModel.Entry) -> String {
        guard let name = model.hostName(of: entry) else { return entry.summary.description }
        return String(localized: "\(entry.summary.description) Runs on \(name).")
    }

    /// Why no preview can be asked for now, or nil where one can: a paused connector and one with no machine answer none.
    static func previewBlock(_ entry: ConnectorsModel.Entry, title: String) -> String? {
        guard let control = entry.control else { return nil }
        if control.paused { return String(localized: "Resume \(title) to see one. A paused connector answers no preview.") }
        if control.host == nil { return String(localized: "Choose the machine that runs \(title) to see one.") }
        return nil
    }

    static func dot(_ health: ConnectorHealth) -> Color {
        switch health {
        case .ran: SettingsTokens.ok
        case .needsSetup, .silent, .problems, .lastRunFailed, .unread: SettingsTokens.warning
        case .paused, .noMachine, .waiting, .runRequested, .notRunYet: SettingsTokens.tertiaryText
        }
    }
}

/// The mapping models of the connectors whose mapping page was opened, so Back and Forward return to the same draft.
@MainActor final class ConnectorMappingModels {
    private var held: [String: ConnectorMappingModel] = [:]

    func model(for summary: PluginConnectorSummary, context: OwnerContext) -> ConnectorMappingModel {
        if let model = held[summary.name] { return model }
        let model = ConnectorMappingModel(context: context, plugin: summary)
        held[summary.name] = model
        return model
    }
}

/// One connector's page.
private struct ConnectorDetail: View {
    let model: ConnectorsModel
    let entry: ConnectorsModel.Entry
    let host: any MarfaSettingsHost
    @Environment(\.settingsNavigation) private var navigation

    private var summary: PluginConnectorSummary { entry.summary }
    private var health: ConnectorHealth { model.health(of: entry) }
    private var isWorking: Bool { model.working.contains(summary.name) }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(
                lead: SettingsWell(size: SettingsTokens.Metric.headTile) { host.markGlyph(summary.mark) }, title: Text(verbatim: summary.title),
                line: headLine.map { Text(verbatim: $0) }
            ) {
                SettingsButton("Run Now") { Task { await model.runNow(summary.name) } }
                    .disabled(isWorking || entry.control == nil)
            }
            if let failure = model.rowErrors[summary.name] {
                OwnerProblem(title: "Not Changed", failure: failure, page: .connectors, host: host)
            }
            problems
            running
            settings
            brings
            plugin
        }
    }

    private var headLine: String? {
        let line = ConnectorWording.head(hostName: model.hostName(of: entry), run: entry.registration?.lastRun)
        return line.isEmpty ? summary.description : line
    }

    /// What the connector reports as wrong, as it wrote it.
    @ViewBuilder private var problems: some View {
        if let problems = entry.registration?.problems, !problems.isEmpty {
            SettingsSection(name: Text("Needs Attention")) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    SettingsProblemRow(title: Text(verbatim: problem), actions: [])
                }
            }
        }
    }

    // MARK: Running

    private var running: some View {
        SettingsSection(
            name: Text("Running"),
            footer: Text("Pause, Resume and Run Now are kept on \(host.serverName). The connector follows them at its next run.")
        ) {
            SettingsRow(
                verbatim: String(localized: "Status"),
                line: ConnectorWording.line(health, hostName: model.hostName(of: entry), labels: model.labels(of: entry))
            ) {
                SettingsValue(verbatim: ConnectorWording.title(health), dot: ConnectorsPage.dot(health))
            }
            SettingsRow("Pause", line: "A paused connector does nothing until you resume it.") {
                SettingsToggle(title: "Pause", isOn: Binding { entry.control?.paused ?? false } set: { paused in
                    Task { await model.setPaused(paused, for: summary.name) }
                })
                .disabled(isWorking || entry.control == nil)
            }
            machine
            signIn
        }
    }

    @ViewBuilder private var machine: some View {
        if let failure = model.hostsFailure {
            OwnerProblemRow(
                title: "Couldn’t Read Connector Machines", failure: failure, page: .connectors, host: host,
                retry: { Task { await model.reload(summary.name) } })
        }
        let held = model.hostID(of: entry)
        if model.hosts.isEmpty && held == nil {
            if model.hostsFailure == nil {
                SettingsRow("Runs On", line: "No machine runs connectors yet. Add a Connector… on Connectors links one.") { SettingsValue("No Machine") }
            }
        } else {
            SettingsRow("Runs On") {
                SettingsPopUp(
                    title: "Runs On", selection: Binding<String?> { held } set: { id in
                        if let id {
                            Task { await model.assign(summary.name, toHost: id) }
                        } else {
                            Task { await model.chooseNoMachine(for: summary.name) }
                        }
                    }
                ) {
                    Text("No Machine").tag(String?.none)
                    if let held, model.host(held) == nil {
                        Text("Another Machine").tag(String?.some(held))
                    }
                    if !model.hosts.isEmpty { Divider() }
                    ForEach(model.hosts) { Text(verbatim: $0.name).tag(String?.some($0.id)) }
                }
                .disabled(isWorking || model.hostsFailure != nil)
            }
        }
    }

    /// The vendor sign-in, only for a connector whose plugin declares one.
    @ViewBuilder private var signIn: some View {
        if let declared = summary.signIn {
            let provider = ConnectorWording.provider(declared.provider)
            let isSignedIn = model.isSignedIn(entry)
            let signingIn = model.signingIn == summary.name
            SettingsRow(
                verbatim: isSignedIn ? String(localized: "Signed In to \(provider)") : String(localized: "Sign In to \(provider)"),
                line: String(localized: "Through \(host.serverName)."), error: model.signInProblems[summary.name]
            ) {
                SettingsButton(signingIn ? "Waiting…" : (isSignedIn ? "Sign In Again…" : "Sign In…")) {
                    Task {
                        await model.signIn(summary.name, returningTo: host.webSignInReturn) { await host.showWebSignIn(at: $0) }
                    }
                }
                .disabled(model.signingIn != nil)
            }
        }
    }

    // MARK: Settings

    @ViewBuilder private var settings: some View {
        let shown = model.shownSettings(of: entry)
        if !shown.isEmpty {
            SettingsSection("Settings") {
                ForEach(shown) { setting in row(setting) }
            }
        }
    }

    @ViewBuilder private func row(_ setting: ConnectorSetting) -> some View {
        let key = ConnectorsModel.key(summary.name, setting.name)
        let missing = entry.settings?.missing.contains(setting.name) ?? false
        let error = model.settingErrors[key] ?? (missing ? String(localized: "Needed before it can run.") : nil)
        if setting.secret {
            SettingsRow(verbatim: setting.label, line: secretLine(setting), error: error) {
                SettingsButton(setting.isSet || setting.unreadable ? "Change…" : "Set…") { model.beginSecret(setting, in: summary.name) }
            }
        } else {
            switch setting.kind {
            case .boolean:
                SettingsRow(verbatim: setting.label, error: error) {
                    SettingsToggle(verbatim: setting.label, isOn: Binding {
                        if case .flag(let on)? = setting.value { on } else { false }
                    } set: { on in
                        Task { await model.set(.flag(on), for: setting, in: summary.name) }
                    })
                }
            case .choice:
                SettingsRow(verbatim: setting.label, error: error) {
                    SettingsPopUp(
                        verbatim: setting.label, selection: Binding<String?> {
                            if case .text(let text)? = setting.value { text } else { nil }
                        } set: { choice in
                            Task { await model.set(choice.map { .text($0) }, for: setting, in: summary.name) }
                        }
                    ) {
                        if !setting.required { Text("Not Set").tag(String?.none) }
                        ForEach(setting.choices, id: \.self) { Text(verbatim: ConnectorWording.kindTitle($0)).tag(String?.some($0)) }
                    }
                }
            case .number:
                SettingsRow(verbatim: setting.label, error: error) {
                    SettingsNumberField(
                        verbatim: setting.label,
                        text: Binding { model.text(of: setting, in: summary.name) } set: { model.drafts[key] = $0 },
                        unit: nil,
                        isError: error != nil && model.settingErrors[key] != nil,
                        onSubmit: { Task { await model.commit(setting, in: summary.name) } },
                        onEndEditing: { Task { await model.commit(setting, in: summary.name) } })
                }
            case .text:
                SettingsRow(verbatim: setting.label, error: error) {
                    SettingsField(
                        verbatim: setting.label,
                        text: Binding { model.text(of: setting, in: summary.name) } set: { model.drafts[key] = $0 },
                        isError: error != nil && model.settingErrors[key] != nil,
                        onSubmit: { Task { await model.commit(setting, in: summary.name) } },
                        onEndEditing: { Task { await model.commit(setting, in: summary.name) } })
                }
            }
        }
    }

    /// A secret is only Set or Not Set: the server never shows it, and neither does this page.
    private func secretLine(_ setting: ConnectorSetting) -> String {
        if setting.unreadable { return String(localized: "Can’t be read. Set it again.") }
        return setting.isSet ? String(localized: "Set. Never shown.") : String(localized: "Not set.")
    }

    // MARK: The plugin

    private var plugin: some View {
        SettingsSection("Plugin") {
            SettingsRow(
                verbatim: String(localized: "From the \(summary.title) Plugin"), line: String(localized: "Removing the plugin removes the connector.")
            ) {
                SettingsButton("Show Plugin") { host.show(.plugins, subpage: PluginsPage.subpage(named: summary.name, title: summary.title)) }
            }
        }
    }

    // MARK: What it brings

    @ViewBuilder private var brings: some View {
        if !summary.kinds.isEmpty {
            SettingsSection("What It Brings") {
                ForEach(summary.kinds) { kind in
                    SettingsLinkRow(
                        verbatim: ConnectorWording.kindTitle(kind.name),
                        line: ConnectorWording.kindLine(kind, typeName: model.typeName(kind.type)), lines: 1
                    ) { navigation?.push(ConnectorsPage.subpage(for: kind, of: summary)) }
                }
            }
        }
    }
}

/// The sheet that sets or changes a secret. Its field is secure, and nothing typed outlives the sheet. A secret held can be
/// removed from here, after the owner is asked.
struct ConnectorSecretSheet: View {
    @Bindable var model: ConnectorsModel

    var body: some View {
        if let sheet = model.sheet {
            SettingsSheet(
                title: sheet.hasValue ? Text("Change \(sheet.label)") : Text("Set \(sheet.label)"),
                line: Text("The new value is never shown again.")
            ) {
                SettingsSheetField(verbatim: sheet.label, error: model.secretError) {
                    SettingsField(
                        verbatim: sheet.label, text: $model.secretDraft,
                        prompt: sheet.hasValue ? String(localized: "Type it again to change it") : nil,
                        isError: model.secretError != nil, isSecure: true, width: nil, onSubmit: { Task { await model.saveSecret() } })
                    .accessibilityIdentifier("ConnectorSecretField")
                }
            } leading: {
                if sheet.hasValue {
                    SettingsButton("Remove…", role: .destructive) { model.askToRemoveSecret() }.disabled(model.isSavingSecret)
                }
            } buttons: {
                SettingsButton("Cancel") { model.closeSheet() }
                SettingsButton("Save", role: .confirm) { Task { await model.saveSecret() } }
                    .disabled(!model.canSaveSecret)
                    .accessibilityIdentifier("ConnectorSecretSave")
            }
        }
    }
}

/// Add a Connector: which connector and where it runs, then, for a machine not linked yet, the command to paste there with
/// its one-time link. The link is shown only here: it is never kept, and closing the sheet drops it.
struct AddConnectorSheet: View {
    @Bindable var model: AddConnectorModel
    let serverName: String
    let close: () -> Void

    /// The connector was put on a machine, or the machine made for it was kept with nothing on it.
    private var isPlaced: Bool { model.placed != nil || model.kept != nil }

    var body: some View {
        SettingsSheet(title: Text("Add a Connector"), line: Text("From a plugin you’ve installed.")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSection("Which and Where") {
                    SettingsRow("Connector") {
                        SettingsPopUp(title: "Connector", selection: $model.plugin) {
                            ForEach(model.candidates) { Text(verbatim: $0.title).tag($0.name) }
                        }
                        .disabled(isPlaced || model.isWorking)
                    }
                    SettingsRow("Runs", line: "Where it can reach what it reads.", error: model.place == .newMachine ? nil : model.error) {
                        SettingsPopUp(title: "Runs", selection: $model.place) {
                            ForEach(model.hosts) { Text("On \($0.name)").tag(AddConnectorModel.Place.host($0.id)) }
                            if !model.hosts.isEmpty { Divider() }
                            Text("On Another Machine").tag(AddConnectorModel.Place.newMachine)
                        }
                        .disabled(isPlaced || model.isWorking)
                    }
                    if model.place == .newMachine && !isPlaced {
                        SettingsRow("Machine Name", line: "What \(serverName) calls it.", error: model.error, lines: nil) {
                            SettingsField(title: "Machine Name", text: $model.machineName, isError: model.error != nil, onSubmit: add)
                        }
                    }
                }
                if let kept = model.kept {
                    SettingsSection(name: Text("On That Machine")) {
                        SettingsRow(
                            "“\(kept.name)” was added but runs nothing yet.",
                            line: "Choose it in Runs next time, or remove it in Terminal with \(AddConnectorModel.removeCommand(kept)).", lines: nil
                        ) {
                            SettingsButton("Copy") { OwnerClipboard.copyText(AddConnectorModel.removeCommand(kept)) }
                        }
                    }
                }
                if let placed = model.placed {
                    SettingsSection(name: Text("On That Machine"), footer: Text("The link works once and gives this machine its own key.")) {
                        if let link = model.liveLink() {
                            if let command = AddConnectorModel.command(for: link.link) {
                                // Copy Command is the only way out: the text can't be selected, and the accessibility tree
                                // names it without reading it out.
                                SettingsStackRow(title: Text("Command to Paste There")) {
                                    SettingsReadOnlyValue(text: command, isSelectable: false)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(Text("Command to Paste There"))
                                }
                            } else {
                                SettingsRow("Command to Paste There", line: "\(serverName) answered a link that can’t be pasted safely.") { EmptyView() }
                            }
                        } else if placed.madeLink {
                            SettingsRow("Command to Paste There", line: "Its link has ended.", error: model.error) { newLink }
                        } else {
                            SettingsRow(
                                "Command to Paste There", line: "“\(placed.host.name)” isn’t linked yet. A new link ends the one it was given.",
                                error: model.error
                            ) { newLink }
                        }
                    }
                    .task(id: placed.link?.expires) { await model.endLinkWhenDue() }
                }
            }
        } buttons: {
            if model.placed != nil {
                CopyCommandButton(model: model)
                SettingsButton("Done", role: .confirm, action: close)
            } else if model.kept != nil {
                SettingsButton("Done", role: .confirm, action: close)
            } else {
                SettingsButton("Cancel", action: close).disabled(model.isWorking)
                SettingsButton("Add Connector", role: .confirm, action: add).disabled(!model.canAdd)
            }
        }
    }

    private var newLink: some View {
        SettingsButton("New Link") { Task { await model.renewLink() } }.disabled(model.isWorking)
    }

    private func add() { Task { await model.add() } }
}

/// Copies the command while its link works, concealed from clipboard managers and taken off the clipboard after a minute.
private struct CopyCommandButton: View {
    let model: AddConnectorModel
    @State private var copied = false

    var body: some View {
        SettingsButton(copied ? "Copied" : "Copy Command") { copied = model.copyCommand() }
            .disabled(model.command == nil)
    }
}
