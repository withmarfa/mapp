import Foundation
import MarfaAPI

/// Builds the definition a replacement of a type sends, from the type's own definition as the server holds it now.
///
/// `PUT /types/{id}` replaces the whole stored definition, and a catalogue type is lossy (resolved with its parents',
/// without tables, policies or display hints), so the definition is always built from `GET /types`, which answers only
/// what each type declares. Only the one field changes; every other member goes back as the server gave it, and a
/// field a parent declares is never written into the child.
nonisolated enum TypeDefinitionEdit {
    typealias Listed = Components.Schemas.ListedType
    typealias Update = Components.Schemas.TypeDefinitionUpdate

    /// The replacement for `plan`, or `changedOnServer` where the type is not as the page showed it: the field is gone,
    /// or no longer has the label or the choices the page showed. A different change to another field is no conflict,
    /// since it is read here and sent back.
    static func update(_ listed: Listed, for plan: FieldEditPlan) throws(TypeSchemaFailure) -> Update {
        let own = listed.value1
        guard var field = own.fields.additionalProperties[plan.edit.key] else { throw .changedOnServer }
        try check(field, against: plan.shown)

        var fields = own.fields
        switch plan.edit {
        case .rename(let key, let label):
            field.label = label
            fields.additionalProperties[key] = field
        case .setChoices(let key, let choices):
            field.enumValues = choices
            fields.additionalProperties[key] = field
        case .remove(let key):
            fields.additionalProperties[key] = nil
        }

        return replacement(of: listed, fields: fields)
    }

    /// The replacement that sends `listed` back as the server gave it, with `fields` in place of its own. The type's
    /// guidance goes back unchanged: a replacement that left it out would remove it, which a sign-in an app made is
    /// refused (`types/guidance-app-made`) and any other sign-in would do without meaning to.
    private static func replacement(of listed: Listed, fields: Components.Schemas.TypeDefinition.FieldsPayload) -> Update {
        let own = listed.value1
        var update = Update(fields: .init(additionalProperties: fields.additionalProperties))
        update.tables = own.tables.map { .init(additionalProperties: $0.additionalProperties) }
        update.version = own.version
        update.parent = own.parent
        update.label = own.label
        update.plural = own.plural
        update.description = own.description
        update.guidance = own.guidance
        update.roles = listed.value2.ownRoles.map(\.rawValue)
        update.displayHints = own.displayHints
        update.linkField = own.linkField
        update.versionPolicy = own.versionPolicy
        update.mergePolicy = own.mergePolicy
        update.retentionPolicy = own.retentionPolicy
        return update
    }

    /// A change to the type itself, not to one field: what the Types page sets. A word's name is a lowercase letter and
    /// then letters, digits and underscores (`status_values`), and the server refuses any other.
    enum TypeChange: Hashable, Sendable {
        case label(String)
        /// An empty plural leaves it to the server, which adds `s`, `es` or `ies` to the label.
        case plural(String)
        /// An empty description leaves it out.
        case description(String)
        case parent(String?)
        /// A new word for the type's status field, in one of its four groups.
        case addWord(group: String, value: String)
        /// What an own word means; empty leaves it out.
        case wordMeaning(value: String, text: String)
    }

    /// The replacement for `change` to `listed`. A word is added to the type's own status field, or to a redeclaration
    /// of the one a type above gives it, which carries only the words the child adds (`types/child-adds`).
    static func update(_ listed: Listed, applying change: TypeChange, in all: [Listed]) throws(TypeSchemaFailure) -> Update {
        let own = listed.value1
        var update = replacement(of: listed, fields: own.fields)
        switch change {
        case .label(let text):
            update.label = text
        case .plural(let text):
            update.plural = text.isEmpty ? nil : text
        case .description(let text):
            update.description = text.isEmpty ? nil : text
        case .parent(let id):
            update.parent = id
        case .addWord(let group, let value):
            guard let group = Components.Schemas.StatusValue.GroupPayload(rawValue: group) else { throw .refused(String(localized: "A status word belongs to one of four groups.")) }
            let word = Components.Schemas.StatusValue(value: value, group: group)
            if let key = own.fields.additionalProperties.first(where: { $0.value._type == .status })?.key {
                update.fields.additionalProperties[key]?.statusValues = (own.fields.additionalProperties[key]?.statusValues ?? []) + [word]
            } else if let key = statusField(above: own, in: all) {
                update.fields.additionalProperties[key] = .init(_type: .status, statusValues: [word])
            } else {
                throw .changedOnServer
            }
        case .wordMeaning(let value, let text):
            guard let key = own.fields.additionalProperties.first(where: { $0.value.statusValues?.contains { $0.value == value } == true })?.key else {
                throw .changedOnServer
            }
            update.fields.additionalProperties[key]?.statusValues = own.fields.additionalProperties[key]?.statusValues?.map { word in
                guard word.value == value else { return word }
                var changed = word
                changed.description = text.isEmpty ? nil : text
                return changed
            }
        }
        return update
    }

    /// Whether `own`, as the server holds it now, already has what `change` would make. The server has no check for a stale
    /// write and refuses a word it holds, so a change worked out before another one landed is sent only if it still differs.
    static func holds(_ change: TypeChange, in own: Listed) -> Bool {
        let type = own.value1
        switch change {
        case .label(let text): return type.label == text
        case .plural(let text): return type.plural == (text.isEmpty ? nil : text)
        case .description(let text): return type.description == (text.isEmpty ? nil : text)
        case .parent(let id): return type.parent == id
        case .addWord(let group, let value):
            return type.fields.additionalProperties.values.contains { field in
                field.statusValues?.contains { $0.value == value && $0.group.rawValue == group } == true
            }
        case .wordMeaning(let value, let text):
            let words = type.fields.additionalProperties.values.flatMap { $0.statusValues ?? [] }
            return words.contains { $0.value == value && $0.description == (text.isEmpty ? nil : text) }
        }
    }

    /// The name of the status field a type above `own` declares, which a child redeclares to add words.
    private static func statusField(above own: Components.Schemas.TypeDefinition, in all: [Listed]) -> String? {
        var seen: Set<String> = [own.id]
        var next = own.parent
        while let id = next, seen.insert(id).inserted, let parent = all.first(where: { $0.value1.id == id }) {
            if let key = parent.value1.fields.additionalProperties.first(where: { $0.value._type == .status })?.key { return key }
            next = parent.value1.parent
        }
        return nil
    }

    /// The field as the server holds it must read as the page showed it: a label the page showed from the type, or the
    /// choices it showed. A label the server does not declare is derived, so it only has to be one the page showed
    /// from the field's own type, which `shown` already is.
    private static func check(_ field: Components.Schemas.FieldDefinition, against shown: ItemTypeInfo.Field) throws(TypeSchemaFailure) {
        if let label = field.label, label != shown.label { throw .changedOnServer }
        switch shown.kind {
        case .choice(let choices):
            guard field.enumValues == choices else { throw .changedOnServer }
        default:
            break
        }
    }

    /// Reads the type's own definition, checks it against the plan and replaces it. `read` answers the types the
    /// server lists, and `replace` sends the definition for the type.
    static func run(
        _ plan: FieldEditPlan,
        read: () async throws -> [Listed],
        replace: (Update) async throws -> Void
    ) async throws {
        let listed = try await read()
        guard let own = listed.first(where: { $0.value1.id == plan.type.rawValue }) else { throw TypeSchemaFailure.changedOnServer }
        if own.value2.provenance.origin == .plugin { throw TypeSchemaFailure.pluginType }
        if declaredAbove(plan.edit.key, from: own, in: listed) { throw TypeSchemaFailure.changedOnServer }
        try await replace(update(own, for: plan))
    }

    /// Reads the types, checks that `id` is the owner's to change and replaces it with `change` made, unless it already holds it.
    static func run(
        _ change: TypeChange, to id: String,
        read: () async throws -> [Listed],
        replace: (Update) async throws -> Void
    ) async throws {
        let listed = try await read()
        guard let own = listed.first(where: { $0.value1.id == id }) else { throw TypeSchemaFailure.changedOnServer }
        if own.value2.provenance.origin == .plugin { throw TypeSchemaFailure.pluginType }
        if holds(change, in: own) { return }
        try await replace(update(own, applying: change, in: listed))
    }

    /// Whether a type above `own`, as the server lists them now, declares `key`: then the field is inherited, and a
    /// change to the child's own declaration would not reach it, whatever the catalogue held when the page was shown.
    static func declaredAbove(_ key: String, from own: Listed, in listed: [Listed]) -> Bool {
        var seen: Set<String> = [own.value1.id]
        var next = own.value1.parent
        while let id = next, seen.insert(id).inserted, let parent = listed.first(where: { $0.value1.id == id }) {
            if parent.value1.fields.additionalProperties[key] != nil { return true }
            next = parent.value1.parent
        }
        return false
    }
}
