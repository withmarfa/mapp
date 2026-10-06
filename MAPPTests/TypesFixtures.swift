import Foundation
@testable import MAPP

/// Catalogues for the tests of Marfa Types, small enough that each expectation can be read against them.
enum TypesFixtures {
    static func field(
        _ key: String, _ kind: ItemTypeInfo.Field.Kind = .text, by owner: String, required: Bool = false
    ) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(
            key: key, label: MarfaMapping.label(forField: key), kind: kind, declaredBy: TypeID(owner), required: required)
    }

    static func type(
        _ id: String, _ label: String? = nil, parent: String? = nil, fields: [ItemTypeInfo.Field] = [],
        titleField: String? = "title", bodyField: String? = nil, version: Int64? = nil,
        compatibleWith: [String] = [], roles: [String] = []
    ) -> ItemTypeInfo {
        ItemTypeInfo(
            id: TypeID(id), label: label ?? id, fields: fields, titleField: titleField, bodyField: bodyField,
            parent: parent.map { TypeID($0) }, version: version, roles: roles, compatibleWith: compatibleWith.map { TypeID($0) })
    }

    static func edge(
        _ id: String, _ label: String? = nil, reverse: String? = nil, held: EdgeTypeInfo.Cardinality = .many,
        other: EdgeTypeInfo.Cardinality = .many, writtenAt: EdgeTypeInfo.End = .source, from: [String] = [],
        to: [String] = [], fromRoles: [String] = [], toRoles: [String] = [], cascade: EdgeTypeInfo.CascadeOnDelete = .orphan, properties: [ItemTypeInfo.Field] = []
    ) -> EdgeTypeInfo {
        EdgeTypeInfo(
            id: id, label: label ?? id, reverseName: reverse, cardinality: held, writtenAt: writtenAt,
            sourceTypes: Set(from.map { TypeID($0) }), targetTypes: Set(to.map { TypeID($0) }),
            sourceRoles: Set(fromRoles), targetRoles: Set(toRoles), reverseCardinality: other, cascadeOnDelete: cascade, properties: properties)
    }

    /// A file hierarchy of three levels, a second root, a type whose parent the catalogue lacks, and edge types
    /// that name types at their ends.
    static let catalogue = Catalogue(
        itemTypes: [
            type("core.file", "File", fields: [field("blob_ref", by: "core.file", required: true), field("title", by: "core.file")], version: 2),
            type("core.file.image", "Image", parent: "core.file", fields: [
                field("blob_ref", by: "core.file", required: true), field("title", by: "core.file"), field("width", .number, by: "core.file.image")
            ]),
            type("core.file.image.raw", "Raw Image", parent: "core.file.image", fields: [
                field("blob_ref", by: "core.file", required: true), field("title", by: "core.file"), field("width", .number, by: "core.file.image"),
                field("exposure", by: "core.file.image.raw")
            ]),
            type("core.file.pdf", "PDF", parent: "core.file", fields: [
                field("blob_ref", by: "core.file", required: true), field("title", by: "core.file")
            ]),
            type("core.entity", "Entity", fields: [field("name", by: "core.entity")], titleField: "name"),
            type("core.entity.person", "Person", parent: "core.entity", fields: [
                field("name", by: "core.entity"), field("email", by: "core.entity.person")
            ], titleField: "name", compatibleWith: ["core.contact"]),
            type("core.contact", "Contact", fields: [field("name", by: "core.contact")], titleField: "name"),
            type("aic.ticket.bug", "Bug", parent: "aic.ticket"),
            type("core.media.album", "Album", roles: ["container"]),
            type("core.media.album.live", "Live Album", parent: "core.media.album")
        ],
        edgeTypes: [
            edge("parent-of", "Parent of", reverse: "child-of", held: .one, writtenAt: .target, cascade: .cascade),
            edge("attached-to", "Attached to", reverse: "has-attachment", held: .one, other: .many, from: ["core.file"], to: ["core.entity"]),
            edge("references", "References"),
            edge("in-collection", "In collection", reverse: "contains", toRoles: ["container"])
        ])
}
