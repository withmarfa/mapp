import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

// What a connector's mapping screen asks of the server, in values of its own. Every call needs `connectors.manage`.

/// Where a field of the target type gets its value.
nonisolated enum MappingSource: Hashable, Sendable {
    /// A field of the kind's own type.
    case field(String)
    case fixed(ConnectorSettingValue)
    /// Jinja text the connector renders. It is read only for writing back, so it cannot be written back.
    case template(String)
}

/// What one kind of a connector brings, as the server stores it.
nonisolated struct KindMapping: Hashable, Sendable {
    var enabled: Bool
    var targetType: String
    var tier: KeyTier
    /// A status word of the kind's own type, by the word of the target type it becomes.
    var statusOverrides: [String: String]
    var fields: [String: MappingSource]
}

/// A rewrite of existing items that was asked for and the connector has not carried out.
nonisolated struct PendingRewrite: Identifiable, Hashable, Sendable {
    let number: Int
    var kinds: [String]
    var requested: Date?

    var id: Int { number }
}

nonisolated struct ConnectorMappingReading: Hashable, Sendable {
    var version: Int
    var kinds: [String: KindMapping]
    var rewrites: [PendingRewrite]
}

/// One thing the server refused in a mapping, by its place in the kind's entry (`target_type`, `fields.client`,
/// `fields.client.fixed`).
nonisolated struct MappingFault: Hashable, Sendable {
    var path: String
    var message: String
}

/// How a save ended, where the server answered with something the page keeps the draft for.
nonisolated enum MappingSaveOutcome: Hashable, Sendable {
    case saved(ConnectorMappingReading)
    /// The mapping changed since it was read. `current` is the version it is at now, where the server said.
    case stale(current: Int?)
    case refused([MappingFault])
}

/// An item as the connector rendered it under a mapping.
nonisolated struct MappingPreviewItem: Hashable, Sendable {
    var type: String
    var title: String?
    /// What each field would hold, as text, by the target type's field name.
    var properties: [String: String]
}

nonisolated enum MappingPreviewStatus: Hashable, Sendable {
    case pending
    case ready(MappingPreviewItem)
    case failed(String?)
}

nonisolated struct MappingPreview: Hashable, Sendable {
    var id: String
    var status: MappingPreviewStatus
    var expires: Date
}

/// How many items a rewrite touches, kind by kind.
nonisolated struct MappingRewrite: Hashable, Sendable {
    struct Count: Hashable, Sendable {
        var targetType: String
        var count: Int
    }

    var dryRun: Bool
    /// The stored request's number; nil for a count.
    var number: Int?
    var version: Int
    var kinds: [String: Count]
}

nonisolated struct MappingTypeOption: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var parent: String?
}

nonisolated enum MappingFieldKind: Hashable, Sendable {
    case string, number, integer, boolean, url, email, datetime, date, choice, array, object, thumbnail, status
}

nonisolated struct MappingStatusWord: Hashable, Sendable {
    var value: String
    /// `not_started`, `in_progress`, `completed` or `canceled`.
    var group: String
}

nonisolated struct MappingTypeField: Identifiable, Hashable, Sendable {
    var name: String
    /// The label the server shows the field by, where it names one.
    var label: String?
    var kind: MappingFieldKind
    var required: Bool
    var choices: [String]
    var statusWords: [MappingStatusWord]

    var id: String { name }
}

/// A type as a mapping reads it: its fields, inherited ones included.
nonisolated struct MappingTypeInfo: Hashable, Sendable {
    var id: String
    var label: String
    var plural: String?
    var fields: [MappingTypeField]

    func field(_ name: String) -> MappingTypeField? { fields.first { $0.name == name } }
}

extension ClientOwnerCalls {
    private static func source(_ field: Components.Schemas.ConnectorMappingField) -> MappingSource? {
        switch field {
        case .case1(let from): .field(from.from)
        case .case2(let fixed): value(fixed.fixed).map { .fixed($0) }
        case .case3(let template): .template(template.template)
        }
    }

    private static func kind(_ kind: Components.Schemas.ConnectorMappingKind, named name: String) -> KindMapping {
        KindMapping(
            enabled: kind.enabled ?? true, targetType: kind.targetType ?? "",
            tier: kind.tier.flatMap { KeyTier(rawValue: $0.rawValue) } ?? .feed, statusOverrides: kind.statusOverrides?.additionalProperties ?? [:],
            fields: (kind.fields?.additionalProperties ?? [:]).compactMapValues(source))
    }

    private static func mapping(_ mapping: Components.Schemas.ConnectorMapping) -> ConnectorMappingReading {
        ConnectorMappingReading(
            version: mapping.version,
            kinds: Dictionary(uniqueKeysWithValues: mapping.kinds.additionalProperties.map { ($0.key, kind($0.value, named: $0.key)) }),
            rewrites: mapping.rewrites.map { PendingRewrite(number: $0.number, kinds: $0.kinds, requested: $0.requestedAt) })
    }

    private static func body(_ kind: KindMapping) -> Components.Schemas.ConnectorMappingKind {
        var fields: [String: Components.Schemas.ConnectorMappingField] = [:]
        for (name, source) in kind.fields {
            switch source {
            case .field(let from): fields[name] = .case1(.init(from: from))
            case .fixed(let value): fields[name] = .case2(.init(fixed: container(value)))
            case .template(let text): fields[name] = .case3(.init(template: text))
            }
        }
        return Components.Schemas.ConnectorMappingKind(
            enabled: kind.enabled, targetType: kind.targetType, tier: .init(rawValue: kind.tier.rawValue),
            statusOverrides: .init(additionalProperties: kind.statusOverrides), fields: .init(additionalProperties: fields))
    }

    /// The faults a refusal names, each by its place under `kinds.<kind>.` or `mapping.`, which the caller strips.
    static func mappingFaults(_ error: any Error) -> [MappingFault]? {
        guard case .validation(_, _, let details, let server)? = marfaError(error) else { return nil }
        let errors = (details ?? server?.details)?.object?["errors"]?.array ?? []
        let faults = errors.compactMap { entry -> MappingFault? in
            guard let path = entry.object?["path"]?.string else { return nil }
            return MappingFault(path: path, message: entry.object?["message"]?.string ?? "")
        }
        return faults.isEmpty ? nil : faults
    }

    /// The version a stale refusal names.
    static func mappingStale(_ error: any Error) -> Int?? {
        guard case .server(409, "connector_mapping_stale", _, let details, let server)? = marfaError(error) else { return nil }
        return .some((details ?? server?.details)?.object?["version"]?.integer.map { Int($0) })
    }

    func connectorMapping(of plugin: String) async throws(OwnerFailure) -> ConnectorMappingReading {
        try await run { client in Self.mapping(try await client.getConnectorMapping(path: .init(name: plugin)).ok.body.json) }
    }

    func saveConnectorMapping(of plugin: String, version: Int, kinds: [String: KindMapping]) async throws(OwnerFailure) -> MappingSaveOutcome {
        let client = try make()
        do {
            let save = Components.Schemas.ConnectorMappingSave(
                version: version, kinds: .init(additionalProperties: kinds.mapValues(Self.body)))
            return .saved(Self.mapping(try await client.saveConnectorMapping(path: .init(name: plugin), body: .json(save)).ok.body.json))
        } catch {
            if let stale = Self.mappingStale(error) { return .stale(current: stale) }
            if let faults = Self.mappingFaults(error) { return .refused(faults) }
            throw Self.failure(error)
        }
    }

    private static func preview(_ preview: Components.Schemas.ConnectorPreview) -> MappingPreview {
        let status: MappingPreviewStatus =
            switch preview.status {
            case .pending: .pending
            case .failed: .failed(preview.error)
            case .ready:
                if let result = preview.result.value {
                    .ready(
                        MappingPreviewItem(
                            type: result._type, title: result.title,
                            properties: result.properties.additionalProperties.compactMapValues { text($0) }))
                } else {
                    .failed(nil)
                }
            }
        return MappingPreview(id: preview.id, status: status, expires: preview.expiresAt)
    }

    /// A value the connector sent, as the text a person would read it as; nil for what has nothing to show.
    private static func text(_ container: OpenAPIValueContainer) -> String? {
        switch container.value {
        case let text as String: text.isEmpty ? nil : text
        case let flag as Bool: flag ? String(localized: "Yes") : String(localized: "No")
        case let number as Int: number.formatted(.number.grouping(.never))
        case let number as Double: number.formatted(.number.grouping(.never))
        case let list as [(any Sendable)?]:
            list.compactMap { $0.flatMap { try? OpenAPIValueContainer(unvalidatedValue: $0) }.flatMap(text) }.formatted(.list(type: .and, width: .narrow))
        default: nil
        }
    }

    /// Asks the connector to render one of its recent items under `draft`, or under the mapping in force where there is none.
    func startMappingPreview(of plugin: String, kind: String, draft: KindMapping?) async throws(OwnerFailure) -> MappingPreview {
        try await run { client in
            let request = Components.Schemas.ConnectorPreviewRequest(kind: kind, mapping: draft.map { .init(value1: Self.body($0)) })
            return Self.preview(try await client.createMappingPreview(path: .init(name: plugin), body: .json(request)).created.body.json)
        }
    }

    func mappingPreview(of plugin: String, id: String) async throws(OwnerFailure) -> MappingPreview {
        try await run { client in Self.preview(try await client.getMappingPreview(path: .init(name: plugin, id: id)).ok.body.json) }
    }

    func rewriteConnectorItems(of plugin: String, kinds: [String], dryRun: Bool) async throws(OwnerFailure) -> MappingRewrite {
        try await run { client in
            let answer = try await client.rewriteConnectorItems(
                path: .init(name: plugin), body: .json(.init(dryRun: dryRun, kinds: kinds))
            ).ok.body.json
            return MappingRewrite(
                dryRun: answer.dryRun, number: answer.number, version: answer.version,
                kinds: answer.kinds.additionalProperties.mapValues { .init(targetType: $0.targetType, count: $0.count) })
        }
    }

    func mappingTypeOptions() async throws(OwnerFailure) -> [MappingTypeOption] {
        try await run { client in
            try await client.listTypes().ok.body.json.data.map(\.value1)
                .filter { !$0.id.hasPrefix("system.") && !$0.id.hasPrefix("app.") }
                .map { MappingTypeOption(id: $0.id, label: $0.label ?? $0.id, parent: $0.parent) }
        }
    }

    func mappingType(_ id: String) async throws(OwnerFailure) -> MappingTypeInfo {
        try await run { client in
            let registered = try await client.getType(path: .init(id: id)).ok.body.json
            let definition = registered.value1
            let fields = definition.fields.additionalProperties.map { name, field in
                let kind: MappingFieldKind =
                    switch field._type {
                    case .string: .string
                    case .number: .number
                    case .integer: .integer
                    case .boolean: .boolean
                    case .url: .url
                    case .email: .email
                    case .datetime: .datetime
                    case .date: .date
                    case ._enum: .choice
                    case .array: .array
                    case .object: .object
                    case .thumbnail: .thumbnail
                    case .status: .status
                    }
                return MappingTypeField(
                    name: name, label: field.label, kind: kind, required: field.required ?? false, choices: field.enumValues ?? [],
                    statusWords: (field.statusValues ?? []).map { MappingStatusWord(value: $0.value, group: $0.group.rawValue) })
            }
            return MappingTypeInfo(
                id: definition.id, label: definition.label ?? definition.id, plural: registered.value2.plural.isEmpty ? nil : registered.value2.plural,
                fields: fields.sorted { $0.name < $1.name })
        }
    }
}
