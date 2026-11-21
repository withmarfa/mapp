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
            if let permission = page.permission, !host.grants.contains(permission) {
                SettingsPageState(
                    symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: page.permissionLine),
                    action: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                        let host = host
                        Task { _ = await host.allowMore([permission]) }
                    }))
                .disabled(host.isAllowingMore)
            } else {
                content
            }
        }
    }

    static func notAnswering(
        _ lastAnswered: Date?, now: Date = .now, calendar: Calendar = .current, format: DateFormat = .stored()
    ) -> String {
        guard let lastAnswered else { return String(localized: "MAPP keeps trying.") }
        let time = DateDisplay.timeOfDay(of: lastAnswered, format: format, calendar: calendar)
        let when = calendar.isDate(lastAnswered, inSameDayAs: now)
            ? String(localized: "today, \(time)")
            : DateDisplay.text(of: lastAnswered, place: .value, format: format, now: now, calendar: calendar)
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
            case .account: AccountPage(host: host)
            case .apps: AppsPage(host: host, subpage: subpage)
            case .keys: KeysPage(host: host, subpage: subpage)
            case .addresses: AddressesPage(host: host)
            case .recentlyDeleted: RecentlyDeletedPage(host: host, showsAll: subpage?.id == RecentlyDeletedPage.allDeleted.id)
            case .webhooks: WebhooksPage(host: host, subpage: subpage)
            }
        }
    }
}
