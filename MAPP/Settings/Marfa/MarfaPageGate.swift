import Marfa
import SwiftUI

/// Shows a Marfa page only when it can: a page with no copy open, a signed-out connection, a server that is not
/// answering or a permission the owner has not approved says so in the centered state, with the way forward, and never
/// falls back to a library of its own.
struct MarfaPageGate<Content: View>: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    @ViewBuilder let content: Content

    var body: some View {
        switch host.connection {
        case .opening:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity).background(SettingsTokens.page)
        case .notConnected:
            SettingsPageState(
                symbol: "server.rack", title: Text("No Marfa Open"),
                line: Text("Connect to a Marfa in Connection to see this page."),
                action: ("Open Connection…", { host.showConnection() }))
        case .signedOut:
            SettingsPageState(
                symbol: "person.crop.circle.badge.exclamationmark", title: Text("Signed Out"),
                line: Text("\(host.serverName) ended MAPP’s sign-in. Sign in again in Connection."),
                action: ("Open Connection…", { host.showConnection() }))
        case .notAnswering(let lastAnswered):
            SettingsPageState(
                symbol: "wifi.exclamationmark", title: Text("\(host.serverName) Isn’t Answering"),
                line: Text(Self.notAnswering(lastAnswered)),
                action: ("Try Again", { host.tryAgain() }))
        case .connected:
            if host.grants.contains(page.permission) {
                content
            } else {
                SettingsPageState(
                    symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: page.permissionLine),
                    action: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                        let host = host
                        let permission = page.permission
                        Task { _ = await host.allowMore([permission]) }
                    }))
                .disabled(host.isAllowingMore)
            }
        }
    }

    static func notAnswering(_ lastAnswered: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let lastAnswered else { return String(localized: "MAPP keeps trying.") }
        let time = lastAnswered.formatted(date: .omitted, time: .shortened)
        let when = calendar.isDate(lastAnswered, inSameDayAs: now)
            ? String(localized: "today, \(time)")
            : lastAnswered.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Last answered \(when). MAPP keeps trying.")
    }
}

/// The Marfa's page for `page`, behind its gate.
struct MarfaSettingsPageView: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    @Environment(\.settingsSubpage) private var subpage

    var body: some View {
        MarfaPageGate(page: page, host: host) {
            switch page {
            case .overview: OverviewPage(host: host)
            case .recentlyDeleted: RecentlyDeletedPage(host: host, showsAll: subpage?.id == RecentlyDeletedPage.allDeleted.id)
            }
        }
    }
}
