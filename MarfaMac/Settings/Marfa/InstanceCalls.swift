import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

// What Activity, Monitoring, Limits and Start-Up ask of the server, in values of their own so the pages and their models
// read nothing generated, and a test can script every answer. A refusal is an `OwnerFailure`, as on the owner's other pages.

/// A kind of entry in the audit log, as the server sorts them.
nonisolated enum ActivityKind: String, CaseIterable, Hashable, Sendable {
    case access, data, settings, housekeeping

    var title: String {
        switch self {
        case .access: String(localized: "Access")
        case .data: String(localized: "Items")
        case .settings: String(localized: "Settings")
        case .housekeeping: String(localized: "Housekeeping")
        }
    }
}

/// What a page of the audit log is asked for. The log is read newest first, a page at a time, from `cursor`.
nonisolated struct ActivityQuery: Hashable, Sendable {
    var kind: ActivityKind?
    var search = ""
    var limit = 20
    var cursor: String?
}

nonisolated struct ActivityEntry: Identifiable, Hashable, Sendable {
    let id: String
    var date: Date?
    /// The sign-in's name as it was when it acted, "Marfa" for the server's own work, or nil where it is not known.
    var who: String?
    /// The server's own name for what happened, which `ActivityWording` puts into words.
    var action: String
    var resourceType: String
    var resourceID: String?
    var address: String?
}

nonisolated struct ActivityBatch: Hashable, Sendable {
    var entries: [ActivityEntry]
    /// Where the next, older page starts; nil on the last page.
    var next: String?
}

/// The value of a stored setting, as the server holds it.
nonisolated enum SettingValue: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case number(Double)
    case text(String)

    var int: Int? {
        switch self {
        case .int(let value): value
        case .number(let value): value == value.rounded() ? Int(exactly: value) : nil
        default: nil
        }
    }

    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }
}

/// A setting the server stores, as `GET /config/settings` lists it. A secret has no value: only whether one is in force.
nonisolated struct StoredSetting: Hashable, Sendable {
    let key: String
    /// The value in force; nil for a secret, and for a setting with none.
    var value: SettingValue?
    var defaultValue: SettingValue?
    /// Whether the owner has stored a value, which a secret never says: it says `isSet`.
    var isStored: Bool
    var isSecret: Bool
    /// Whether a value is in force: for a secret, the server's word; for any other, that it has one.
    var isSet: Bool
}

/// A setting only whoever runs the server can change, with whether the server's environment sets it. Its value is never sent.
nonisolated struct StartUpSetting: Identifiable, Hashable, Sendable {
    let name: String
    var isSecret: Bool
    var isSet: Bool
    var id: String { name }
}

/// Every stored setting and start-up setting the server listed, with the instance that answered.
nonisolated struct InstanceSettingsSnapshot: Hashable, Sendable {
    var instanceID: String?
    var settings: [String: StoredSetting]
    var startUp: [StartUpSetting]

    func setting(_ key: String) -> StoredSetting? { settings[key] }

    /// What the server holds once it has taken `changes`, for when it can't be asked: a secret is set without a value being
    /// known, and a setting cleared takes its default.
    func applying(_ changes: [String: StoredSettingChange]) -> InstanceSettingsSnapshot {
        var next = self
        for (key, change) in changes {
            guard var setting = next.settings[key] else { continue }
            switch change {
            case .set(let value):
                setting.value = setting.isSecret ? nil : value
                setting.isStored = true
                setting.isSet = true
            case .clear:
                setting.value = setting.isSecret ? nil : setting.defaultValue
                setting.isStored = false
                setting.isSet = !setting.isSecret && setting.defaultValue != nil
            }
            next.settings[key] = setting
        }
        return next
    }
}

nonisolated enum StoredSettingChange: Hashable, Sendable {
    case set(SettingValue)
    /// Removes what was stored, so the default applies; for a secret, so nothing is set.
    case clear
}

/// What the pages ask of the server. Every call needs the server and is never queued.
nonisolated protocol InstanceCalls: Sendable {
    func activity(_ query: ActivityQuery) async throws(OwnerFailure) -> ActivityBatch
    func storedSettings() async throws(OwnerFailure) -> InstanceSettingsSnapshot
    /// Sends exactly `changes` to the instance that was read. If another instance answers, nothing is written and the call
    /// throws `conflict`.
    func change(_ changes: [String: StoredSettingChange], instanceID: String?) async throws(OwnerFailure)
}

/// `InstanceCalls` over the package's generated client.
nonisolated struct ClientInstanceCalls: InstanceCalls {
    let client: @Sendable () throws -> Client

    private func run<Result>(
        plainConflict: (String) -> OwnerFailure = { .refused($0) }, _ call: (Client) async throws -> Result
    ) async throws(OwnerFailure) -> Result {
        let client: Client
        do { client = try self.client() } catch { throw ClientOwnerCalls.failure(error) }
        do {
            return try await call(client)
        } catch let failure as OwnerFailure {
            throw failure
        } catch {
            throw ClientOwnerCalls.failure(error, plainConflict: plainConflict)
        }
    }

    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    func activity(_ query: ActivityQuery) async throws(OwnerFailure) -> ActivityBatch {
        try await run { client in
            let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = query.kind.flatMap { Operations.ListAuditLog.Input.Query.KindPayload(rawValue: $0.rawValue) }
            let page = try await client.listAuditLog(
                query: .init(kind: kind, q: search.isEmpty ? nil : search, limit: query.limit, cursor: query.cursor)
            ).ok.body.json
            return ActivityBatch(
                entries: page.data.map { entry in
                    let who = entry.actor.value?.value1?.name ?? entry.actor.value?.value2?.name.rawValue
                    return ActivityEntry(
                        id: entry.id, date: Self.date(entry.createdAt), who: who, action: entry.action,
                        resourceType: entry.resourceType, resourceID: entry.resourceId, address: entry.clientIp)
                },
                next: page.nextCursor)
        }
    }

    func storedSettings() async throws(OwnerFailure) -> InstanceSettingsSnapshot {
        try await run { client in
            let instanceID = try await client.getConfig().ok.body.json.instanceId
            let listed = try await client.listSettings().ok.body.json
            var settings: [String: StoredSetting] = [:]
            for entry in listed.data {
                let value = Self.value(entry.value.value)
                settings[entry.key] = StoredSetting(
                    key: entry.key, value: entry.secret ? nil : value, defaultValue: entry.secret ? nil : Self.value(entry._default.value),
                    isStored: entry.secret ? (entry.set ?? false) : entry.stored.value != nil, isSecret: entry.secret,
                    isSet: entry.secret ? (entry.set ?? false) : value != nil)
            }
            return InstanceSettingsSnapshot(
                instanceID: instanceID, settings: settings,
                startUp: listed.startOnly.map { StartUpSetting(name: $0.name, isSecret: $0.secret, isSet: $0.set) })
        }
    }

    private static func value(_ raw: (any Sendable)?) -> SettingValue? {
        switch raw {
        case let value as Bool: .bool(value)
        case let value as Int: .int(value)
        case let value as Double: .number(value)
        case let value as String: .text(value)
        default: nil
        }
    }

    func change(_ changes: [String: StoredSettingChange], instanceID: String?) async throws(OwnerFailure) {
        try await run(plainConflict: ClientOwnerCalls.configConflict) { client in
            var body = Operations.UpdateConfig.Input.Body.JsonPayload()
            for (key, change) in changes {
                guard Self.apply(key, change, to: &body) else {
                    throw OwnerFailure.failed(String(localized: "The app can’t change this setting."))
                }
            }
            _ = try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok
        }
    }

    /// Puts one change into the body under the setting's own field. A setting the pages do not change is refused here, so
    /// nothing else can be sent by mistake.
    private static func apply(_ key: String, _ change: StoredSettingChange, to body: inout Operations.UpdateConfig.Input.Body.JsonPayload) -> Bool {
        func whole(_ keyPath: WritableKeyPath<Operations.UpdateConfig.Input.Body.JsonPayload, MarfaNullable<Int>?>) -> Bool {
            switch change {
            case .set(let value): guard let number = value.int else { return false }; body[keyPath: keyPath] = .value(number)
            case .clear: body[keyPath: keyPath] = .null
            }
            return true
        }
        func flag(_ keyPath: WritableKeyPath<Operations.UpdateConfig.Input.Body.JsonPayload, MarfaNullable<Bool>?>) -> Bool {
            switch change {
            case .set(let value): guard let flag = value.bool else { return false }; body[keyPath: keyPath] = .value(flag)
            case .clear: body[keyPath: keyPath] = .null
            }
            return true
        }
        func text(_ keyPath: WritableKeyPath<Operations.UpdateConfig.Input.Body.JsonPayload, MarfaNullable<String>?>) -> Bool {
            switch change {
            case .set(.text(let text)): body[keyPath: keyPath] = .value(text)
            case .set: return false
            case .clear: body[keyPath: keyPath] = .null
            }
            return true
        }
        switch key {
        case "max_request_bytes": return whole(\.maxRequestBytes)
        case "max_bulk_request_bytes": return whole(\.maxBulkRequestBytes)
        case "rate_limit_requests": return whole(\.rateLimitRequests)
        case "rate_limit_keys_requests": return whole(\.rateLimitKeysRequests)
        case "rate_limit_window_seconds": return whole(\.rateLimitWindowSeconds)
        case "enrichment_max_blob_bytes": return whole(\.enrichmentMaxBlobBytes)
        case "enrichment_max_text_chars": return whole(\.enrichmentMaxTextChars)
        case "enrichment_max_attempts": return whole(\.enrichmentMaxAttempts)
        case "event_stream_max_viewers": return whole(\.eventStreamMaxViewers)
        case "inbound_max_bytes": return whole(\.inboundMaxBytes)
        case "rate_limit_inbound_requests": return whole(\.rateLimitInboundRequests)
        case "inbound_backlog_deliveries": return whole(\.inboundBacklogDeliveries)
        case "mcp_fetch_max_bytes": return whole(\.mcpFetchMaxBytes)
        case "mcp_fetch_timeout_seconds": return whole(\.mcpFetchTimeoutSeconds)
        case "rate_limit_enabled": return flag(\.rateLimitEnabled)
        case "mcp_fetch_enabled": return flag(\.mcpFetchEnabled)
        case "heartbeat_enabled": return flag(\.heartbeatEnabled)
        case "error_reporting_enabled": return flag(\.errorReportingEnabled)
        case "telemetry_enabled": return flag(\.telemetryEnabled)
        case "heartbeat_url": return text(\.heartbeatUrl)
        case "posthog_host": return text(\.posthogHost)
        case "posthog_project_token": return text(\.posthogProjectToken)
        case "otel_exporter_otlp_endpoint": return text(\.otelExporterOtlpEndpoint)
        case "otel_exporter_otlp_headers": return text(\.otelExporterOtlpHeaders)
        default: return false
        }
    }
}
