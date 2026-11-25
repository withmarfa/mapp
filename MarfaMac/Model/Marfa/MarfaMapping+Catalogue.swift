import Foundation
import Marfa

nonisolated extension MarfaMapping {
    /// An app's own types (`app.*`) are its machinery and never shown, so they are left out.
    static func catalogue(itemTypes: [Marfa.ItemType], edgeTypes: [Marfa.EdgeType]) -> Catalogue {
        Catalogue(itemTypes: itemTypes.filter { !$0.id.hasPrefix("app.") }.map(itemType), edgeTypes: edgeTypes.map(edgeType))
    }

    static func itemType(_ type: Marfa.ItemType) -> ItemTypeInfo {
        ItemTypeInfo(
            id: TypeID(type.id), label: type.label ?? type.id, plural: type.plural,
            fields: type.fields.map { field($0, statusWords: $0.name == type.statusField ? type.statusWords : []) },
            titleField: type.titleField, bodyField: type.bodyField, parent: type.parent.map { TypeID($0) }, icon: type.icon,
            description: type.description, version: type.version, roles: type.roles, linkField: type.linkField)
    }

    private static func field(_ field: Marfa.TypeField, statusWords: [Marfa.StatusWord] = []) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(
            key: field.name, label: field.label, kind: kind(of: field, statusWords: statusWords),
            declaredBy: TypeID(field.declaredBy), required: field.required, description: field.description,
            format: format(of: field), isInteger: field.type == "integer",
            minimum: bound("minimum", in: field.definition), maximum: bound("maximum", in: field.definition),
            maxItems: field.type == "array" ? maxItems(in: field.definition) : nil)
    }

    /// The most entries a list declares (`maxItems`, a whole number of at least 1), nil where it names none.
    static func maxItems(in definition: JSONObject) -> Int? {
        guard case .integer(let value)? = definition["maxItems"], value >= 1 else { return nil }
        return Int(value)
    }

    /// A number a definition names, such as a `minimum`.
    static func bound(_ name: String, in definition: JSONObject) -> Decimal? {
        switch definition[name] {
        case .integer(let value)?: Decimal(value)
        case .number(let value)?: Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX"))
        default: nil
        }
    }

    /// The members of a list of entries (`items_fields`), in the order the type declares them; nil where the field is
    /// not one.
    static func listShape(of field: Marfa.TypeField) -> ListShape? {
        guard field.type == "array", field.definition["items_type"]?.string == "object",
              let declared = field.definition["items_fields"]?.object, !declared.keys.isEmpty else { return nil }
        let members = declared.keys.compactMap { key -> ListShape.Member? in
            guard let definition = declared[key]?.object, let type = definition["type"]?.string else { return nil }
            let kind: ListShape.Member.Kind
            switch type {
            case "string": kind = .text(definition["format"]?.string == "url" ? .url : definition["format"]?.string == "email" ? .email : nil)
            case "url": kind = .text(.url)
            case "email": kind = .text(.email)
            case "enum": kind = .choice(definition["enum_values"]?.array?.compactMap(\.string) ?? [])
            case "number", "integer":
                kind = .number(NumberRule(
                    integer: type == "integer", minimum: bound("minimum", in: definition), maximum: bound("maximum", in: definition)))
            case "boolean": kind = .boolean
            case "date": kind = .date(includesTime: false)
            case "datetime": kind = .date(includesTime: true)
            default: return nil
            }
            // The core labels every member; a catalog that came without one is read as its key in words ("street_address").
            let words = key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return ListShape.Member(
                key: key, label: definition["label"]?.string ?? words, kind: kind, required: definition["required"]?.bool == true)
        }
        // A member the app cannot read would be dropped from an entry it edits, so such a list is shown but not edited.
        return members.count == declared.keys.count ? ListShape(members: members) : nil
    }

    /// A field is a web or mail address when its kind says so or, as a text field's `format` refines it, when its
    /// definition does: the server stores such a field as that kind, but a catalogue can still carry it as `string`.
    static func format(of field: Marfa.TypeField) -> ItemTypeInfo.Field.TextFormat? {
        let name = field.type == "string" ? field.definition["format"]?.string : field.type
        switch name {
        case "url": return .url
        case "email": return .email
        case "currency": return .currency
        default: return nil
        }
    }

    static func edgeType(_ type: Marfa.EdgeType) -> EdgeTypeInfo {
        // Cardinality is given from the `from` end to the `to` end; the end that writes the edge holds as many as the other
        // side of it allows.
        let ends = type.cardinality.split(separator: "-to-").map(String.init)
        let held = type.writtenFrom == .to ? ends.first : ends.last
        let other = type.writtenFrom == .to ? ends.last : ends.first
        return EdgeTypeInfo(
            id: type.id, label: type.label, reverseLabel: type.reverseLabel, reverseName: type.reverseName,
            cardinality: held == "one" ? .one : .many, writtenFrom: type.writtenFrom == .to ? .to : .from,
            fromTypes: constraints(type.fromTypeConstraints).types,
            toTypes: constraints(type.toTypeConstraints).types,
            fromRoles: constraints(type.fromTypeConstraints).roles,
            toRoles: constraints(type.toTypeConstraints).roles,
            description: type.description, reverseCardinality: other == "one" ? .one : .many,
            cascadeOnDelete: cascade(type.cascadeOnDelete), properties: type.properties.map { field($0) }, flat: type.flat)
    }

    private static func cascade(_ name: String) -> EdgeTypeInfo.CascadeOnDelete {
        switch name {
        case "cascade": .cascade
        case "block": .block
        default: .orphan
        }
    }

    /// A constraint names a type, which matches its subtypes, or `role:<name>`, which matches the types that play
    /// the role. `*` allows any.
    private static func constraints(_ names: [String]) -> (types: Set<TypeID>, roles: Set<String>) {
        guard !names.contains("*") else { return ([], []) }
        let prefix = "role:"
        let roles = names.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        return (Set(names.filter { !$0.hasPrefix(prefix) }.map { TypeID($0) }), Set(roles))
    }

    private static func kind(of field: Marfa.TypeField, statusWords: [Marfa.StatusWord]) -> ItemTypeInfo.Field.Kind {
        switch field.type {
        case "status":
            .status(statusWords.compactMap { word in StatusGroup(rawValue: word.group.rawValue).map { StatusWord(value: word.value, group: $0) } })
        case "string", "url", "email": .text
        case "number", "integer": .number
        case "boolean": .boolean
        case "date": .date(includesTime: false)
        case "datetime": .date(includesTime: true)
        case "enum":
            if case .array(let values) = field.definition["enum_values"] {
                .choice(values.compactMap(\.string))
            } else {
                .other
            }
        case "array":
            if let shape = listShape(of: field) {
                .list(shape)
            } else if ["string", "url", "email"].contains(field.definition["items_type"]?.string) {
                .words
            } else {
                .other
            }
        default: .other
        }
    }
}
