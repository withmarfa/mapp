import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime
import os

/// The calls that ask the Marfa server itself instead of the working copy: an item's snapshots (Version History),
/// the server's own settings (This Marfa), the owner's icon for a type, changes to a type's fields, the names, marks and counts of sources
/// and an item's `https` link.
/// They need a connection, so they fail while the server cannot be reached. Every call goes through the package's `Server`
/// (This Marfa's through the generated `Client` made from it), with the address and the sign-in read
/// from the Keychain on each call, so a sign-in the person has since made again is the one used. Both go over
/// `URLSession`, so App Transport Security applies to a plain http address, unlike the copy, which goes through the
/// package's core.
nonisolated struct MarfaServerCalls: ItemHistorySource, InstanceConfigSource, TypeIconSource, TypeSchemaSource, SourceNameSource {
    let connection: MarfaConnection
    let signIns: any SignIns
    /// How long a call waits for the server before it fails, so an unreachable server never leaves a page waiting.
    var timeout = Server.defaultTimeout

    /// How a call to the server ends, in the words of the page that made it.
    enum Ending: Error, Hashable {
        case unreachable, keyRefused, notPermitted
        /// The server holds nothing at the address asked for.
        case notFound(String)
        /// Another instance answers at the address.
        case instanceChanged(String)
        /// The server's own sentence for why it refused the request.
        case refused(String)
        case failed(String)
    }

    /// The server with the sign-in kept for its address. A sign-in the Keychain cannot give is told as that, never as
    /// missing or ended, and nothing is sent.
    func server() throws(Ending) -> Server {
        let server: Server?
        do { server = try signIns.server(for: connection) } catch { throw .failed(Words.signInUnreadable) }
        guard let server else { throw .keyRefused }
        return server
    }

    /// The package's client over the server, for the Marfa's pages of Settings, which make their own calls.
    func client() throws(Ending) -> Client {
        Client(try server(), timeout: timeout)
    }

    /// What the package's error stands for, by its own classes: away, a refused key, or what the server said.
    static func ending(_ error: any Error) -> Ending {
        guard let error = marfaError(in: error) else {
            Telemetry.logger(.library).error("A server call failed: \(String(describing: error))")
            return .failed(Words.syncFailed)
        }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .keyRefused }
        switch error {
        case .forbidden: return .notPermitted
        case .notFound: return .notFound(Words.message(for: error))
        case .validation(_, let message, _, _): return .refused(message)
        case .instanceChanged: return .instanceChanged(Words.message(for: error))
        default: return .failed(Words.message(for: error))
        }
    }

    /// Returns a `MarfaError` directly or from an OpenAPI `ClientError`.
    static func marfaError(in error: any Error) -> MarfaError? {
        var current = error
        for _ in 0..<4 {
            if let known = current as? MarfaError { return known }
            guard let wrapped = current as? ClientError else { return nil }
            current = wrapped.underlyingError
        }
        return nil
    }

    // MARK: Version History (`GET /items/{id}/versions`)

    @concurrent func page(of id: ItemID, after cursor: String?, limit: Int) async throws(ItemHistoryFailure) -> ItemHistoryPage {
        do {
            let page = try await server().snapshots(ofItem: id.rawValue, after: cursor, limit: limit, timeout: timeout)
            return ItemHistoryPage(snapshots: page.snapshots.map(Self.snapshot), next: page.next)
        } catch let ending as Ending {
            throw Self.historyFailure(ending)
        } catch {
            throw Self.historyFailure(Self.ending(error))
        }
    }

    static func historyFailure(_ ending: Ending) -> ItemHistoryFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .notFound: .unavailable
        case .instanceChanged(let message), .refused(let message), .failed(let message): .failed(message)
        }
    }

    static func snapshot(_ version: Marfa.ItemSnapshot) -> ItemSnapshot {
        ItemSnapshot(
            id: version.id, version: version.version, type: TypeID(version.type),
            properties: properties(version.properties), replaced: version.createdAt,
            writer: version.writer.map { writer in
                ItemSnapshot.Writer(kind: kind(writer.kind), name: writer.name)
            })
    }

    private static func kind(_ kind: Marfa.ItemSnapshot.Writer.Kind) -> ItemSnapshot.Writer.Kind {
        switch kind {
        case .browser: .browser
        case .app: .app
        case .key: .key
        case .local: .local
        case .other: .key
        }
    }

    private static func properties(_ object: JSONObject) -> [String: PropertyValue] {
        guard case .object(let properties) = MarfaMapping.value(.object(object)) else { return [:] }
        return properties
    }

    // MARK: This Marfa (`GET` and `PATCH /config`, which need `config.manage`)

    @concurrent func read() async throws(InstanceConfigFailure) -> InstanceConfig {
        do {
            return Self.config(try await Client(server(), timeout: timeout).getConfig().ok.body.json)
        } catch let ending as Ending {
            throw Self.configFailure(ending)
        } catch {
            throw Self.configFailure(Self.ending(error))
        }
    }

    @concurrent func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig {
        do {
            let body = Self.patch(patch)
            let headers = Operations.UpdateConfig.Input.Headers(xMarfaInstanceId: instanceID)
            return Self.config(
                try await Client(server(), timeout: timeout).updateConfig(headers: headers, body: .json(body)).ok.body.json)
        } catch let ending as Ending {
            throw Self.configFailure(ending)
        } catch {
            throw Self.configFailure(Self.ending(error))
        }
    }

    static func configFailure(_ ending: Ending) -> InstanceConfigFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .instanceChanged: .instanceChanged
        case .refused(let reason): .refused(reason)
        case .notFound(let message), .failed(let message): .failed(message)
        }
    }

    static func config(_ answer: Components.Schemas.InstanceConfig) -> InstanceConfig {
        var config = InstanceConfig()
        config.instanceID = answer.instanceId
        func number(_ setting: InstanceSetting, _ value: Int?) { config.values[setting] = value.map { .number($0) } }
        func megabytes(_ setting: InstanceSetting, _ bytes: Int?) {
            config.values[setting] = bytes.map { .number(Int((Double($0) / Double(InstanceSetting.bytesPerMegabyte)).rounded())) }
        }
        func flag(_ setting: InstanceSetting, _ value: Bool?) { config.values[setting] = value.map { .flag($0) } }
        config.values[.name] = answer.name.map { .text($0) }
        number(.trashRetentionDays, answer.trashRetentionDays)
        number(.versionRecentDays, answer.versionRecentDays)
        number(.versionDailyDays, answer.versionDailySnapshotDays)
        number(.versionWeeklyDays, answer.versionWeeklySnapshotDays)
        number(.versionMaxVersions, answer.versionMaxVersions)
        number(.auditRetentionDays, answer.auditRetentionDays)
        number(.eventLogRetentionDays, answer.eventLogRetentionDays)
        number(.rowLogRetentionDays, answer.rowLogRetentionDays)
        number(.inboundHandledRetentionDays, answer.inboundHandledRetentionDays)
        number(.inboundPendingRetentionDays, answer.inboundPendingRetentionDays)
        number(.blobMinCopies, answer.blobMinCopies)
        megabytes(.diskReserveMegabytes, answer.diskReserveBytes)
        flag(.enrichmentEnabled, answer.enrichmentEnabled)
        flag(.enrichmentOcrEnabled, answer.enrichmentOcrEnabled)
        flag(.mcpFetchEnabled, answer.mcpFetchEnabled)
        megabytes(.mcpFetchMaxMegabytes, answer.mcpFetchMaxBytes)
        flag(.blobCleanupEnabled, answer.blobCleanupEnabled)
        number(.blobCleanupGraceSeconds, answer.blobCleanupGraceSeconds)
        return config
    }

    /// A change that names only the settings in `patch`: a field left out stays as it is, and a cleared one is removed.
    static func patch(_ patch: InstanceConfigPatch) -> Operations.UpdateConfig.Input.Body.JsonPayload {
        func number(_ setting: InstanceSetting, scale: Int = 1) -> MarfaNullable<Int>? {
            if patch.clear.contains(setting) { return .null }
            if case .number(let number)? = patch.values[setting] { return .value(number * scale) }
            return nil
        }
        func flag(_ setting: InstanceSetting) -> MarfaNullable<Bool>? {
            if patch.clear.contains(setting) { return .null }
            if case .flag(let flag)? = patch.values[setting] { return .value(flag) }
            return nil
        }
        var change = Operations.UpdateConfig.Input.Body.JsonPayload()
        if patch.clear.contains(.name) {
            change.name = .null
        } else if case .text(let text)? = patch.values[.name] {
            change.name = .value(text)
        }
        change.trashRetentionDays = number(.trashRetentionDays)
        change.versionRecentDays = number(.versionRecentDays)
        change.versionDailySnapshotDays = number(.versionDailyDays)
        change.versionWeeklySnapshotDays = number(.versionWeeklyDays)
        change.versionMaxVersions = number(.versionMaxVersions)
        change.auditRetentionDays = number(.auditRetentionDays)
        change.eventLogRetentionDays = number(.eventLogRetentionDays)
        change.rowLogRetentionDays = number(.rowLogRetentionDays)
        change.inboundHandledRetentionDays = number(.inboundHandledRetentionDays)
        change.inboundPendingRetentionDays = number(.inboundPendingRetentionDays)
        change.blobMinCopies = number(.blobMinCopies)
        change.diskReserveBytes = number(.diskReserveMegabytes, scale: InstanceSetting.bytesPerMegabyte)
        change.enrichmentEnabled = flag(.enrichmentEnabled)
        change.enrichmentOcrEnabled = flag(.enrichmentOcrEnabled)
        change.mcpFetchEnabled = flag(.mcpFetchEnabled)
        change.mcpFetchMaxBytes = number(.mcpFetchMaxMegabytes, scale: InstanceSetting.bytesPerMegabyte)
        change.blobCleanupEnabled = flag(.blobCleanupEnabled)
        change.blobCleanupGraceSeconds = number(.blobCleanupGraceSeconds)
        return change
    }

    // MARK: Type icons (`PUT` and `DELETE /types/{id}/icon`, which need `schema.write` and write on the type)

    @concurrent func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String? {
        do {
            return try await server().setTypeIcon(icon, ofType: type.rawValue, timeout: timeout)
        } catch let ending as Ending {
            throw Self.iconFailure(ending)
        } catch {
            throw Self.iconFailure(Self.ending(error))
        }
    }

    static func iconFailure(_ ending: Ending) -> TypeIconFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .refused(let reason): .refused(reason)
        case .notFound(let message), .instanceChanged(let message), .failed(let message): .failed(message)
        }
    }

    // MARK: Type fields (`GET /types`, then `PUT /types/{id}`, which need `schema.write` and write on the type)

    /// The server has no version guard on `PUT /types/{id}`: `version` is a number for callers to track and is never
    /// compared. So the type's own definition is read again right before the replacement and must still hold the field
    /// as the page showed it. The server judges each write against the registry as it stands when it lands
    /// (`types/write-race`), so only the moment between the two calls is open.
    @concurrent func apply(_ plan: FieldEditPlan) async throws(TypeSchemaFailure) {
        do {
            let client = try Client(server(), timeout: timeout)
            try await TypeDefinitionEdit.run(
                plan,
                read: { try await client.listTypes().ok.body.json.data },
                replace: { _ = try await client.replace(itemType: plan.type.rawValue, with: $0) })
        } catch let failure as TypeSchemaFailure {
            throw failure
        } catch let ending as Ending {
            throw Self.schemaFailure(ending)
        } catch {
            throw Self.schemaFailure(Self.ending(error))
        }
    }

    static func schemaFailure(_ ending: Ending) -> TypeSchemaFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .refused(let reason): .refused(reason)
        case .notFound: .changedOnServer
        case .instanceChanged(let message), .failed(let message): .failed(message)
        }
    }

    // MARK: Sources (`GET /sources`, `PATCH /source`, `GET /items/stats?by=source`)

    @concurrent func sources() async throws(SourceEditFailure) -> [SourceInfo] {
        do {
            return try await server().sources(timeout: timeout).map(Self.info)
        } catch let ending as Ending {
            throw Self.sourceFailure(ending)
        } catch {
            throw Self.sourceFailure(Self.ending(error))
        }
    }

    /// The items the library lists: the active ones in either tier, without parts (`part eq false`), which are the
    /// files attached to an item and the other items that live with a host. The server leaves out hidden items
    /// (`system.*` and `app.*`, `items/hidden-types`) and the ones the key cannot read by itself.
    @concurrent func counts() async throws(SourceEditFailure) -> [String: Int] {
        do {
            return try await server().itemCountsBySource(state: "active", filter: "part eq false", timeout: timeout)
        } catch let ending as Ending {
            throw Self.sourceFailure(ending)
        } catch {
            throw Self.sourceFailure(Self.ending(error))
        }
    }

    @concurrent func update(
        _ code: String, name: SourceFieldChange?, mark: SourceFieldChange?
    ) async throws(SourceEditFailure) -> SourceInfo {
        do {
            return Self.info(
                try await server().updateSource(code, name: name.map(Self.change), mark: mark.map(Self.change), timeout: timeout))
        } catch let ending as Ending {
            throw Self.sourceFailure(ending)
        } catch {
            throw Self.sourceFailure(Self.ending(error))
        }
    }

    static func info(_ source: Marfa.ItemSource) -> SourceInfo {
        SourceInfo(code: source.code, name: source.name, mark: source.mark, nameOrigin: source.nameOrigin)
    }

    static func change(_ change: SourceFieldChange) -> SettingChange<String> {
        switch change {
        case .set(let value): .set(value)
        case .clear: .clear
        }
    }

    static func sourceFailure(_ ending: Ending) -> SourceEditFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .refused(let reason): .refused(reason)
        case .notFound(let message), .instanceChanged(let message), .failed(let message): .failed(message)
        }
    }
}
