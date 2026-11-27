import Marfa
import SwiftUI

/// The Housekeeping page: the jobs the server runs by itself, how often, when each last ran and how it went, and the problem
/// that holds clean-up: the server's clock reading far past the time it last trusted. Confirm Date… asks first.
struct HousekeepingPage: View {
    let host: any MarfaSettingsHost
    @State private var model: HousekeepingModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: HousekeepingModel(context: OwnerContext(host: host)))
    }

    private var health: ServerHealthModel { host.health }
    private var housekeeping: HousekeepingHealth? { health.health?.housekeeping }

    var body: some View {
        content
            .task(id: host.grants) {
                guard host.grants.contains(.instanceRead) else { return }
                await model.load()
                await host.health.load()
            }
            .alert(
                model.confirming.map { String(localized: "Is it \(Self.date($0))?") } ?? "",
                isPresented: Binding { model.confirming != nil } set: { if !$0 { model.cancelConfirming() } },
                presenting: model.confirming
            ) { date in
                Button("Cancel", role: .cancel) {}
                Button("Confirm Date") { Task { await model.confirm(date: date, health: host.health) } }
            } message: { _ in
                Text("\(host.serverName)’s clock says so. If it’s right, clean-up starts again.")
            }
            .accessibilityIdentifier("HousekeepingPage")
    }

    @ViewBuilder private var content: some View {
        SettingsPageColumn {
            jobsContent
            if host.grants.contains(.configManage) {
                InstanceSettingsGate(page: .housekeeping, host: host) {
                    SettingsSection("Logs") {
                        ForEach(InstanceSetting.logSettings, id: \.self) { setting in
                            InstanceChoiceRow(model: host.instanceSettings, setting: setting, among: InstanceSetting.logSettings, line: Self.logLine(setting))
                        }
                        InstanceStatusLine(model: host.instanceSettings, settings: InstanceSetting.logSettings)
                    }
                }
            } else {
                OwnerProblem(title: "Log Retention", failure: .notPermitted(InstancePermission.configManage.rawValue), page: .housekeeping, host: host)
            }
        }
    }

    private static func logLine(_ setting: InstanceSetting) -> LocalizedStringKey? {
        switch setting {
        case .auditRetentionDays: "And webhook deliveries."
        case .eventLogRetentionDays: "What apps catch up on after being away."
        case .rowLogRetentionDays: "So a change to a table can be undone."
        default: nil
        }
    }

    @ViewBuilder private var jobsContent: some View {
        if !host.grants.contains(.instanceRead) {
            OwnerProblem(title: "Jobs", failure: .notPermitted(InstancePermission.instanceRead.rawValue), page: .housekeeping, host: host)
        } else if let failure = model.failure {
            OwnerFailureState(page: .housekeeping, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else {
            attention
            jobs
        }
    }

    /// A date as the alert and the problem say it: "3 March 2027", always with the year, since a clock that jumped is
    /// judged by it.
    static func date(_ date: Date) -> String { date.formatted(.dateTime.day().month(.wide).year()) }

    // MARK: Needs attention

    @ViewBuilder private var attention: some View {
        let failed = housekeeping?.failed ?? []
        let hold = housekeeping?.hold
        if hold != nil || !failed.isEmpty || model.confirmError != nil || model.confirmedInstead != nil {
            SettingsSection("Needs Attention") {
                if let hold {
                    SettingsProblemRow(
                        title: Text("Clean-up is paused"),
                        line: hold.clockAt.map { Text("\(host.serverName)’s clock jumped to \(Self.date($0)).") } ?? Text("\(host.serverName)’s clock jumped."),
                        actions: [confirmAction(hold)])
                }
                if let instead = model.confirmedInstead {
                    SettingsProblemRow(
                        title: Text("\(host.serverName) took another date"),
                        line: Text("You were shown \(Self.date(instead.shown)), and its clock read \(Self.date(instead.confirmed)) when it confirmed."),
                        actions: [])
                }
                if let error = model.confirmError {
                    OwnerProblemRow(title: "Couldn’t confirm the date", failure: error, page: .housekeeping, host: host)
                }
                ForEach(failed, id: \.name) { job in
                    SettingsProblemRow(
                        title: Text("\(UpkeepWording.jobTitle(job.name)) failed"), line: Text("Its last run failed."), actions: [])
                }
            }
        }
    }

    private func confirmAction(_ hold: ClockHold) -> SettingsProblemAction {
        if host.grants.contains(.instanceMaintain) {
            SettingsProblemAction("Confirm Date…") { Task { await model.askToConfirm(health: host.health) } }
        } else {
            SettingsProblemAction("Allow More…") { host.askForMore(naming: InstancePermission.instanceMaintain.rawValue) }
        }
    }

    // MARK: Jobs

    private var columns: [SettingsTableColumn<HousekeepingJob>] {
        [
            SettingsTableColumn("Job") { Text(verbatim: UpkeepWording.jobTitle($0.name)) },
            SettingsTableColumn("Every", width: SettingsTokens.Metric.Column.day) {
                Text(verbatim: UpkeepWording.every($0.intervalSeconds)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Last Run", width: SettingsTokens.Metric.Column.label) { job in
                Text(verbatim: job.lastFinished.map { UpkeepWording.moment($0, hasTime: job.lastFinishedHasTime) } ?? String(localized: "Not Yet"))
                    .foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("Result", width: SettingsTokens.Metric.Column.state) { Text(verbatim: UpkeepWording.result($0.outcome)).foregroundStyle(SettingsTokens.secondaryText) },
        ]
    }

    private var jobs: some View {
        SettingsSection(
            name: Text("Jobs"), line: Text("\(host.serverName) runs these by itself. Jobs that delete pause while its clock looks wrong.")
        ) {
            if model.listed.isEmpty {
                SettingsEmptyCard(symbol: "sparkles", title: Text("No Jobs Yet"), line: Text("\(host.serverName) lists its jobs once it has started them."))
            } else {
                SettingsSectionTable(rows: model.listed, columns: columns)
            }
        }
    }
}
