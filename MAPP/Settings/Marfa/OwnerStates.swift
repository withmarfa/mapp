import Marfa
import SwiftUI

/// What the owner's pages say in place of themselves when the server could not give what they show.
struct OwnerFailureState: View {
    /// The page the state stands in for, which words what MAPP isn't allowed to do there.
    let page: MarfaSettingsPage
    let failure: OwnerFailure
    let host: any MarfaSettingsHost
    let retry: () -> Void

    var body: some View {
        switch failure {
        case .notPermitted(let scope):
            SettingsPageState(
                symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: OwnerWording.permissionLine(scope, on: page)),
                action: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                    let host = host
                    let asked = scope.flatMap { InstancePermission(rawValue: $0) }
                    Task { _ = await host.allowMore(asked.map { [$0] } ?? []) }
                }))
            .disabled(host.isAllowingMore)
        case .unreachable:
            SettingsPageState(
                symbol: "wifi.exclamationmark", title: Text("Can’t Reach \(host.serverName)"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Try Again", retry))
        case .signedOut:
            SettingsPageState(
                symbol: "person.crop.circle.badge.exclamationmark", title: Text("Signed Out"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Open Connection…", { host.showConnection() }))
        default:
            SettingsPageState(
                symbol: "exclamationmark.triangle", title: Text("Couldn’t Read This Page"), line: Text(verbatim: OwnerWording.line(failure)),
                action: ("Try Again", retry))
        }
    }
}

/// A page waiting for the server's first answer.
struct OwnerLoading: View {
    var body: some View {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity).background(SettingsTokens.page)
    }
}

/// A line under a page's rows that says why the last thing asked of the server was not done.
struct OwnerProblem: View {
    let title: LocalizedStringKey
    let line: String

    var body: some View {
        SettingsSection(name: nil) {
            SettingsProblemRow(title: Text(title), line: Text(verbatim: line), actions: [])
        }
    }
}
