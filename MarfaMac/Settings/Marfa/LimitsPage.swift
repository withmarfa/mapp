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
                    limitSections
                    if let readFailure {
                        OwnerProblem(title: "Couldn’t read start-up settings", failure: readFailure, page: .limits, host: host) { Task { await readStartUp() } }
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
                limitSections
                StartUpSettings(rows: model.startUp)
            }
        } else {
            OwnerLoading()
        }
    }

    @ViewBuilder private var limitSections: some View {
        SettingsSection("Requests", footer: "A bulk request can be at most 32 MB. Leave a field empty to use its default.") {
            field(.largestRequest)
            field(.largestBulkRequest)
        }
        SettingsSection("Rate Limits", footer: "Each app or key gets these in every window.") {
            rateLimitSwitch
            field(.window)
            field(.requestsPerWindow)
            field(.keyRequestsPerWindow)
        }
        SettingsSection("Connector Deliveries", footer: "For each inbound address.") {
            field(.largestDelivery)
            field(.deliveriesPerWindow)
            field(.waiting)
        }
        SettingsSection("Live Updates", footer: "0 sets no limit.") {
            field(.mostViewers)
        }
    }

    @ViewBuilder private func field(_ limit: LimitSetting) -> some View {
        if host.grants.contains(.configManage) {
            LimitField(model: model, limit: limit)
        } else {
            LockedInstanceRow(title: limit.title, permission: .configManage, host: host)
        }
    }

    @ViewBuilder private var rateLimitSwitch: some View {
        if host.grants.contains(.configManage) {
            switchRow("Limit requests", key: LimitSetting.rateLimitSwitch)
        } else {
            LockedInstanceRow(title: String(localized: "Limit requests"), permission: .configManage, host: host)
        }
    }

    @ViewBuilder private func switchRow(_ title: LocalizedStringKey, key: String) -> some View {
        if model.setting(key)?.value?.bool != nil {
            SettingsRow(title: Text(title), error: model.lines[key]) {
                SettingsToggle(title: title, isOn: Binding { model.isOn(key) } set: { on in Task { await model.setSwitch(key, on) } })
                    .disabled(model.saving.contains(key))
                    .accessibilityIdentifier("Limit-" + key)
            }
        }
    }
}

struct LimitField: View {
    let model: LimitsModel
    let limit: LimitSetting

    var body: some View {
        let text = Binding { model.text(limit) } set: { model.type($0, for: limit) }
        if model.held(limit) != nil {
            SettingsRow(verbatim: limit.title, line: limit.line, error: model.line(limit)) {
                SettingsNumberField(
                    title: LocalizedStringKey(limit.title), text: text, unit: LocalizedStringKey(limit.unit.title),
                    isError: model.hasProblem(limit), onSubmit: { Task { await model.commit(limit) } },
                    onEndEditing: { Task { await model.commit(limit) } })
                .disabled(model.saving.contains(limit.key) || !model.isEnabled(limit))
                .accessibilityIdentifier("Limit-" + limit.key)
            }
        }
    }
}
