import SwiftUI

/// The Overview page: the server's head card, then This Marfa's own settings as the server last gave them, edited as a
/// draft and sent by Save. A value the server refuses keeps what was typed, with the red ring and one line.
struct OverviewPage: View {
    let host: any MarfaSettingsHost

    private var model: InstanceSettingsModel { host.instanceSettings }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(
                symbol: MarfaSettingsPage.overview.symbol, tone: MarfaSettingsPage.overview.tone,
                title: Text(verbatim: host.serverName), line: host.serverAddress.map { Text(verbatim: $0) })
            if model.isAvailable {
                ThisMarfaFields(model: model)
            } else {
                unavailable
            }
        }
        .task(id: host.serverAddress) { await model.load() }
        .confirmationDialog(
            "Keep things for less time?", isPresented: Binding { model.pending != nil } set: { if !$0 { model.cancelPending() } },
            presenting: model.pending
        ) { pending in
            Button("Shorten and Save", role: .destructive) { Task { await model.confirm(pending) } }
        } message: { pending in
            Text(pending.shortenings.map(InstanceWording.consequence).joined(separator: "\n\n"))
        }
        .accessibilityIdentifier("OverviewPage")
    }

    /// Nothing can be shown yet: still reading, or the server said why not.
    @ViewBuilder private var unavailable: some View {
        SettingsSection("This Marfa") {
            if let failure = model.failure {
                SettingsRow(verbatim: failure.message, lead: .tint("exclamationmark.triangle", .orange)) {
                    if failure != .unsupported && failure != .notPermitted {
                        SettingsButton("Try Again") { Task { await model.load() } }
                            .disabled(model.isLoading)
                    }
                }
            } else {
                SettingsRow("Reading the server’s settings…") { ProgressView().controlSize(.small) }
            }
        }
    }
}

/// The fields, once the server has answered.
private struct ThisMarfaFields: View {
    @Bindable var model: InstanceSettingsModel

    var body: some View {
        Group {
            SettingsSection(
                "This Marfa", footer: "Shown in the sidebar and wherever MAPP names this server. Empty uses “Marfa”.") {
                field(.name, prompt: "Marfa", unit: nil)
            }
            SettingsSection(
                "Recently Deleted",
                footer: "Deleted items stay in Recently Deleted this long, then the server permanently deletes them, with their history. 0 keeps them with no limit. Empty uses the server’s default."
            ) {
                field(.trashRetentionDays, unit: "days")
            }
            SettingsSection(
                "Version History",
                footer: "The server keeps every version for the first period, then one a day, then one a week. Each period must be at least as long as the one before. A type’s own policy wins. Empty uses the server’s defaults."
            ) {
                field(.versionRecentDays, unit: "days")
                field(.versionDailyDays, unit: "days")
                field(.versionWeeklyDays, unit: "days")
                field(.versionMaxVersions, unit: "versions")
            }
            footer
        }
    }

    /// The server refused what was sent: the ring goes round every field that was changed.
    private var refusal: String? {
        if case .refused(let reason)? = model.failure { reason } else { nil }
    }

    private var isRefused: Bool { refusal != nil }

    /// The one field the refusal is about, where only one was changed: its line is under its title. With several changed the
    /// line is under the buttons.
    private var refusedSetting: InstanceSetting? {
        let edited = InstanceSetting.allCases.filter(model.isEdited)
        return isRefused && edited.count == 1 ? edited.first : nil
    }

    /// One setting's row: its title, the typed field with its unit inside, and why the value can't be sent.
    @ViewBuilder private func field(_ setting: InstanceSetting, prompt: String? = nil, unit: LocalizedStringKey?) -> some View {
        let text = Binding { model.draft[setting] ?? "" } set: { model.draft[setting] = $0 }
        let fallback = prompt ?? setting.documentedDefault.map { String($0) }
        let problem = model.problems[setting]
        let ring = problem != nil || (isRefused && model.isEdited(setting))
        SettingsRow(verbatim: setting.title, error: problem?.message ?? (setting == refusedSetting ? refusal : nil)) {
            Group {
                if let unit {
                    SettingsNumberField(
                        title: LocalizedStringKey(setting.title), text: text, unit: unit, prompt: fallback, isError: ring,
                        onSubmit: { Task { await model.save() } })
                } else {
                    SettingsField(
                        title: LocalizedStringKey(setting.title), text: text, prompt: fallback, isError: ring,
                        onSubmit: { Task { await model.save() } })
                }
            }
            .disabled(model.isSaving)
            .accessibilityIdentifier("ThisMarfa" + setting.rawValue)
        }
    }

    /// What the last save did or what is wrong now, in plain words, then Revert and Save.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = statusLine {
                Text(verbatim: message.text)
                    .settingsFont(.line)
                    .foregroundStyle(message.isError ? SettingsTokens.errorRed : SettingsTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.saved.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved. The server now has:")
                    ForEach(model.saved, id: \.self) { Text(verbatim: $0) }
                }
                .settingsFont(.line)
                .foregroundStyle(SettingsTokens.secondaryText)
                .accessibilityIdentifier("ThisMarfaSaved")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.isSaving || model.isLoading { ProgressView().controlSize(.small) }
                if case .unreachable? = model.failure {
                    SettingsButton("Try Again") { Task { await model.load() } }.disabled(model.isLoading)
                }
                SettingsButton("Revert") { model.revert() }
                    .disabled(!model.hasEdits || model.isSaving)
                    .accessibilityIdentifier("ThisMarfaRevert")
                SettingsButton("Save") { Task { await model.save() } }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("ThisMarfaSave")
            }
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
    }

    private var statusLine: (text: String, isError: Bool)? {
        if let elsewhere = model.elsewhereMessage { return (elsewhere, false) }
        if model.serverChanged { return (InstanceConfigFailure.instanceChanged.message, false) }
        if let failure = model.failure, refusedSetting == nil { return (failure.message, true) }
        return nil
    }
}
