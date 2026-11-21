import Marfa
import SwiftUI

/// The Updates page: the release the server runs, Check for Updates beside Update where one is ready, the steps while it
/// updates, and how the last update ended. Where the server cannot update itself it says how, with Copy Steps.
struct UpdatesPage: View {
    let host: any MarfaSettingsHost
    @State private var model: UpdatesModel
    @State private var copied = false

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: UpdatesModel(context: OwnerContext(host: host)))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onDisappear { model.stop() }
            .accessibilityIdentifier("UpdatesPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .updates, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let status = model.status {
            SettingsPageColumn {
                if model.isUpdating {
                    updating(status)
                } else {
                    problem(status)
                    marfa(status)
                    lastUpdate(status)
                }
            }
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
                line: Text(model.standing(of: .restarting) == .now ? "Restarting. MAPP reconnects when it is back." : "\(host.serverName) restarts when it is done.")
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
                        actions: model.canUpdate ? [SettingsProblemAction("Try Again") { Task { await model.update() } }] : [])
                }
                if model.lostTrack {
                    SettingsProblemRow(
                        title: Text("\(host.serverName) hasn’t come back yet"),
                        line: Text("MAPP stopped waiting. Check again to see where it stands."),
                        actions: [SettingsProblemAction("Check Again") { Task { await model.load() } }])
                }
                if let error = model.error {
                    OwnerProblemRow(title: "Couldn’t Do That", failure: error, page: .updates, host: host)
                }
            }
        }
    }

    private func marfa(_ status: UpdateStatus) -> some View {
        SettingsSection("Marfa") {
            SettingsRow(title: title(status), line: Text(verbatim: line(status))) {
                HStack(spacing: 8) {
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
                        SettingsButton("Update", role: .update) { Task { await model.update() } }
                            .disabled(!model.canUpdate)
                    }
                }
            }
            if model.ready != nil, !status.updatesItself, let step = status.step, !step.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The Server’s Steps").settingsFont(.title).foregroundStyle(SettingsTokens.primaryText)
                    SettingsReadOnlyValue(text: step)
                }
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsRow("Check Automatically", line: model.status?.checksAutomatically == false ? "Turned off." : "Every few hours.") {
                SettingsToggle(
                    title: "Check Automatically",
                    isOn: Binding { status.checksAutomatically } set: { on in Task { await model.setChecksAutomatically(on) } }
                )
                .disabled(model.settings == nil || model.isSwitching)
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
