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

    func addChild(id: String, label: String, below parent: String) async throws(TypeFailure) {
        try await run { client in
            // A child inherits its parent's fields, so it declares none of its own (`types/register-no-fields`
            // asks only for a `fields` object).
            let definition = Components.Schemas.TypeDefinitionInput(
                fields: .init(additionalProperties: [:]), parent: parent, label: label, id: id)
            _ = try await client.register(itemType: definition)
        }
    }

    func delete(_ type: String) async throws(TypeFailure) {
        try await run { client in try await client.delete(itemType: type) }
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
            icon: own.displayHints?.icon, fields: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) }),
            feedWindow: own.retentionPolicy?.feedDays.map { $0.value.map { .days(Int($0)) } ?? .never },
            mergeStrategy: own.mergePolicy?._default?.rawValue)
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
        case .addField(let key, let label, let kind, let choices): .addField(key: key, label: label, kind: kind, choices: choices)
        case .field(let key, let change): .field(key: key, change)
        case .removeField(let key): .removeField(key: key)
        case .feedWindow(let window): .feedWindow(window)
        case .mergeStrategy(let name): .mergeStrategy(name)
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
