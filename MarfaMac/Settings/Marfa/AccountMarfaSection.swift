import Marfa
import SwiftUI

/// Server name, release and update controls on Account.
struct AccountMarfaSection: View {
    let host: any MarfaSettingsHost
    @State private var copied = false
    @State private var asksToUpdate = false

    init(host: any MarfaSettingsHost) {
        self.host = host
    }

    private var settings: InstanceSettingsModel { host.instanceSettings }
    private var model: UpdatesModel { host.updates }

    var body: some View {
        content
            .task(id: host.grants) {
                if host.grants.contains(.configManage) { await settings.load() }
                if host.grants.contains(.instanceRead) { await model.load() }
                else if model.canChangeSettings { await model.loadAutomaticChecks() }
            }
            .alert("Update \(host.serverName)?", isPresented: $asksToUpdate) {
                Button("Cancel", role: .cancel) {}
                Button("Update") {
                    let model = model
                    Task { await model.confirmUpdate() }
                }
                .disabled(!model.canUpdate)
            } message: {
                Text("\(host.serverName) restarts to finish the update. The app reconnects when it’s back.")
            }
            .accessibilityIdentifier("AccountRelease")
    }

    @ViewBuilder private var content: some View {
        SettingsSection(name: Text("Marfa"), footer: lastUpdateLine) {
            if host.grants.contains(.configManage) {
                if settings.isAvailable { nameRow }
                else if let failure = settings.failure {
                    OwnerProblemRow(title: "Couldn’t read the name", failure: OwnerFailure(failure), page: .account, host: host) { Task { await settings.load() } }
                }
            } else {
                locked("Name", permission: .configManage)
            }
            if !host.grants.contains(.instanceRead) {
                locked("Version", permission: .instanceRead)
            } else if let failure = model.failure {
                OwnerProblemRow(title: "Couldn’t read the release", failure: failure, page: .account, host: host) { Task { await model.load() } }
            } else if let status = model.status {
                if model.isUpdating { updating(status) }
                else { marfa(status) }
            }
            automaticChecks
        }
        if host.grants.contains(.instanceRead), let status = model.status, !model.isUpdating { problem(status) }
    }

    private var lastUpdateLine: Text? {
        guard host.grants.contains(.instanceRead), let last = model.status?.last else { return nil }
        let title = last.result == .succeeded ? String(localized: "Updated to \(last.release)") : String(localized: "Tried \(last.release)")
        return Text(verbatim: [title, lastLine(last)].joined(separator: ". "))
    }

    private func locked(_ title: LocalizedStringKey, permission: InstancePermission) -> some View {
        SettingsRow(title) {
            Button { host.askForMore(naming: permission.rawValue) } label: { Label("Not allowed", systemImage: "lock") }
                .buttonStyle(.plain).disabled(host.isAllowingMore)
        }
    }

    private var nameRow: some View {
        let errors = InstanceRowErrors(model: settings, settings: [.name])
        let text = Binding { settings.draft[.name] ?? "" } set: { settings.draft[.name] = $0 }
        return VStack(alignment: .leading, spacing: 0) {
            SettingsRow("Name", line: "What apps and the sign-in page show.", error: errors.message(for: .name)) {
                SettingsField(
                    title: "Name", text: text, prompt: String(localized: "Marfa"), isError: errors.isError(.name),
                    onSubmit: { Task { await settings.save([.name]) } }, onEndEditing: { Task { await settings.save([.name]) } }
                )
                .disabled(settings.isSaving)
                .accessibilityIdentifier("ThisMarfaName")
            }
            InstanceStatusLine(model: settings, settings: [.name])
        }
    }

    // MARK: Updating

    private func updating(_ status: UpdateStatus) -> some View {
        let release = status.progress?.release ?? status.latest?.version
        let stages = UpdateStage.allCases
        let done = stages.filter { model.standing(of: $0) == .done }.count
        return Group {
            SettingsRow(
                title: release.map { Text("Updating to \($0)") } ?? Text("Updating"),
                line: Text(model.standing(of: .restarting) == .now ? "Restarting. The app reconnects when it is back." : "The server restarts when it is done.")
            ) {
                ProgressView(value: Double(done) + 0.5, total: Double(stages.count))
                    .progressViewStyle(.linear)
                    .frame(width: SettingsTokens.Metric.controlWidth)
            }
            ForEach(stages, id: \.self) { stage in
                let standing = model.standing(of: stage)
                SettingsRow(
                    verbatim: UpkeepWording.stageTitle(stage),
                    lead: .symbol(standing == .done ? "checkmark.circle" : (standing == .now ? "arrow.clockwise" : "circle")), size: .compact
                ) {
                    switch standing {
                    case .done: SettingsValue("Done", dot: SettingsTokens.ok)
                    case .now: SettingsValue("Now")
                    case .next: SettingsValue("Next")
                    }
                }
            }
        }
    }

    // MARK: The release

    @ViewBuilder private func problem(_ status: UpdateStatus) -> some View {
        let undone = model.undone
        if undone != nil || model.error != nil || model.lostTrack {
            SettingsSection("Update Problems") {
                if let undone {
                    SettingsProblemRow(
                        title: Text("The update to \(undone.release) didn’t work"),
                        line: Text(
                            undone.result == .putBack
                                ? "The server is back on \(status.running). Nothing was lost."
                                : "The server runs \(status.running)."),
                        actions: retryActions(status))
                }
                if model.lostTrack {
                    SettingsProblemRow(
                        title: Text("The server hasn’t come back yet"),
                        line: Text("The app stopped waiting. Check again to see where it stands."),
                        actions: [SettingsProblemAction("Check Again") { Task { await model.load() } }])
                }
                if let error = model.error {
                    OwnerProblemRow(title: "Couldn’t update", failure: error, page: .account, host: host)
                }
            }
        }
    }

    private func retryActions(_ status: UpdateStatus) -> [SettingsProblemAction] {
        if model.needsMaintain, status.available, status.updatesItself {
            return [SettingsProblemAction("Allow More") { host.askForMore(naming: InstancePermission.instanceMaintain.rawValue) }]
        }
        return model.canUpdate ? [SettingsProblemAction("Try Again") { asksToUpdate = true }] : []
    }

    private func marfa(_ status: UpdateStatus) -> some View {
        Group {
            SettingsRow(title: title(status), line: Text(verbatim: line(status))) {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    if model.needsMaintain {
                        SettingsButton("Allow More") { host.askForMore(naming: InstancePermission.instanceMaintain.rawValue) }
                    } else {
                        SettingsButton(model.isChecking ? "Checking…" : "Check for Updates", reserving: "Check for Updates") {
                            Task { await model.checkForUpdates() }
                        }
                        .disabled(!model.canCheck)
                    }
                    if model.ready != nil, !status.updatesItself, let step = status.step, !step.isEmpty {
                        SettingsButton(copied ? "Copied" : "Copy Steps") {
                            OwnerClipboard.copyText(step)
                            copied = true
                        }
                    } else if model.ready != nil, !model.needsMaintain {
                        SettingsButton("Update", role: .update) { asksToUpdate = true }
                            .disabled(!model.canUpdate)
                    }
                }
            }
            if model.ready != nil, !status.updatesItself, let step = status.step, !step.isEmpty {
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetLabelSpacing) {
                    Text("The Server’s Steps").settingsFont(.title).foregroundStyle(SettingsTokens.primaryText)
                    SettingsReadOnlyValue(text: step)
                }
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .padding(.vertical, SettingsTokens.Metric.cardGap)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var automaticChecks: some View {
        if !model.canChangeSettings {
            locked("Check automatically", permission: .configManage)
        } else if let failure = model.settingsFailure {
            OwnerProblemRow(title: "Couldn’t read automatic update settings", failure: failure, page: .account, host: host) {
                Task { await model.loadAutomaticChecks() }
            }
        } else if let settings = model.settings {
            SettingsRow("Check automatically") {
                SettingsToggle(title: "Check automatically", isOn: Binding { settings.checksForUpdates } set: { on in
                    Task { await model.setChecksAutomatically(on) }
                }).disabled(model.isSwitching)
            }
            if !host.grants.contains(.instanceRead), let error = model.error {
                OwnerProblemRow(title: "Couldn’t change automatic update settings", failure: error, page: .account, host: host)
            }
        }
    }

    private func title(_ status: UpdateStatus) -> Text {
        let known = status.running != "0.0.0"
        return known ? Text("Marfa \(status.running)") : Text("Marfa")
    }

    /// One sentence under the release: why it can't be checked, or how it gets updated.
    private func line(_ status: UpdateStatus) -> String {
        if let latest = model.ready {
            if let published = OwnerWording.when(latest.published) { return String(localized: "\(latest.version) is ready. Published \(published).") }
            return String(localized: "\(latest.version) is ready.")
        }
        if status.checkFailed { return String(localized: "The last check found no answer.") }
        return status.checksAutomatically ? String(localized: "Automatic checks are on.") : String(localized: "Automatic checks are off.")
    }

    // MARK: Last update

    private func lastLine(_ last: UpdateOutcome) -> String {
        let when = last.finished.map { UpkeepWording.moment($0, hasTime: last.finishedHasTime) + "." }
        let why: String? =
            switch last.result {
            case .succeeded: nil
            case .putBack: String(localized: "It was undone.")
            case .failed: String(localized: "It couldn’t be put in place.")
            }
        return [when, why].compactMap { $0 }.joined(separator: " ")
    }
}
