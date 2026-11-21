import SwiftUI

/// The Monitoring page: the heartbeat, the error reports and the telemetry the server sends, and the addresses and tokens
/// they go to. A secret is shown as Set or Not Set and never in full; it is changed in a sheet by typing it again.
struct MonitoringPage: View {
    let host: any MarfaSettingsHost
    @State private var model: MonitoringModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: MonitoringModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    /// A page over a model that already holds its state, for a render to draw.
    init(host: any MarfaSettingsHost, model: MonitoringModel) {
        self.host = host
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) { MonitoringSecretSheetView(model: model) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .accessibilityIdentifier("MonitoringPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, !model.isLoaded {
            OwnerFailureState(page: .monitoring, failure: failure, host: host) { Task { await model.load() } }
        } else if model.isLoaded {
            SettingsPageColumn {
                if let notice = model.notice { OwnerNotice(title: "Changed Elsewhere", line: notice, close: { model.dismissNotice() }) }
                SettingsSection("Heartbeat") {
                    switchRow(
                        "Send a Heartbeat", key: "heartbeat_enabled", hasReceiver: model.heartbeatHasReceiver,
                        line: "Marfa asks this address on a schedule, so a monitor notices if it stops.",
                        idle: "Nothing is sent until an address is set.")
                    secretRow(.heartbeatAddress)
                }
                SettingsSection("Error Reports") {
                    switchRow(
                        "Report Errors", key: "error_reporting_enabled", hasReceiver: model.errorReportsHaveReceiver,
                        line: "To PostHog’s error tracking.", idle: "Nothing is sent until the host and token are set.")
                    secretRow(.postHogHost)
                    secretRow(.postHogToken)
                }
                SettingsSection("Telemetry", footer: "Secrets are never shown. To change one, type it again.") {
                    switchRow(
                        "Send Telemetry", key: "telemetry_enabled", hasReceiver: model.telemetryHasReceiver,
                        line: "Traces, logs and metrics. Off keeps the settings.", idle: "Nothing is sent until an address is set.")
                    secretRow(.telemetryAddress)
                    secretRow(.telemetryHeaders)
                }
            }
        } else {
            OwnerLoading()
        }
    }

    /// A switch row. A switch that is on with nothing to send to says so in its line.
    private func switchRow(_ title: LocalizedStringKey, key: String, hasReceiver: Bool, line: LocalizedStringKey, idle: LocalizedStringKey) -> some View {
        SettingsRow(title: Text(title), line: Text(model.isOn(key) && !hasReceiver ? idle : line), error: model.line(key)) {
            SettingsToggle(title: title, isOn: Binding { model.isOn(key) } set: { on in Task { await model.setSwitch(key, on) } })
                .disabled(model.isWriting)
                .accessibilityIdentifier("Monitoring-" + key)
        }
    }

    private func secretRow(_ secret: MonitoringSecret) -> some View {
        let isSet = model.isSet(secret)
        return SettingsRow(verbatim: secret.title, error: model.line(secret.key)) {
            HStack(spacing: 8) {
                SettingsValue(isSet ? "Set" : "Not Set")
                SettingsButton(isSet ? "Change…" : "Set…") { model.begin(secret) }
                    .accessibilityIdentifier("Monitoring-" + secret.rawValue)
                if isSet {
                    SettingsMoreMenu {
                        Button("Remove…", role: .destructive) { model.askToRemove(secret) }
                    }
                    .disabled(model.isWriting)
                    .accessibilityIdentifier("MonitoringMore-" + secret.rawValue)
                }
            }
        }
    }
}

/// The sheet that sets, changes or removes a secret. Its field is secure, so what is typed is never shown, and nothing typed
/// outlives the sheet.
struct MonitoringSecretSheetView: View {
    @Bindable var model: MonitoringModel

    var body: some View {
        if let sheet = model.sheet {
            SettingsSheet(title: title(sheet), line: line(sheet).map { Text(verbatim: $0) }) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sheet.fields) { field in
                        SettingsSheetField(
                            verbatim: field.title, error: field == sheet.fields.last ? sheet.error : nil
                        ) {
                            SettingsField(
                                title: LocalizedStringKey(field.title),
                                text: Binding { model.sheet?.inputs[field.key] ?? "" } set: { model.sheet?.inputs[field.key] = $0 },
                                prompt: model.isSet(field) && model.isSecure(field) ? String(localized: "Type it again to change it") : field.prompt,
                                isError: sheet.error != nil, isSecure: model.isSecure(field), width: nil,
                                onSubmit: { Task { await model.save() } })
                            .accessibilityIdentifier("MonitoringSecretField-" + field.rawValue)
                        }
                    }
                }
            } buttons: {
                Spacer(minLength: 0)
                SettingsButton("Cancel") { model.close() }
                SettingsButton("Save") { Task { await model.save() } }
                    .disabled(!sheet.hasInput || model.isWriting)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("MonitoringSecretSave")
            }
        }
    }

    private func title(_ sheet: MonitoringSecretSheet) -> Text {
        model.isSet(sheet.secret) ? Text("Change \(sheet.secret.title)") : Text("Set \(sheet.secret.title)")
    }

    /// What the sheet says about what is typed, where the server never shows it again.
    private func line(_ sheet: MonitoringSecretSheet) -> String? {
        guard sheet.fields.contains(where: model.isSecure) else { return nil }
        if sheet.fields.count > 1 { return String(localized: "The new host and token are never shown again.") }
        switch sheet.secret {
        case .heartbeatAddress, .telemetryAddress, .postHogHost: return String(localized: "The new address is never shown again.")
        case .postHogToken, .telemetryHeaders: return String(localized: "The new value is never shown again.")
        }
    }
}
