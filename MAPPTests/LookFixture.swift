import Foundation
@testable import MAPP

/// A catalogue of Marfa's core types, written from the fields the contract gives them, and the types built on them
/// that a looks test needs. A child carries the fields it inherits, as the server's catalogue gives them, each declared by
/// the type that first names it.
enum LookFixture {
    struct Spec {
        let id: String
        var parent: String?
        var fields: [ItemTypeInfo.Field] = []
    }

    static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind = .text, format: ItemTypeInfo.Field.TextFormat? = nil) -> ItemTypeInfo.Field {
        var field = ItemTypeInfo.Field(key: key, label: key, kind: kind, declaredBy: TypeID("test"))
        field.format = format
        return field
    }

    static let date = ItemTypeInfo.Field.Kind.date(includesTime: true)
    static let day = ItemTypeInfo.Field.Kind.date(includesTime: false)
    static let list = ItemTypeInfo.Field.Kind.list(ListShape(members: []))
    static let status = ItemTypeInfo.Field.Kind.status([
        StatusWord(value: "todo", group: .notStarted), StatusWord(value: "done", group: .completed),
    ])

    static let specs: [Spec] = [
        Spec(id: "core.entity", fields: [
            field("name"), field("url", format: .url), field("description"), field("emails", list), field("phones", list),
            field("addresses", list), field("founded", day), field("notes"),
        ]),
        Spec(id: "core.entity.person", parent: "core.entity", fields: [
            field("given_name"), field("family_name"), field("organization"), field("job_title"), field("birthday", day),
        ]),
        Spec(id: "acme.repository", parent: "core.entity", fields: [field("full_name"), field("language"), field("url", format: .url)]),
        Spec(id: "core.entity.place", parent: "core.entity", fields: [
            field("street_address"), field("locality"), field("region"), field("postal_code"), field("country"),
            field("latitude", .number), field("longitude", .number),
        ]),
        Spec(id: "core.event", fields: [
            field("title"), field("description"), field("starts_at", date), field("ends_at", date), field("duration", .number),
            field("place"), field("latitude", .number), field("longitude", .number), field("url", format: .url),
            field("status", .choice(["tentative", "confirmed", "canceled"])), field("attendees", list),
        ]),
        Spec(id: "core.task", fields: [
            field("title"), field("body"), field("due_at", date), field("starts_at", date), field("completed_at", date),
            field("status", status), field("priority", .choice(["low", "high"])), field("place"), field("assignees", list),
        ]),
        Spec(id: "core.file", fields: [
            field("blob_ref"), field("mime_type"), field("title"), field("url", format: .url), field("author"),
            field("size_bytes", .number),
        ]),
        Spec(id: "core.file.image", parent: "core.file", fields: [
            field("width", .number), field("height", .number), field("latitude", .number), field("longitude", .number),
        ]),
        Spec(id: "core.file.video", parent: "core.file", fields: [field("duration", .number), field("latitude", .number)]),
        Spec(id: "core.file.webpage", parent: "core.file"),
        Spec(id: "core.bookmark", fields: [
            field("url", format: .url), field("body"), field("title"), field("author"), field("published_at", date),
        ]),
        Spec(id: "core.highlight", fields: [
            field("text"), field("note"), field("color", .choice(["yellow"])), field("start_location"),
        ]),
        Spec(id: "core.media", fields: [
            field("title"), field("body"), field("author"), field("url", format: .url), field("published_at", date),
            field("progress", .status([StatusWord(value: "planned", group: .notStarted)])), field("rating", .number),
        ]),
        Spec(id: "core.media.book", parent: "core.media", fields: [field("isbn"), field("page_count", .number)]),
        Spec(id: "core.message", fields: [field("body"), field("from"), field("to", list)]),
        Spec(id: "core.note", fields: [field("body"), field("title"), field("language")]),
        Spec(id: "aic.decision", parent: "core.note", fields: [field("description")]),
        Spec(id: "aic.ticket", parent: "core.task"),
        Spec(id: "aic.ticket.task", parent: "aic.ticket"),
        Spec(id: "aic.agent.session", parent: "core.event", fields: [field("body")]),
    ]

    private static func declared(_ field: ItemTypeInfo.Field, by id: String) -> ItemTypeInfo.Field {
        var copy = ItemTypeInfo.Field(key: field.key, label: field.label, kind: field.kind, declaredBy: TypeID(id))
        copy.format = field.format
        return copy
    }

    /// The look of the type `id`, resolved with `choices`.
    static func look(_ id: String, in catalogue: Catalogue, choices: [TypeID: TypeLookChoice] = [:]) -> TypeLook {
        catalogue.looks(choices: choices)[TypeID(id)]!
    }

    /// The catalogue of `specs`, each type's fields with its ancestors' before its own.
    static func catalogue(_ specs: [Spec] = specs) -> Catalogue {
        let byID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
        func fields(of spec: Spec, depth: Int = 0) -> [ItemTypeInfo.Field] {
            let inherited = depth < 12 ? spec.parent.flatMap { byID[$0] }.map { fields(of: $0, depth: depth + 1) } ?? [] : []
            let own = spec.fields.filter { field in !inherited.contains { $0.key == field.key } }.map { declared($0, by: spec.id) }
            return inherited + own
        }
        return Catalogue(itemTypes: specs.map { spec in
            ItemTypeInfo(
                id: TypeID(spec.id), label: spec.id, fields: fields(of: spec), titleField: nil, bodyField: nil,
                parent: spec.parent.map { TypeID($0) })
        })
    }

    static func make(_ id: String, parent: String? = nil, _ fields: [ItemTypeInfo.Field] = []) -> Spec {
        Spec(id: id, parent: parent, fields: fields)
    }
}
