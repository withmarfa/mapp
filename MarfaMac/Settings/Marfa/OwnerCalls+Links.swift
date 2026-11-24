import Foundation
import Marfa
import MarfaAPI

// What the Links page asks of the server: the link types (`GET /edge-types`), what each joins and who brought it, and
// registering and deleting the owner's own (`POST /edge-types`, `DELETE /edge-types/{id}`).

/// How many links of a type an item may hold at each end, from the from end to the to end.
nonisolated enum LinkCardinality: String, CaseIterable, Hashable, Sendable {
    case manyToMany = "many-to-many"
    case manyToOne = "many-to-one"
    case oneToMany = "one-to-many"
    case oneToOne = "one-to-one"

    var title: String {
        switch self {
        case .manyToMany: String(localized: "Many to Many")
        case .manyToOne: String(localized: "Many to One")
        case .oneToMany: String(localized: "One to Many")
        case .oneToOne: String(localized: "One to One")
        }
    }

    /// The same, as the end of a row's line.
    var sentence: String {
        switch self {
        case .manyToMany: String(localized: "Many to many.")
        case .manyToOne: String(localized: "Many to one.")
        case .oneToMany: String(localized: "One to many.")
        case .oneToOne: String(localized: "One to one.")
        }
    }
}

/// A link type, as the server lists it.
nonisolated struct OwnerLinkType: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    /// The name read from the to end; the label where the type has none of its own.
    var reverseLabel: String
    var description: String?
    var cardinality: LinkCardinality
    /// The item types each end admits: `*`, a type, or `role:<name>`.
    var fromTypes: [String]
    var toTypes: [String]
    /// Marfa ships it, so it can't be deleted.
    var shipped: Bool
    /// The title of the plugin that brought it, where an installed plugin did.
    var plugin: String?
}

/// The link types, with the names of the item types they join.
nonisolated struct LinkTypeListing: Hashable, Sendable {
    var linkTypes: [OwnerLinkType]
    /// Each item type's name by its ID.
    var typeNames: [String: String]
}

/// What New Link Type… registers.
nonisolated struct NewLinkType: Hashable, Sendable {
    var id: String
    var label: String
    var reverseLabel: String?
    var cardinality: LinkCardinality
    var fromTypes: [String]
    var toTypes: [String]
}

/// How a delete ended that the server answered.
nonisolated enum LinkTypeDeletion: Hashable, Sendable {
    case deleted
    /// Links of the type are stored, so the server kept it (`edges/types-delete-in-use`).
    case inUse
    /// Nothing is registered under the ID any more: it was deleted somewhere else.
    case gone
}

extension ClientOwnerCalls {
    /// The owner's `metadata.edge_types:write`, which registering needs and which the server names only by subresource.
    static let registeringLinkTypes = "metadata.edge_types:write"

    func linkTypes() async throws(OwnerFailure) -> LinkTypeListing {
        try await run { client in
            let listed = try await client.listEdgeTypes().ok.body.json.data
            let types = try await client.listTypes().ok.body.json.data.map {
                (id: $0.value1.id, label: $0.value1.label ?? $0.value1.id, parent: $0.value1.parent)
            }
            var brought: [String: String] = [:]
            for plugin in try await client.listPlugins().ok.body.json.data {
                for id in plugin.edgeTypes { brought[id] = plugin.title }
            }
            let linkTypes = listed.map { Self.linkType($0, plugin: brought[$0.id]) }
            return LinkTypeListing(linkTypes: linkTypes, typeNames: OwnerWording.typeNames(types))
        }
    }

    func register(_ linkType: NewLinkType) async throws(OwnerFailure) -> OwnerLinkType {
        let request = Components.Schemas.EdgeTypeRegistrationRequest(
            id: linkType.id, label: linkType.label, reverseLabel: linkType.reverseLabel,
            cardinality: .init(rawValue: linkType.cardinality.rawValue) ?? .manyToMany,
            fromTypeConstraints: linkType.fromTypes, toTypeConstraints: linkType.toTypes)
        let client = try make()
        let answer: Operations.RegisterEdgeType.Output
        do {
            answer = try await client.registerEdgeType(body: .json(request))
        } catch {
            if case .forbidden(_, _, let server)? = Self.marfaError(error),
                server?.details?.object?["metadata_subresource"]?.string == "edge_types"
            {
                throw .notPermitted(Self.registeringLinkTypes)
            }
            throw Self.failure(error, plainConflict: { _ in .refused(String(localized: "Another link type has this name. Choose another.")) })
        }
        let registered: Components.Schemas.EdgeType? = switch answer {
        case .created(let created): try? created.body.json
        case .ok(let kept): try? kept.body.json
        default: nil
        }
        guard let registered else { throw .failed(String(localized: "The server’s answer couldn’t be read.")) }
        return Self.linkType(registered, plugin: nil)
    }

    func deleteLinkType(_ id: String) async throws(OwnerFailure) -> LinkTypeDeletion {
        let client = try make()
        do {
            _ = try await client.deleteEdgeType(path: .init(id: id)).ok
            return .deleted
        } catch {
            switch Self.marfaError(error) {
            case .server(409, "edge_type_in_use", _, _, _)?: return .inUse
            case .notFound?: return .gone
            default: throw Self.failure(error)
            }
        }
    }

    private static func linkType(_ type: Components.Schemas.EdgeType, plugin: String?) -> OwnerLinkType {
        OwnerLinkType(
            id: type.id, label: type.label, reverseLabel: type.reverseLabel, description: type.description,
            cardinality: LinkCardinality(rawValue: type.cardinality.rawValue) ?? .manyToMany, fromTypes: type.fromTypeConstraints,
            toTypes: type.toTypeConstraints, shipped: type.shipped, plugin: plugin)
    }
}
