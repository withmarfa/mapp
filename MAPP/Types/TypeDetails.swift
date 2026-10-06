import Foundation

/// A type named from another, which is a link where the catalogue holds the type and plain text where it does not.
nonisolated struct TypeReference: Identifiable, Hashable, Sendable {
    let id: TypeID
    let label: String
    let isKnown: Bool

    init(_ id: TypeID, in catalogue: Catalogue) {
        self.id = id
        label = catalogue.itemTypes[id]?.label ?? id.rawValue
        isKnown = catalogue.itemTypes[id] != nil
    }
}

/// Everything the page for an item type shows, worked out from the catalogue so the view only lays it out.
nonisolated struct ItemTypeDetail: Sendable {
    struct FieldRow: Identifiable, Hashable, Sendable {
        let field: ItemTypeInfo.Field
        /// The type that declares it, when that is not the type being shown.
        let inheritedFrom: TypeReference?
        var id: String { field.key }
    }

    struct EdgeLink: Identifiable, Hashable, Sendable {
        /// The ends of the edge a type may stand at.
        enum Role: Hashable, Sendable { case source, target, either }

        let edge: EdgeTypeInfo
        let role: Role
        var id: String { edge.id }
    }

    let type: ItemTypeInfo
    /// From the top of the hierarchy down to the direct parent; it stops at a parent the catalogue lacks.
    let parents: [TypeReference]
    let fields: [FieldRow]
    let compatibleWith: [TypeReference]
    /// The types that name this one as compatible, found by reading the catalogue the other way.
    let compatibleFrom: [TypeReference]
    /// Edge types that name this type or one above it at an end. One that limits no types applies to every type,
    /// so it is left out.
    let edgeTypes: [EdgeLink]

    init(_ type: ItemTypeInfo, in catalogue: Catalogue) {
        self.type = type
        var chain: [TypeReference] = []
        var visited: Set<TypeID> = [type.id]
        var next = type.parent
        while let id = next, visited.insert(id).inserted {
            chain.append(TypeReference(id, in: catalogue))
            next = catalogue.itemTypes[id]?.parent
        }
        parents = chain.reversed()
        fields = type.fields.map { field in
            FieldRow(
                field: field,
                inheritedFrom: field.declaredBy == type.id ? nil : TypeReference(field.declaredBy, in: catalogue))
        }
        compatibleWith = type.compatibleWith.map { TypeReference($0, in: catalogue) }
        compatibleFrom = TypeTree.ordered(catalogue.itemTypes.values.filter { $0.compatibleWith.contains(type.id) })
            .map { TypeReference($0.id, in: catalogue) }
        edgeTypes = TypeTree.ordered(Array(catalogue.edgeTypes.values)).compactMap { edge in
            let asSource = edge.sourceTypes.contains(type.id) || catalogue.isSubtype(type.id, ofAnyOf: edge.sourceTypes)
            let asTarget = edge.targetTypes.contains(type.id) || catalogue.isSubtype(type.id, ofAnyOf: edge.targetTypes)
            switch (asSource, asTarget) {
            case (true, true): return EdgeLink(edge: edge, role: .either)
            case (true, false): return EdgeLink(edge: edge, role: .source)
            case (false, true): return EdgeLink(edge: edge, role: .target)
            case (false, false): return nil
            }
        }
    }

    /// The field that holds the title, or nil where the title is the body's first line.
    var titleField: String? { MarfaMapping.titleField(of: type) }
}

/// Everything the page for an edge type shows.
nonisolated struct EdgeTypeDetail: Sendable {
    let edge: EdgeTypeInfo
    /// Empty where any type may stand at the end.
    let sourceTypes: [TypeReference]
    let targetTypes: [TypeReference]

    init(_ edge: EdgeTypeInfo, in catalogue: Catalogue) {
        self.edge = edge
        func references(_ ids: Set<TypeID>) -> [TypeReference] {
            TypeTree.ordered(ids.compactMap { catalogue.itemTypes[$0] }).map { TypeReference($0.id, in: catalogue) }
                + ids.filter { catalogue.itemTypes[$0] == nil }.sorted { $0.rawValue < $1.rawValue }
                .map { TypeReference($0, in: catalogue) }
        }
        sourceTypes = references(edge.sourceTypes)
        targetTypes = references(edge.targetTypes)
    }
}

// MARK: Wording

extension EdgeTypeInfo {
    /// How many items an item at the source end can point to.
    var targetsPerSource: Cardinality { writtenAt == .source ? cardinality : reverseCardinality }

    /// How many items can point to an item at the target end.
    var sourcesPerTarget: Cardinality { writtenAt == .source ? reverseCardinality : cardinality }

    var sourceEndWording: String {
        switch targetsPerSource {
        case .one: String(localized: "Each can point to one item at most.")
        case .many: String(localized: "Each can point to many items.")
        }
    }

    var targetEndWording: String {
        switch sourcesPerTarget {
        case .one: String(localized: "Each can be pointed to by one item at most.")
        case .many: String(localized: "Each can be pointed to by many items.")
        }
    }

    var writtenAtWording: String {
        switch writtenAt {
        case .source: String(localized: "The item it points from")
        case .target: String(localized: "The item it points to")
        }
    }

    var cascadeWording: String {
        switch cascadeOnDelete {
        case .cascade: String(localized: "Deleting the item it points from also deletes the item it points to")
        case .orphan: String(localized: "Deleting either item keeps the other")
        case .block: String(localized: "Deleting either item is refused while the connection exists")
        }
    }
}

extension ItemTypeInfo.Field.Kind {
    var wording: String {
        switch self {
        case .text: String(localized: "Text")
        case .number: String(localized: "Number")
        case .boolean: String(localized: "Yes or No")
        case .date: String(localized: "Date")
        case .choice: String(localized: "Choice")
        case .other: String(localized: "Other")
        }
    }
}

extension ItemTypeDetail.EdgeLink.Role {
    var wording: String {
        switch self {
        case .source: String(localized: "From")
        case .target: String(localized: "To")
        case .either: String(localized: "From or To")
        }
    }
}
