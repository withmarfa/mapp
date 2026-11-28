import Foundation
import Marfa
import MarfaAPI

/// `TypeCalls` over the package's generated client. A change is built by `TypeDefinitionEdit`, the one place a type's
/// replacement is made, so a field's edit and a page's edit both send the type back as the server holds it.
nonisolated struct ServerTypeCalls: TypeCalls {
    let client: @Sendable () throws -> Client

    func types() async throws(TypeFailure) -> TypeListing {
        try await run { client in
            let listed = try await client.listTypes().ok.body.json.data
            // A plugin's own title is a nicety: without it the name is made readable.
            let plugins = (try? await client.listPlugins().ok.body.json.data) ?? []
            return TypeListing(types: listed.map(Self.record), pluginTitles: Dictionary(plugins.map { ($0.name, $0.title) }) { first, _ in first })
        }
    }

    func reading(of type: String) async throws(TypeFailure) -> TypeReading {
        try await run { client in
            let read = try await client.getType(path: .init(id: type)).ok.body.json
            return TypeReading(
                guidance: read.value1.guidance, plural: read.value1.plural,
                ancestors: (read.value2.ancestorGuidance ?? []).map { TypeGuidanceRecord(type: $0._type, guidance: $0.guidance) })
        }
    }

    func change(_ type: String, _ edit: TypeEdit) async throws(TypeFailure) {
        try await run { client in
            try await TypeDefinitionEdit.run(
                Self.change(edit), to: type,
                read: { try await client.listTypes().ok.body.json.data },
                replace: { _ = try await client.replace(itemType: type, with: $0) })
        }
    }

    func addType(_ type: NewTypeRecord) async throws(TypeFailure) {
        try await run { client in
            // A new type declares no field of its own, with a parent or without (`types/register-no-fields` asks only
            // for a `fields` object). The icon is the type's own, as its author's.
            var definition = Components.Schemas.TypeDefinitionInput(
                fields: .init(additionalProperties: [:]), parent: type.parent, label: type.label,
                plural: type.plural.isEmpty ? nil : type.plural, id: type.id)
            if let icon = type.icon { definition.displayHints = .init(icon: icon) }
            _ = try await client.register(itemType: definition)
        }
    }

    func delete(_ type: String, force: Bool) async throws(TypeFailure) {
        try await run { client in try await client.delete(itemType: type, force: force, revision: nil) }
    }

    func previewMove(of type: String, to target: String) async throws(TypeFailure) -> TypeMovePreview {
        try await run { client in
            let preview = try await client.previewMove(ofType: type, to: target)
            return TypeMovePreview(items: preview.matched, ids: preview.ids, settings: preview.settings.map(Self.setting))
        }
    }

    func move(_ type: String, to target: String) async throws(TypeFailure) -> TypeMoveResult {
        try await run { client in
            let started = try await client.startMove(ofType: type, to: target)
            let job = try await client.follow(moveJob: started.id)
            let result = job.result
            var problem: String?
            switch job.status {
            case .completed: problem = result?.settingsError?.message
            case .failed, .canceled: problem = job.error ?? String(localized: "The move stopped before it finished.")
            case .queued, .inProgress: problem = String(localized: "The move stopped before it finished.")
            }
            return TypeMoveResult(
                moved: job.succeeded, failed: job.errored, remaining: result?.remaining ?? 0, remainingHidden: result?.remainingHidden ?? false,
                problem: problem)
        }
    }

    static func setting(_ setting: Components.Schemas.TypeSetting) -> TypeSettingRecord {
        let kind: TypeSettingRecord.Kind =
            switch setting.kind {
            case .folder: .folder
            case .view: .view
            case .webhook: .webhook
            }
        return TypeSettingRecord(
            kind: kind, id: setting.id, field: setting.field,
            blocked: setting.reason.map { block($0.rawValue, message: setting.message) })
    }

    /// A setting as a `type_move_blocked` refusal names it in `details.settings`.
    static func setting(_ object: JSONObject) -> TypeSettingRecord? {
        let kind: TypeSettingRecord.Kind
        switch object["kind"]?.string {
        case "folder": kind = .folder
        case "view": kind = .view
        case "webhook": kind = .webhook
        default: return nil
        }
        return TypeSettingRecord(
            kind: kind, id: object["id"]?.string, field: object["field"]?.string ?? "",
            blocked: object["reason"]?.string.map { block($0, message: object["message"]?.string) })
    }

    private static func block(_ reason: String, message: String?) -> TypeSettingRecord.Block {
        switch reason {
        case "not_permitted": .notPermitted
        case "filter_term": .filterTerm
        case "placement_conflict": .placementConflict
        case "subtypes": .subtypes
        default: .other(message ?? reason)
        }
    }

    // MARK: Reading

    static func record(_ listed: TypeDefinitionEdit.Listed) -> TypeRecord {
        let own = listed.value1
        let origin: TypeOrigin =
            switch listed.value2.provenance.origin {
            case .platform: .platform
            case .registered: .registered
            case .plugin: .plugin
            case .unknown: .unknown
            }
        let fields = own.fields.additionalProperties.map { key, field in
            TypeFieldRecord(
                key: key, label: field.label, kind: field._type.rawValue, meaning: field.description, isRequired: field.required ?? false,
                isSearchable: field.searchable ?? true, longest: field.maxLength, choices: field.enumValues ?? [],
                statusWords: (field.statusValues ?? []).map {
                    StatusWordRecord(value: $0.value, group: $0.group.rawValue, meaning: $0.description)
                })
        }
        return TypeRecord(
            id: own.id, label: own.label ?? own.id, plural: own.plural, description: own.description, guidance: own.guidance,
            parent: own.parent, origin: origin,
            plugin: listed.value2.provenance.plugin.map { .init(name: $0.name, version: $0.version) },
            creator: listed.value2.provenance.createdBy.flatMap { created in
                TypeCreator.Kind(rawValue: created.kind.rawValue).map { TypeCreator(kind: $0, id: created.id, name: created.name) }
            },
            icon: own.displayHints?.icon, fields: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) }),
            feedWindow: own.retentionPolicy?.feedDays.map { $0.value.map { .days(Int($0)) } ?? .never },
            mergeStrategy: own.mergePolicy?._default?.rawValue, versionWindow: versionWindow(own.versionPolicy))
    }

    /// The windows a type declares: one length for all three, which is what the page sets, or another shape it only shows.
    static func versionWindow(_ policy: Components.Schemas.VersionPolicy?) -> VersionWindow? {
        guard let policy else { return nil }
        let windows = [policy.recentDays, policy.dailySnapshotDays, policy.weeklySnapshotDays]
        if windows.allSatisfy({ $0 == nil }) { return nil }
        if let days = policy.recentDays, days > 0, windows.allSatisfy({ $0 == days }) { return .days(days) }
        return .custom
    }

    static func change(_ edit: TypeEdit) -> TypeDefinitionEdit.TypeChange {
        switch edit {
        case .label(let text): .label(text)
        case .plural(let text): .plural(text)
        case .description(let text): .description(text)
        case .guidance(let text): .guidance(text)
        case .parent(let id): .parent(id)
        case .addWord(let group, let value): .addWord(group: group, value: value)
        case .wordMeaning(let value, let text): .wordMeaning(value: value, text: text)
        case .addField(let new): .addField(new)
        case .field(let key, let change): .field(key: key, change)
        case .removeField(let key): .removeField(key: key)
        case .feedWindow(let window): .feedWindow(window)
        case .mergeStrategy(let name): .mergeStrategy(name)
        case .versionWindow(let days): .versionWindow(days)
        }
    }

    // MARK: Failing

    private func run<Result>(_ call: (Client) async throws -> Result) async throws(TypeFailure) -> Result {
        let client: Client
        do { client = try self.client() } catch { throw Self.failure(error) }
        do {
            return try await call(client)
        } catch {
            throw Self.failure(error)
        }
    }

    /// The server refused what was written when it names a field in `details.errors`; the page shows its words on that
    /// field. Anything else is told as an owner's call is.
    static func failure(_ error: any Error) -> TypeFailure {
        if let failure = error as? TypeFailure { return failure }
        if let failure = error as? TypeSchemaFailure {
            switch failure {
            case .pluginType: return .pluginType
            case .changedOnServer: return .changedOnServer
            case .refused(let reason): return .invalid(field: nil, message: reason)
            case .notPermitted: return .owner(.notPermitted(InstancePermission.schemaWrite.rawValue))
            case .keyRefused: return .owner(.signedOut)
            case .unreachable: return .owner(.unreachable)
            case .unsupported: return .owner(.unsupported)
            case .failed(let message): return .owner(.failed(message))
            }
        }
        if let known = ClientOwnerCalls.marfaError(error) {
            switch known {
            case .canceled: return .canceled
            case .validation(let code, let message, let details, let server) where code == "invalid_schema":
                let first = (details ?? server?.details)?.object?["errors"]?.array?.first?.object
                return .invalid(field: first?["field"]?.string, message: first?["message"]?.string ?? message)
            case .server(let status, let code, _, let details, let server) where status == 409 && code == "type_in_use":
                let object = (details ?? server?.details)?.object
                return .inUse(items: object?["item_count"]?.number.map { Int($0) }, settings: object?["settings"]?.array?.count ?? 0)
            case .server(let status, let code, _, let details, let server) where status == 409 && code == "type_move_blocked":
                let object = (details ?? server?.details)?.object
                let settings = object?["settings"]?.array?.compactMap { $0.object.flatMap(Self.setting) } ?? []
                return .moveBlocked(settings: settings, tables: object?["tables"]?.array?.compactMap(\.string) ?? [])
            case .server(let status, let code, _, let details, let server) where status == 409 && code == "type_has_subtypes":
                return .hasSubtypes((details ?? server?.details)?.object?["subtype_ids"]?.array?.compactMap(\.string) ?? [])
            case .forbidden(_, _, let server):
                // A sign-in that lacks `schema.write` is told the permission it needs (`required_scope`); only a sign-in that
                // holds it and is an app's is refused for the guidance alone.
                let details = server?.details?.object
                let changes = details?["changes"]?.array?.compactMap(\.string) ?? []
                if changes.contains("guidance"), details?["required_scope"] == nil { return .guidanceByApp }
            default: break
            }
        }
        return .owner(ClientOwnerCalls.failure(error))
    }
}
