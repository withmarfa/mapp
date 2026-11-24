import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

// What the Connectors page asks of the server, in values of its own. Every call needs `connectors.manage`.

/// Which way a kind of record a connector brings moves.
nonisolated enum ConnectorDirection: Hashable, Sendable {
    case into, out, both
}

/// A kind of record a connector brings, written as one of its plugin's own types.
nonisolated struct ConnectorKind: Hashable, Sendable, Identifiable {
    var name: String
    var type: String
    var direction: ConnectorDirection

    var id: String { name }
}

/// How a connector signs in to its service, each part naming one of its settings.
nonisolated struct ConnectorSignInDeclaration: Hashable, Sendable {
    /// The service, as the server names it (`google`).
    var provider: String
    var clientIDSetting: String
    var clientSecretSetting: String
    var tokenSetting: String
}

/// An installed plugin that holds a connector.
nonisolated struct PluginConnectorSummary: Identifiable, Hashable, Sendable {
    /// The plugin's name, which every door of its connector is addressed by.
    let name: String
    var title: String
    var description: String
    /// An icon ID such as `simple-icons:rss`.
    var mark: String
    var source: String
    var version: String
    var hostID: String?
    var kinds: [ConnectorKind]
    /// Nil for a connector that declares no vendor sign-in.
    var signIn: ConnectorSignInDeclaration?

    var id: String { name }
}

/// What the owner has chosen for a connector: where it runs, whether it is paused and whether a run was asked for.
nonisolated struct ConnectorControl: Hashable, Sendable {
    var host: String?
    /// Nil until the connector's host has registered it.
    var registration: String?
    var paused: Bool
    var runRequested: Date?
}

/// How a run ended.
nonisolated struct ConnectorRunInfo: Hashable, Sendable {
    var succeeded: Bool
    var started: Date?
    var finished: Date?
    /// What the connector said it did.
    var summary: String?
}

/// What the connector itself has reported.
nonisolated struct ConnectorRegistration: Hashable, Sendable {
    var lastHeartbeat: Date?
    var lastRun: ConnectorRunInfo?
    /// The connector's current problems, as it wrote them, ordered by their keys.
    var problems: [String]
}

/// A machine that runs connectors.
nonisolated struct ConnectorHostInfo: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var lastSeen: Date?
    /// Whether the machine has used its one-time link and holds a key of its own.
    var linked: Bool
    /// The plugins whose connectors are assigned to it.
    var connectors: [String] = []
}

/// A machine's one-time link, which the server answers once. It gives the machine a key, so it is shown only in the sheet
/// that asked for it and never written anywhere: `description` leaves it out, so a stray print can't show it.
nonisolated struct ConnectorHostLink: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var host: ConnectorHostInfo
    let link: String
    var expires: Date

    var description: String { "ConnectorHostLink(host: \(host.id), expires: \(expires))" }
    var debugDescription: String { description }
}

/// What a setting holds, or is given.
nonisolated enum ConnectorSettingValue: Hashable, Sendable {
    case text(String)
    case number(Double)
    case flag(Bool)
}

nonisolated enum ConnectorSettingKind: Hashable, Sendable {
    case text, number, boolean, choice
}

/// A setting of a connector. A secret's value is never read: only whether one is set.
nonisolated struct ConnectorSetting: Identifiable, Hashable, Sendable {
    var name: String
    var label: String
    var kind: ConnectorSettingKind
    var choices: [String]
    var secret: Bool
    var required: Bool
    var defaultValue: ConnectorSettingValue?
    /// The value set, or the default while none is set. Always nil for a secret.
    var value: ConnectorSettingValue?
    var isSet: Bool
    /// A secret that holds a value the server cannot read, because the Marfa was restored or moved.
    var unreadable: Bool

    var id: String { name }
}

nonisolated struct ConnectorSettingsReading: Hashable, Sendable {
    var settings: [ConnectorSetting]
    /// The names of the required settings with no value, in the order the connector declares them.
    var missing: [String]
}

/// One change to a setting: a value, or taking the value away.
nonisolated enum ConnectorSettingChange: Hashable, Sendable {
    case set(ConnectorSettingValue)
    case clear
}

nonisolated struct ConnectorSignInStart: Hashable, Sendable {
    /// The sign-in's own ID, which the status read names while this sign-in is the latest.
    var id: String
    var address: URL
    var expires: Date
}

nonisolated enum ConnectorSignInStatus: Hashable, Sendable {
    case none, pending, signedIn
    /// `reason` is the server's one outcome word for how it failed.
    case failed(reason: String?)
    case expired
}

/// The latest sign-in a connector has, and which one it is.
nonisolated struct ConnectorSignInReading: Hashable, Sendable {
    var status: ConnectorSignInStatus
    /// The latest sign-in's ID, nil where none was started.
    var id: String?
}

extension ClientOwnerCalls {
    private static func kind(_ kind: Components.Schemas.PluginConnectorKind) -> ConnectorKind {
        let direction: ConnectorDirection =
            switch kind.direction {
            case ._in: .into
            case .out: .out
            case .both: .both
            }
        return ConnectorKind(name: kind.name, type: kind._type, direction: direction)
    }

    private static func summary(_ plugin: Components.Schemas.Plugin) -> PluginConnectorSummary? {
        guard let connector = plugin.connector.value else { return nil }
        let declared = connector.signIn?.value1
        return PluginConnectorSummary(
            name: plugin.name, title: plugin.title, description: plugin.description, mark: plugin.mark, source: connector.source,
            version: plugin.version, hostID: plugin.connectorHost, kinds: connector.kinds.map(kind),
            signIn: declared.map {
                ConnectorSignInDeclaration(
                    provider: $0.provider.rawValue, clientIDSetting: $0.clientIdSetting, clientSecretSetting: $0.clientSecretSetting,
                    tokenSetting: $0.tokenSetting)
            })
    }

    private static func control(_ control: Components.Schemas.PluginConnectorControl) -> ConnectorControl {
        ConnectorControl(host: control.host, registration: control.registration, paused: control.paused, runRequested: control.runRequestedAt)
    }

    static func value(_ container: OpenAPIValueContainer) -> ConnectorSettingValue? {
        switch container.value {
        case let flag as Bool: .flag(flag)
        case let number as Int: .number(Double(number))
        case let number as Double: .number(number)
        case let text as String: .text(text)
        default: nil
        }
    }

    private static func reading(_ answer: Components.Schemas.PluginConnectorSettings) -> ConnectorSettingsReading {
        ConnectorSettingsReading(
            settings: answer.settings.map { setting in
                let kind: ConnectorSettingKind =
                    switch setting.kind {
                    case .text: .text
                    case .number: .number
                    case .boolean: .boolean
                    case .choice: .choice
                    }
                return ConnectorSetting(
                    name: setting.name, label: ConnectorWording.settingTitle(setting.label), kind: kind, choices: setting.choices ?? [], secret: setting.secret,
                    required: setting.required, defaultValue: setting.secret ? nil : value(setting._default),
                    value: setting.secret ? nil : value(setting.value), isSet: setting.set, unreadable: setting.unreadable)
            },
            missing: answer.missing)
    }

    static func container(_ value: ConnectorSettingValue?) -> OpenAPIValueContainer {
        switch value {
        case .text(let text)?: OpenAPIValueContainer(stringLiteral: text)
        case .number(let number)?: (try? OpenAPIValueContainer(unvalidatedValue: number)) ?? OpenAPIValueContainer(nilLiteral: ())
        case .flag(let flag)?: OpenAPIValueContainer(booleanLiteral: flag)
        case nil: OpenAPIValueContainer(nilLiteral: ())
        }
    }

    /// The server's `409` that names why a connector's sign-in cannot start yet, as the settings it names.
    static func signInSettingsMissing(_ error: any Error) -> [String]? {
        guard case .server(409, "connector_sign_in_settings_missing", _, let details, _)? = marfaError(error) else { return nil }
        return details?.object?["settings"]?.array?.compactMap(\.string) ?? []
    }

    /// Whether the server refused a sign-in's `return_to`, as it does for a sign-in that is not an app's: the redirect the app
    /// registered is only accepted from the app that registered it.
    static func signInReturnRefused(_ error: any Error) -> Bool {
        guard case .validation(_, let message, let details, let server)? = marfaError(error) else { return false }
        let named = [details, server?.details].contains { details in
            details?.object?["errors"]?.array?.contains { $0.object?["path"]?.string == "return_to" } ?? false
        }
        return named || message.contains("return_to")
    }

    func connectorPlugins() async throws(OwnerFailure) -> [PluginConnectorSummary] {
        try await run { client in try await client.listPlugins().ok.body.json.data.compactMap(Self.summary) }
    }

    func connectorControl(of plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await run { client in Self.control(try await client.getPluginConnector(path: .init(name: plugin)).ok.body.json) }
    }

    func connectorRegistration(_ id: String) async throws(OwnerFailure) -> ConnectorRegistration {
        try await run { client in
            let connector = try await client.getConnector(path: .init(id: id)).ok.body.json
            let run = connector.lastRun.value
            return ConnectorRegistration(
                lastHeartbeat: Self.date(connector.lastHeartbeatAt),
                lastRun: run.map {
                    ConnectorRunInfo(
                        succeeded: $0.outcome == .succeeded, started: Self.date($0.startedAt), finished: Self.date($0.finishedAt), summary: $0.summary)
                },
                problems: connector.problems.additionalProperties.sorted { $0.key < $1.key }.map(\.value))
        }
    }

    private static func host(_ host: Components.Schemas.ConnectorHost) -> ConnectorHostInfo {
        ConnectorHostInfo(id: host.id, name: host.name, lastSeen: host.lastSeenAt, linked: host.linked, connectors: host.connectors.map(\.plugin))
    }

    private static func link(_ answer: Components.Schemas.ConnectorHostLink) -> ConnectorHostLink {
        ConnectorHostLink(host: host(answer.host.value1), link: answer.link, expires: answer.expiresAt)
    }

    func connectorHosts() async throws(OwnerFailure) -> [ConnectorHostInfo] {
        try await run { client in try await client.listConnectorHosts().ok.body.json.data.map(Self.host) }
    }

    func connectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostInfo {
        try await run { client in Self.host(try await client.getConnectorHost(path: .init(id: id)).ok.body.json) }
    }

    func createConnectorHost(named name: String) async throws(OwnerFailure) -> ConnectorHostLink {
        try await run { client in Self.link(try await client.createConnectorHost(body: .json(.init(name: name))).created.body.json) }
    }

    func linkConnectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostLink {
        try await run { client in Self.link(try await client.createConnectorHostLink(path: .init(id: id)).ok.body.json) }
    }

    func connectorSettings(of plugin: String) async throws(OwnerFailure) -> ConnectorSettingsReading {
        try await run { client in Self.reading(try await client.getPluginConnectorSettings(path: .init(name: plugin)).ok.body.json) }
    }

    func changeConnectorSettings(of plugin: String, _ changes: [String: ConnectorSettingChange]) async throws(OwnerFailure) -> ConnectorSettingsReading {
        try await run { client in
            let body = Operations.UpdatePluginConnectorSettings.Input.Body.JsonPayload(
                additionalProperties: changes.mapValues { change in
                    switch change {
                    case .set(let value): Self.container(value)
                    case .clear: Self.container(nil)
                    }
                })
            return Self.reading(try await client.updatePluginConnectorSettings(path: .init(name: plugin), body: .json(body)).ok.body.json)
        }
    }

    func pauseConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await run { client in Self.control(try await client.pausePluginConnector(path: .init(name: plugin)).ok.body.json) }
    }

    func resumeConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await run { client in Self.control(try await client.resumePluginConnector(path: .init(name: plugin)).ok.body.json) }
    }

    func runConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl {
        try await run { client in Self.control(try await client.runPluginConnector(path: .init(name: plugin)).ok.body.json) }
    }

    func assignConnector(_ plugin: String, toHost host: String?) async throws(OwnerFailure) {
        try await run { client in
            _ = try await client.replacePluginConnectorHost(path: .init(name: plugin), body: .json(.init(host: host.map { .value($0) } ?? .null))).ok
        }
    }

    func startConnectorSignIn(of plugin: String, returningTo address: String) async throws(OwnerFailure) -> ConnectorSignInStart {
        let client = try make()
        do {
            let started = try await client.startPluginConnectorSignIn(path: .init(name: plugin), body: .json(.init(returnTo: address))).created.body.json
            guard let url = URL(string: started.url), url.scheme == "https" else {
                throw OwnerFailure.failed(String(localized: "The server’s address for signing in couldn’t be read."))
            }
            return ConnectorSignInStart(id: started.id, address: url, expires: started.expiresAt)
        } catch let failure as OwnerFailure {
            throw failure
        } catch {
            if let settings = Self.signInSettingsMissing(error) { throw .signInNeeds(settings) }
            if Self.signInReturnRefused(error) {
                throw .failed(String(localized: "A connector’s sign-in needs the app signed in as an app. Sign in again in Connection."))
            }
            throw Self.failure(error)
        }
    }

    func connectorSignInStatus(of plugin: String) async throws(OwnerFailure) -> ConnectorSignInReading {
        try await run { client in
            let status = try await client.getPluginConnectorSignIn(path: .init(name: plugin)).ok.body.json
            let stands: ConnectorSignInStatus =
                switch status.status {
                case .none: .none
                case .pending: .pending
                case .signedIn: .signedIn
                case .failed: .failed(reason: status.reason)
                case .expired: .expired
                }
            return ConnectorSignInReading(status: stands, id: status.id)
        }
    }
}
