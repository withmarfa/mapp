import Marfa
import SwiftUI

/// Shows a Marfa page only when it can: a page with no copy open, a signed-out connection, a server that is not
/// answering or a permission the owner has not approved says so in the centered state, with the way forward, and never
/// falls back to a library of its own. `above` is what the page offers whatever the state, such as a setting of this
/// Mac: it stands over a state, and the page draws it itself above its own content.
struct MarfaPageGate<Content: View>: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    var above: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        switch host.connection {
        case .opening:
            standing { OwnerLoading() }
        case .notConnected:
            standing {
                SettingsPageState(
                    symbol: "server.rack", title: Text("No Marfa Open"),
                    line: Text("Connect to a Marfa in Connection to see this page."),
                    action: ("Open Connection", { host.showConnection() }))
            }
        case .signedOut:
            standing {
                SettingsPageState(
                    symbol: "person.crop.circle.badge.exclamationmark", title: Text("Signed Out"),
                    line: Text("\(host.serverName) ended the app’s sign-in. Sign in again in Connection."),
                    action: ("Open Connection", { host.showConnection() }))
            }
        case .notAnswering(let lastAnswered):
            standing {
                SettingsPageState(
                    symbol: "wifi.exclamationmark", title: Text("\(host.serverName) Isn’t Answering"),
                    line: Text(Self.notAnswering(lastAnswered)),
                    action: ("Try Again", { host.tryAgain() }))
            }
        case .connected:
            if let permission = page.missingPermission(in: host.grants) {
                standing {
                    SettingsPageState(
                        symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: page.permissionLine),
                        action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: permission.rawValue) }))
                    .disabled(host.isAllowingMore)
                }
            } else {
                content
            }
        }
    }

    /// A state, under `above` where the page has something to offer in any state.
    @ViewBuilder private func standing<State: View>(@ViewBuilder _ state: () -> State) -> some View {
        if let above {
            SettingsStandingState { above } state: { state() }
        } else {
            state()
        }
    }

    static func notAnswering(
        _ lastAnswered: Date?, now: Date = .now, calendar: Calendar = .current, format: DateFormat = .stored()
    ) -> String {
        guard let lastAnswered else { return String(localized: "The app keeps trying.") }
        let time = DateDisplay.timeOfDay(of: lastAnswered, format: format, calendar: calendar)
        let when = calendar.isDate(lastAnswered, inSameDayAs: now)
            ? String(localized: "today, \(time)")
            : DateDisplay.text(of: lastAnswered, place: .value, format: format, now: now, calendar: calendar)
        return String(localized: "Last answered \(when). The app keeps trying.")
    }
}

/// The Marfa's page for `page`, behind its gate.
struct MarfaSettingsPageView: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost
    @Environment(\.settingsSubpage) private var subpage

    var body: some View {
        MarfaPageGate(page: page, host: host, above: standingContent) {
            switch page {
            case .passkeys, .browsers: AccountSignInsPage(page: page, host: host)
            case .account: AccountPage(host: host)
            case .apps: AppsPage(host: host, subpage: subpage)
            case .keys: KeysPage(host: host, subpage: subpage)
            case .network: NetworkPage(host: host)
            case .plugins: PluginsPage(host: host, subpage: subpage)
            case .sources: SourcesPage(host: host, subpage: subpage)
            case .types: TypesPage(host: host, subpage: subpage)
            case .links: LinksPage(host: host, subpage: subpage)
            case .activity: ActivityPage(host: host)
            case .monitoring: MonitoringPage(host: host)
            case .limits: LimitsPage(host: host)
            case .trash: TrashPage(host: host, showsAll: subpage?.id == TrashPage.allDeleted.id)
            case .fileStorage: FileStoragePage(host: host)
            case .connectors: ConnectorsPage(host: host, subpage: subpage)
            case .webhooks: WebhooksPage(host: host, subpage: subpage)
            case .folders: FoldersPage(host: host, subpage: subpage)
            case .backups: BackupsPage(host: host, showsAll: subpage?.id == BackupsPage.allBackups.id)
            case .housekeeping: HousekeepingPage(host: host)
            }
        }
        .id(host.serverAddress)
    }

    private var standingContent: AnyView? {
        guard subpage == nil else { return nil }
        switch page {
        case .account where host.serverAddress != nil: return AnyView(AccountHeader(host: host))
        case .keys: return AnyView(AppsSettingsSection(host: host))
        default: return nil
        }
    }
}

/// A link to another Marfa page. A locked link still opens its gate, where the owner can grant access.
struct MarfaSettingsPageRow: View {
    let page: MarfaSettingsPage
    let host: any MarfaSettingsHost

    private var lock: String? {
        guard host.connection == .connected, page.missingPermission(in: host.grants) != nil else { return nil }
        return String(localized: "Not allowed")
    }

    var body: some View {
        SettingsLinkRow(verbatim: page.title, lead: .tile(page.symbol, page.tone), lock: lock) { host.show(page) }
            .accessibilityIdentifier("SettingsLink-\(page.rawValue)")
    }
}
