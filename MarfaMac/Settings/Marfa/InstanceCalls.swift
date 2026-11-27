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
    /// Item counts from `GET /items/stats`. A missing key means zero. The call needs no owner permission of its own.
    func itemStats(_ query: UsageStatsQuery) async throws(OwnerFailure) -> [String: Int]
    /// Versions, files and the database from `GET /metrics`. Needs `instance.read`.
    func usageMetrics() async throws(OwnerFailure) -> UsageMetrics
    func storedSettings() async throws(OwnerFailure) -> InstanceSettingsSnapshot
    /// Sends exactly `changes` to the instance that was read. If another instance answers, nothing is written and the call
    /// throws `conflict`.
    func change(_ changes: [String: StoredSettingChange], instanceID: String?) async throws(OwnerFailure)
}

/// `InstanceCalls` over the package's generated client. Item counts use the server as well: the generated client does
/// not hold `GET /items/stats`.
nonisolated struct ClientInstanceCalls: InstanceCalls {
    let client: @Sendable () throws -> Client
    let server: @Sendable () throws -> Server

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

    /// The same instant the audit log is read with, so a bound is the instant the page asked for.
    private static func stamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    private static func count(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
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

    func itemStats(_ query: UsageStatsQuery) async throws(OwnerFailure) -> [String: Int] {
        do {
            return try await Self.itemCounts(query, server: server)
        } catch {
            throw ClientOwnerCalls.failure(error)
        }
    }

    /// The names and values `GET /items/stats` is asked with. `itemCountsBySource` cannot pass a grouping or a date.
    static func statsQueryItems(_ query: UsageStatsQuery) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "by", value: query.grouping == .type ? "type" : "source")]
        if let after = query.updatedAfter { items.append(URLQueryItem(name: "updated_after", value: stamp(after))) }
        if let before = query.updatedBefore { items.append(URLQueryItem(name: "updated_before", value: stamp(before))) }
        return items
    }

    /// One `GET /items/stats`. A refused token is renewed by the package's own stats call, then this request goes once more.
    private static func itemCounts(
        _ query: UsageStatsQuery, server make: @Sendable () throws -> Server, renewed: Bool = false
    ) async throws(MarfaError) -> [String: Int] {
        let server: Server
        do {
            server = try make()
        } catch let error as MarfaError {
            throw error
        } catch {
            throw .signedOut(origin: "", message: "the sign-in could not be read")
        }
        let (response, data) = try await exchange(statsRequest(query, server: server))
        if response.statusCode == 401, !renewed {
            _ = try await server.itemCountsBySource()
            return try await itemCounts(query, server: make, renewed: true)
        }
        let origin = origin(of: server)
        let status = UInt16(clamping: response.statusCode)
        if (300..<400).contains(response.statusCode) {
            throw .redirected(
                origin: origin, status: status, location: response.value(forHTTPHeaderField: "Location"),
                message: "\(origin) answered with a redirect, which was not followed", server: nil)
        }
        guard response.statusCode == 200 else { throw refusal(status: status, data: data, origin: origin) }
        let contract = response.value(forHTTPHeaderField: "X-Marfa-Contract")
        guard contract == String(marfaContractVersion) else {
            throw .contractMismatch(
                served: contract, expected: UInt64(marfaContractVersion), status: status, writeSent: false,
                message: "\(origin) speaks a different contract", server: nil)
        }
        return try counts(from: data)
    }

    private static func statsRequest(_ query: UsageStatsQuery, server: Server) throws(MarfaError) -> URLRequest {
        guard var components = URLComponents(url: server.url, resolvingAgainstBaseURL: false) else {
            throw .invalid(message: "the server address could not be used")
        }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") { base.removeLast() }
        components.percentEncodedPath = base + "/items/stats"
        let items = statsQueryItems(query)
        components.percentEncodedQuery = items.map { "\(queryPart($0.name))=\(queryPart($0.value ?? ""))" }.joined(separator: "&")
        guard let url = components.url else { throw .invalid(message: "the item counts could not be asked for") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let parts = Server.defaultTimeout.components
        request.timeoutInterval = TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(String(marfaContractVersion), forHTTPHeaderField: "X-Marfa-Contract")
        request.setValue("Bearer \(server.key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func exchange(_ request: URLRequest) async throws(MarfaError) -> (HTTPURLResponse, Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: StatsNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw .canceled(message: "the request was canceled")
        } catch let error as URLError {
            throw transport(error)
        } catch {
            throw .network(message: "the server could not be reached")
        }
        guard let http = response as? HTTPURLResponse else {
            throw .network(message: "the server did not answer with http")
        }
        return (http, data)
    }

    private static func transport(_ error: URLError) -> MarfaError {
        switch error.code {
        case .cancelled: .canceled(message: "the request was canceled")
        case .timedOut: .network(message: "the server did not answer in time")
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            .noConnection(message: "the server could not be reached")
        default: .network(message: "the server could not be reached")
        }
    }

    private static func refusal(status: UInt16, data: Data, origin: String) -> MarfaError {
        let told = refusalFields(data)
        let code = told?.code ?? "error"
        let message = told?.message ?? "\(origin) refused the item counts"
        switch status {
        case 401: return .unauthorized(code: code, message: message, server: nil)
        case 403: return .forbidden(code: code, message: message, server: nil)
        case 404: return .notFound(code: code, message: message, server: nil)
        default: return .server(status: status, code: code, message: message, details: nil, server: nil)
        }
    }

    private static func refusalFields(_ data: Data) -> (code: String, message: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let body = (object["error"] as? [String: Any]) ?? object
        let code = body["code"] as? String
        let message = body["message"] as? String
        guard code != nil || message != nil else { return nil }
        return (code ?? "error", message ?? "the server refused the item counts")
    }

    private static func counts(from data: Data) throws(MarfaError) -> [String: Int] {
        let object: [String: Double]
        do {
            object = try JSONDecoder().decode([String: Double].self, from: data)
        } catch {
            throw .decoding(message: "the item counts could not be read")
        }
        var counts: [String: Int] = [:]
        for (key, value) in object {
            if let count = count(value) { counts[key] = count }
        }
        return counts
    }

    private static func origin(of server: Server) -> String {
        guard let host = server.url.host, !host.isEmpty else { return server.url.absoluteString }
        var text = "\(server.url.scheme ?? "https")://\(host)"
        if let port = server.url.port { text += ":\(port)" }
        return text
    }

    /// `+` is escaped too: a server reads a bare `+` in a query as a space.
    private static func queryPart(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func usageMetrics() async throws(OwnerFailure) -> UsageMetrics {
        try await run { client in
            let metrics = try await client.getInstanceMetrics().ok.body.json
            return UsageMetrics(
                versionCount: metrics.storage.rows.versions.flatMap(Self.count),
                fileBytes: Self.count(metrics.blobs.totalBytes) ?? 0,
                databaseBytes: metrics.storage.databaseBytes.flatMap(Self.count))
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
            do {
                _ = try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok
            } catch {
                if changes["allow_private_addresses"] == .set(.bool(false)), let line = StoredSettingWording.notPublic(error) {
                    throw OwnerFailure.refused(line)
                }
                throw error
            }
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
        case "allow_private_addresses": return flag(\.allowPrivateAddresses)
        case "heartbeat_url": return text(\.heartbeatUrl)
        case "posthog_host": return text(\.posthogHost)
        case "posthog_project_token": return text(\.posthogProjectToken)
        case "otel_exporter_otlp_endpoint": return text(\.otelExporterOtlpEndpoint)
        case "otel_exporter_otlp_headers": return text(\.otelExporterOtlpHeaders)
        default: return false
        }
    }
}

/// Refuses a redirect, so the sign-in's token stays on the server that was asked.
private nonisolated final class StatsNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
