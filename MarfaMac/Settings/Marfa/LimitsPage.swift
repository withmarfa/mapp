import Marfa
import SwiftUI

/// The Limits page: how much of each kind of thing the server takes, as numbers with their units inside. A value is sent
/// when its field is left or Return is pressed; a value out of range stays in its field with one line under its title.
struct LimitsPage: View {
    let host: any MarfaSettingsHost
    @State private var model: LimitsModel

    @State private var readOnlyStartUp: [StartUpSetting]?
    @State private var readFailure: OwnerFailure?

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: LimitsModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    /// A page over a model that already holds its state, for a render to draw.
    init(host: any MarfaSettingsHost, model: LimitsModel) {
        self.host = host
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if host.grants.contains(.configManage) { content }
            else {
                SettingsPageColumn {
                    OwnerProblem(title: "Limits", failure: .notPermitted(InstancePermission.configManage.rawValue), page: .limits, host: host)
                    if let readFailure {
                        OwnerProblem(title: "Couldn’t Read Start-Up Settings", failure: readFailure, page: .limits, host: host) { Task { await readStartUp() } }
                    } else if let readOnlyStartUp { StartUpSettings(rows: readOnlyStartUp) }
                }
            }
        }
            .task(id: host.grants) {
                if host.grants.contains(.configManage) { await model.load() }
                else { await readStartUp() }
            }
            .onAppear { host.ownerDrafts.register(model) }
            .accessibilityIdentifier("LimitsPage")
    }

    private func readStartUp() async {
        do {
            readOnlyStartUp = try await host.instanceCalls.startUpSettings()
            readFailure = nil
        } catch {
            readFailure = error
            await OwnerContext(host: host).learn(from: error)
        }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, !model.isLoaded {
            OwnerFailureState(page: .limits, failure: failure, host: host) { Task { await model.load() } }
        } else if model.isLoaded {
            SettingsPageColumn {
                if let notice = model.notice { OwnerNotice(title: "Changed Elsewhere", line: notice, close: { model.dismissNotice() }) }
                SettingsSection("Requests", footer: "Leave a field empty to use \(host.serverName)’s own default.") {
                    field(.largestRequest)
                    field(.largestBulkRequest)
                }
                SettingsSection("Rate Limits") {
                    switchRow("Limit Requests", key: LimitSetting.rateLimitSwitch)
                    field(.requestsPerWindow)
                    field(.keyRequestsPerWindow)
                    field(.window)
                }
                SettingsSection("File Reading") {
                    field(.largestFileRead)
                    field(.mostTextKept)
                    field(.tries)
                }
                SettingsSection("Connector Deliveries") {
                    field(.largestDelivery)
                    field(.deliveriesPerWindow)
                    field(.waiting)
                }
                SettingsSection("Live Updates") {
                    field(.mostViewers)
                }
                SettingsSection("Fetching Files") {
                    switchRow("Let Tools Fetch Files", line: "From a web address, or one a chat attached.", key: LimitSetting.fetchSwitch)
                    field(.largestFetch)
                    field(.fetchTime)
                }
                StartUpSettings(rows: model.startUp)
            }
        } else {
            OwnerLoading()
        }
    }

    private func field(_ limit: LimitSetting) -> some View {
        let text = Binding { model.text(limit) } set: { model.type($0, for: limit) }
        return SettingsRow(verbatim: limit.title, line: limit.line, error: model.line(limit)) {
            SettingsNumberField(
                title: LocalizedStringKey(limit.title), text: text, unit: LocalizedStringKey(limit.unit.title),
                isError: model.hasProblem(limit), onSubmit: { Task { await model.commit(limit) } },
                onEndEditing: { Task { await model.commit(limit) } })
            .disabled(model.saving.contains(limit.key) || !model.isEnabled(limit))
            .accessibilityIdentifier("Limit-" + limit.key)
        }
    }

    private func switchRow(_ title: LocalizedStringKey, line: LocalizedStringKey? = nil, key: String) -> some View {
        SettingsRow(title, line: line) {
            SettingsToggle(title: title, isOn: Binding { model.isOn(key) } set: { on in Task { await model.setSwitch(key, on) } })
                .disabled(model.saving.contains(key))
                .accessibilityIdentifier("Limit-" + key)
        }
    }
}
