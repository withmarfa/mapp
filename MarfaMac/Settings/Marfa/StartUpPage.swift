import SwiftUI

/// What the server started with, read only: each setting only whoever runs it can change, with what it does and whether it is
/// set. Its value is never shown, since some are secrets and the rest are the machine's own.
struct StartUpPage: View {
    let host: any MarfaSettingsHost
    @State private var store: StoredSettings

    init(host: any MarfaSettingsHost) {
        self.host = host
        _store = State(initialValue: StoredSettings(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    private var columns: [SettingsTableColumn<StartUpSetting>] {
        [
            SettingsTableColumn("Setting", width: SettingsTokens.Metric.Column.setting, truncation: .middle) { setting in
                Text(verbatim: setting.name).settingsFont(.mono)
            },
            SettingsTableColumn("What It Does", lines: 2) { setting in
                Text(verbatim: StartUpWording.what(setting.name)).foregroundStyle(SettingsTokens.secondaryText)
            },
            SettingsTableColumn("State", width: SettingsTokens.Metric.Column.state) { setting in
                Text(setting.isSet ? "Set" : "Not Set").foregroundStyle(SettingsTokens.secondaryText)
            },
        ]
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await store.load() }
            .accessibilityIdentifier("StartUpPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = store.failure, store.snapshot == nil {
            OwnerFailureState(page: .startUp, failure: failure, host: host) { Task { await store.load() } }
        } else if let snapshot = store.snapshot {
            SettingsPageColumn {
                SettingsSection(
                    name: Text("Set Where \(host.serverName) Runs"), line: Text("Read when \(host.serverName) starts. Change them where it runs.")
                ) {
                    if snapshot.startUp.isEmpty {
                        SettingsEmptyCard(symbol: "power", title: Text("Nothing listed"), line: Text("\(host.serverName) lists no start-up settings."))
                    } else {
                        SettingsSectionTable(rows: snapshot.startUp, columns: columns, showsCount: false)
                    }
                }
            }
        } else {
            OwnerLoading()
        }
    }
}

/// What each start-up setting does, in the app's words. A setting a newer server adds has none until the app names it.
nonisolated enum StartUpWording {
    static func what(_ name: String) -> String { known[name] ?? "" }

    private static let known: [String: String] = [
        "MARFA_PORT": String(localized: "The port it listens on."),
        "MARFA_LISTEN_HOST": String(localized: "The address it listens on."),
        "MARFA_TRUSTED_PROXY_CIDRS": String(localized: "Proxies it believes."),
        "MARFA_TRUSTED_PROXY_HEADER": String(localized: "Where a proxy puts the caller’s address."),
        "MARFA_DATABASE_PATH": String(localized: "Where the database is."),
        "MARFA_MAX_CONNECTIONS": String(localized: "Most connections at once."),
        "MARFA_MAX_CONNECTIONS_PER_ADDRESS": String(localized: "Most connections from one address."),
        "MARFA_BLOB_PATH": String(localized: "Where files are kept."),
        "MARFA_ENRICHMENT_TESSDATA_DIR": String(localized: "More languages for reading text in pictures."),
        "MARFA_CONTROL_SOCKET": String(localized: "The command line’s way in."),
        "MARFA_CONTROL_ONLY": String(localized: "Starts only the command line’s way in, for recovery."),
        "MARFA_CLAIM_ADDRESS": String(localized: "The sign-in address a new Marfa starts with."),
        "MARFA_OWNER_RECOVERY": String(localized: "Prints a recovery code at each start."),
        "MARFA_CLOUD_URL": String(localized: "The address used to connect to Marfa Cloud."),
        "MARFA_CLOUDFLARED": String(localized: "The location of the tunnel connector for Marfa Cloud."),
        "MARFA_KEY_SALT": String(localized: "Seals stored keys. Never shown."),
        "MARFA_AUTH_SECRET": String(localized: "Signs sign-ins. Never shown."),
    ]
}
