import Marfa
import SwiftUI

/// The Updates page: the release the server runs, Check for Updates beside Update where one is ready, the steps while it
/// updates, and how the last update ended. Where the server cannot update itself it says how, with Copy Steps.
struct UpdatesPage: View {
    let host: any MarfaSettingsHost
    @State private var copied = false
    @State private var asksToUpdate = false

    private struct LoadID: Equatable {
        let address: String?
        let canChangeSettings: Bool
    }

    init(host: any MarfaSettingsHost) {
        self.host = host
    }

    /// The host's one updates model, which Overview reads too.
    private var model: UpdatesModel { host.updates }

    var body: some View {
        content
            .task(id: LoadID(address: host.serverAddress, canChangeSettings: model.canChangeSettings)) { await model.load() }
            .alert("Update \(host.serverName)?", isPresented: $asksToUpdate) {
                Button("Cancel", role: .cancel) {}
                Button("Update") {
                    let model = model
                    Task { await model.confirmUpdate() }
                }
            } message: {
                Text("\(host.serverName) restarts to finish the update. The app reconnects when it’s back.")
            }
            .accessibilityIdentifier("UpdatesPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .updates, failure: failure, host: host) { Task { await model.load() } }
        } else if model.hasLoaded, let status = model.status {
            SettingsPageColumn {
                if model.isUpdating {
                    updating(status)
                } else {
                    problem(status)
                    marfa(status)
                    lastUpdate(status)
                }
            }
        } else {
            OwnerLoading()
        }
    }

    // MARK: Updating

    private func updating(_ status: UpdateStatus) -> some View {
        let release = status.progress?.release ?? status.latest?.version
        let stages = UpdateStage.allCases
        let done = stages.filter { model.standing(of: $0) == .done }.count
        return SettingsSection("Marfa") {
            SettingsRow(
                title: release.map { Text("Updating to \($0)") } ?? Text("Updating"),
                line: Text(model.standing(of: .restarting) == .now ? "Restarting. The app reconnects when it is back." : "\(host.serverName) restarts when it is done.")
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
            SettingsSection("Needs Attention") {
                if let undone {
                    SettingsProblemRow(
                        title: Text("The update to \(undone.release) didn’t work"),
                        line: Text(
                            undone.result == .putBack
                                ? "\(host.serverName) is back on \(status.running), as before. Nothing was lost."
                                : "\(host.serverName) runs \(status.running)."),
                        actions: model.canUpdate ? [SettingsProblemAction("Try Again") { asksToUpdate = true }] : [])
                }
                if model.lostTrack {
                    SettingsProblemRow(
                        title: Text("\(host.serverName) hasn’t come back yet"),
                        line: Text("The app stopped waiting. Check again to see where it stands."),
                        actions: [SettingsProblemAction("Check Again") { Task { await model.load() } }])
                }
                if let error = model.error {
                    OwnerProblemRow(title: "Couldn’t do that", failure: error, page: .updates, host: host)
                }
            }
        }
    }

    private func marfa(_ status: UpdateStatus) -> some View {
        SettingsSection("Marfa") {
            SettingsRow(title: title(status), line: Text(verbatim: line(status))) {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    if model.needsMaintain {
                        SettingsButton("Allow More…") { host.askForMore(naming: InstancePermission.instanceMaintain.rawValue) }
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
                        SettingsButton("Update…", role: .update) { asksToUpdate = true }
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
            SettingsRow("Check Automatically", line: model.status?.checksAutomatically == false ? "Turned off." : "Every few hours.") {
                SettingsToggle(
                    title: "Check Automatically",
                    isOn: Binding { status.checksAutomatically } set: { on in Task { await model.setChecksAutomatically(on) } }
                )
                .disabled(!model.canChangeSettings || model.settings == nil || model.settingsFailure != nil || model.isSwitching)
            }
            if let failure = model.settingsFailure {
                OwnerProblemRow(
                    title: "Couldn’t read automatic update settings", failure: failure, page: .updates, host: host,
                    retry: { Task { await model.load() } })
            } else if !model.canChangeSettings {
                OwnerProblemRow(
                    title: "Can’t change automatic update settings", failure: .notPermitted(InstancePermission.configManage.rawValue),
                    page: .updates, host: host)
            }
        }
    }

    private func title(_ status: UpdateStatus) -> Text {
        let known = status.running != OverviewModel.developmentVersion
        if let latest = model.ready { return Text("Marfa \(latest.version) is ready") }
        return known ? Text("Marfa \(status.running)") : Text("Marfa")
    }

    /// One sentence under the release: why it can't be checked, or how it gets updated.
    private func line(_ status: UpdateStatus) -> String {
        if !status.checksAutomatically {
            return String(localized: "Check Automatically is off, so \(host.serverName) isn’t looking for updates.")
        }
        if model.ready != nil {
            return status.updatesItself
                ? String(localized: "\(host.serverName) restarts to update.") : String(localized: "\(host.serverName) is updated where it runs.")
        }
        if status.checkFailed { return String(localized: "The last check found no answer.") }
        return String(localized: "What \(host.serverName) runs.")
    }

    // MARK: Last update

    @ViewBuilder private func lastUpdate(_ status: UpdateStatus) -> some View {
        if let last = status.last {
            SettingsSection("Last Update") {
                SettingsRow(
                    title: last.result == .succeeded ? Text("Updated to \(last.release)") : Text("Tried \(last.release)"),
                    line: Text(verbatim: lastLine(last))
                ) {
                    switch last.result {
                    case .succeeded: SettingsValue("Succeeded", dot: SettingsTokens.ok)
                    case .putBack: SettingsValue("Undone", dot: SettingsTokens.warning)
                    case .failed: SettingsValue("Failed", dot: SettingsTokens.errorRed)
                    }
                }
            }
        }
    }

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
