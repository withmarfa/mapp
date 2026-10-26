import SwiftUI

/// The This Marfa page of Settings: the connected server's own settings, as the server last gave them, edited as a
/// draft and sent by Save. The page says what an empty field means, and asks first where a change keeps things for
/// less time.
struct ThisMarfaSettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.openURL) private var openURL

    private var model: InstanceSettingsModel { libraries.instanceSettings }

    var body: some View {
        Form {
            if libraries.host.configuredConnection == nil {
                Section {
                    Text("Connect to a Marfa server in Library to see and change its settings here.")
                        .foregroundStyle(.secondary)
                }
            } else if !model.isAvailable {
                unavailable
            } else {
                ThisMarfaFields(model: model)
            }
        }
        .settingsForm()
        .accessibilityIdentifier("ThisMarfaSettings")
        .task(id: libraries.host.configuredConnection?.address) { await model.load() }
        .confirmationDialog(
            "Keep things for less time?", isPresented: Binding { model.pending != nil } set: { if !$0 { model.cancelPending() } },
            presenting: model.pending
        ) { pending in
            Button("Shorten and Save", role: .destructive) { Task { await model.confirm(pending) } }
        } message: { pending in
            Text(pending.shortenings.map(InstanceWording.consequence).joined(separator: "\n\n"))
        }
    }

    /// Nothing can be shown: still reading, or the server said why not.
    @ViewBuilder private var unavailable: some View {
        Section {
            if let failure = model.failure {
                Text(failure.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if failure == .notPermitted, let address = libraries.host.configuredConnection?.address {
                    LabeledContent("Console") {
                        Button("Open in Browser") { openURL(address) }
                            .accessibilityIdentifier("ThisMarfaOpenConsole")
                    }
                } else {
                    Button("Try Again") { Task { await model.load() } }
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("ThisMarfaTryAgain")
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the server’s settings…").foregroundStyle(.secondary)
                }
            }
        } header: {
            if model.failure == .notPermitted { Text("Settings unavailable") } else { Text("Settings") }
        }
    }
}

/// The fields, once the server has answered.
private struct ThisMarfaFields: View {
    @Bindable var model: InstanceSettingsModel

    var body: some View {
        Group {
            Section {
                field(.name, prompt: Text("Marfa"), unit: nil)
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in the sidebar and wherever MAPP names this server. Empty uses “Marfa”.")
            }
            Section {
                field(.trashRetentionDays, unit: Text("days"))
            } header: {
                Text("Recently Deleted")
            } footer: {
                Text("Deleted items stay in Recently Deleted this long, then the server removes them for good, with their history. 0 keeps them with no limit. Empty uses the server’s default, 60 days, unless whoever runs the server has set another.")
            }
            Section {
                field(.versionRecentDays, unit: Text("days"))
                field(.versionDailyDays, unit: Text("days"))
                field(.versionWeeklyDays, unit: Text("days"))
                field(.versionMaxVersions, unit: Text("versions"))
            } header: {
                Text("Version History")
            } footer: {
                Text("The server keeps every version of an item for the first period, then one a day, then one a week, and removes older ones. Each period must be at least as long as the one before. A type can set its own policy, which wins. Empty uses the server’s defaults, 30, 90 and 365 days and 500 versions, unless whoever runs the server has set others.")
            }
            Section {
                status
                HStack(spacing: 8) {
                    Button("Revert") { model.revert() }
                        .disabled(!model.hasEdits || model.isSaving)
                        .accessibilityIdentifier("ThisMarfaRevert")
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("ThisMarfaSave")
                    if model.isSaving || model.isLoading { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    /// One setting's field: its title, the typed value, the unit, then why the value can't be sent.
    @ViewBuilder private func field(_ setting: InstanceSetting, prompt: Text? = nil, unit: Text?) -> some View {
        let text = Binding { model.draft[setting] ?? "" } set: { model.draft[setting] = $0 }
        let fallback = prompt ?? Text(setting.documentedDefault.map { String($0) } ?? "")
        LabeledContent(setting.title) {
            HStack(spacing: 6) {
                TextField(setting.title, text: text, prompt: fallback)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: setting.isNumber ? 110 : .infinity)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await model.save() } }
                    .accessibilityIdentifier("ThisMarfa" + setting.rawValue)
                if let unit { unit.foregroundStyle(.secondary) }
            }
        }
        .disabled(model.isSaving)
        if let problem = model.problems[setting] {
            Text(problem.message)
                .foregroundStyle(.red)
                .accessibilityIdentifier("ThisMarfaProblem" + setting.rawValue)
        }
    }

    /// What the last save did, or what is wrong now, in plain words.
    @ViewBuilder private var status: some View {
        if let elsewhere = model.elsewhereMessage {
            Text(elsewhere).fixedSize(horizontal: false, vertical: true)
        }
        if let failure = model.failure {
            Text(failure.message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            if failure == .unreachable {
                Text("These are the settings as the server last gave them.").foregroundStyle(.secondary)
                Button("Try Again") { Task { await model.load() } }
                    .disabled(model.isLoading)
            }
        }
        if !model.saved.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved. The server now has:").foregroundStyle(.secondary)
                ForEach(model.saved, id: \.self) { Text($0) }
            }
            .accessibilityIdentifier("ThisMarfaSaved")
        }
    }
}
