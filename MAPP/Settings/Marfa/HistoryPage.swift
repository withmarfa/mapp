import Marfa
import SwiftUI

/// The History page: how long and how many versions of an item the server keeps, and how long it keeps its logs. Each choice is
/// sent at once; one that keeps things for less time asks first and says what it removes.
struct HistoryPage: View {
    let host: any MarfaSettingsHost

    private var model: InstanceSettingsModel { host.instanceSettings }
    private var all: [InstanceSetting] { InstanceSetting.versionSettings + InstanceSetting.logSettings }

    var body: some View {
        InstanceSettingsGate(host: host) {
            SettingsPageColumn {
                SettingsSection("Versions", line: "A type can keep its own.") {
                    ForEach(InstanceSetting.versionSettings, id: \.self) { setting in
                        InstanceChoiceRow(model: model, setting: setting, among: all, line: setting == .versionMaxVersions ? "For one item." : nil)
                    }
                }
                SettingsSection("Logs") {
                    ForEach(InstanceSetting.logSettings, id: \.self) { setting in
                        InstanceChoiceRow(model: model, setting: setting, among: all, line: Self.line(setting))
                    }
                }
                InstanceStatusLine(model: model, settings: all)
            }
        }
        .accessibilityIdentifier("HistoryPage")
    }

    private static func line(_ setting: InstanceSetting) -> LocalizedStringKey? {
        switch setting {
        case .auditRetentionDays: "And webhook deliveries."
        case .eventLogRetentionDays: "What apps catch up on after being away."
        case .rowLogRetentionDays: "So a change to a table can be undone."
        default: nil
        }
    }
}
