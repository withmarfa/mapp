import SwiftUI

/// The Limits page: how much of each kind of thing the server takes, as numbers with their units inside. A value is sent
/// when its field is left or Return is pressed; a value out of range stays in its field with one line under its title.
struct LimitsPage: View {
    let host: any MarfaSettingsHost
    @State private var model: LimitsModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: LimitsModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .accessibilityIdentifier("LimitsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, !model.isLoaded {
            OwnerFailureState(failure: failure, host: host) { Task { await model.load() } }
        } else if model.isLoaded {
            SettingsPageColumn {
                if let notice = model.notice { OwnerProblem(title: "Not Changed", line: notice) }
                SettingsSection("Requests") {
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
                SettingsSection("Fetching Files", footer: "Leave a field empty to use \(host.serverName)’s own default.") {
                    switchRow("Let Tools Fetch Files", line: "From a web address, or one a chat attached.", key: LimitSetting.fetchSwitch)
                    field(.largestFetch)
                    field(.fetchTime)
                }
            }
        } else {
            OwnerLoading()
        }
    }

    private func field(_ limit: LimitSetting) -> some View {
        let text = Binding { model.text(limit) } set: { model.drafts[limit.key] = $0 }
        return SettingsRow(verbatim: limit.title, line: limit.line, error: model.line(limit)) {
            SettingsNumberField(
                title: LocalizedStringKey(limit.title), text: text, unit: LocalizedStringKey(limit.unit.title),
                isError: model.hasProblem(limit), onSubmit: { Task { await model.commit(limit) } },
                onEnd: { Task { await model.commit(limit) } })
            .disabled(model.saving.contains(limit.key))
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
