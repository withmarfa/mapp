import Marfa
import SwiftUI

/// The Connectors page: the connector of each installed plugin, with how it stands, each opening a page of its own with Pause,
/// Run Now, its settings, what it brings and, for one that declares it, its vendor sign-in. Installing a plugin and adding a
/// machine are other pages' work, so this page offers neither.
struct ConnectorsPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: ConnectorsModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

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

    private var openName: String? {
        guard let id = subpage?.id, id.hasPrefix("connector:") else { return nil }
        return String(id.dropFirst(10))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.closeSheet() }) {
                ConnectorSecretSheet(model: model)
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
            .accessibilityIdentifier("ConnectorsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .connectors, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let name = openName {
            if let entry = model.entry(name) {
                ConnectorDetail(model: model, entry: entry, host: host)
                    .task(id: name) { await model.reload(name) }
                    .task(id: entry.control?.runRequested) { await model.followRun(name) }
            } else {
                SettingsPageState(
                    symbol: "arrow.triangle.2.circlepath", title: Text("This Connector Is Gone"),
                    line: Text("Its plugin was removed, here or somewhere else."), action: ("Back", back))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if model.entries.isEmpty {
                SettingsSection(name: Text("Connectors")) {
                    SettingsEmptyCard(
                        symbol: "arrow.triangle.2.circlepath", title: Text("No Connectors"),
                        line: Text("A connector comes with its plugin."))
                }
            } else {
                SettingsSection(
                    name: Text("Connectors"), footer: Text("A connector comes with its plugin. Its settings and secrets are kept in \(host.serverName).")
                ) {
                    ForEach(model.entries) { entry in
                        let health = model.health(of: entry)
                        SettingsLinkRow(
                            verbatim: entry.summary.title, line: line(of: entry), lead: .well(host.markGlyph(entry.summary.mark)),
                            value: ConnectorWording.title(health), dot: Self.dot(health), lines: 1
                        ) { push(Self.subpage(for: entry.summary)) }
                    }
                }
            }
        }
    }

    private func line(of entry: ConnectorsModel.Entry) -> String {
        guard let name = model.hostName(of: entry) else { return entry.summary.description }
        return String(localized: "\(entry.summary.description) Runs on \(name).")
    }

    static func dot(_ health: ConnectorHealth) -> Color {
        switch health {
        case .ran: SettingsTokens.ok
        case .needsSetup, .silent, .problems, .lastRunFailed, .unread: SettingsTokens.warning
        case .paused, .noMachine, .waiting, .runRequested, .notRunYet: SettingsTokens.tertiaryText
        }
    }
}

/// One connector's page.
private struct ConnectorDetail: View {
    let model: ConnectorsModel
    let entry: ConnectorsModel.Entry
    let host: any MarfaSettingsHost

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
        if model.hosts.isEmpty {
            SettingsRow("Runs On", line: "No machine is linked to run connectors yet.") { SettingsValue("No Machine") }
        } else {
            SettingsRow("Runs On") {
                SettingsPopUp(
                    title: "Runs On", selection: Binding<String?> { entry.control?.host } set: { id in
                        if let id { Task { await model.assign(summary.name, toHost: id) } }
                    }
                ) {
                    if entry.control?.host == nil { Text("No Machine").tag(String?.none) }
                    if let held = entry.control?.host, model.host(held) == nil {
                        Text("Another Machine").tag(String?.some(held))
                    }
                    if entry.control?.host == nil || !model.hosts.isEmpty { Divider() }
                    ForEach(model.hosts) { Text(verbatim: $0.name).tag(String?.some($0.id)) }
                }
                .disabled(isWorking)
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
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    SettingsButton(setting.isSet || setting.unreadable ? "Change…" : "Set…") { model.beginSecret(setting, in: summary.name) }
                    if setting.isSet || setting.unreadable {
                        SettingsMoreMenu {
                            Button("Remove…", role: .destructive) { model.askToRemoveSecret(setting, in: summary.name) }
                        }
                    }
                }
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
                    SettingsRow(
                        verbatim: ConnectorWording.kindTitle(kind.name),
                        line: ConnectorWording.kindLine(kind, typeName: model.typeName(kind.type)), size: .compact)
                }
            }
        }
    }
}

/// The sheet that sets or changes a secret. Its field is secure, and nothing typed outlives the sheet.
private struct ConnectorSecretSheet: View {
    @Bindable var model: ConnectorsModel

    var body: some View {
        if let sheet = model.sheet {
            SettingsSheet(
                title: sheet.isSet ? Text("Change \(sheet.label)") : Text("Set \(sheet.label)"),
                line: Text("The new value is never shown again.")
            ) {
                SettingsSheetField(verbatim: sheet.label, error: model.secretError) {
                    SettingsField(
                        verbatim: sheet.label, text: $model.secretDraft,
                        prompt: sheet.isSet ? String(localized: "Type it again to change it") : nil,
                        isError: model.secretError != nil, isSecure: true, width: nil, onSubmit: { Task { await model.saveSecret() } })
                    .accessibilityIdentifier("ConnectorSecretField")
                }
            } buttons: {
                Spacer(minLength: 0)
                SettingsButton("Cancel") { model.closeSheet() }
                SettingsButton("Save") { Task { await model.saveSecret() } }
                    .disabled(!model.canSaveSecret).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ConnectorSecretSave")
            }
        }
    }
}
