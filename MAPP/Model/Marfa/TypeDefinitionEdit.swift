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

        var update = Update(fields: .init(additionalProperties: fields.additionalProperties))
        update.tables = own.tables.map { .init(additionalProperties: $0.additionalProperties) }
        update.version = own.version
        update.parent = own.parent
        update.label = own.label
        update.plural = own.plural
        update.description = own.description
        update.roles = listed.value2.ownRoles.map(\.rawValue)
        update.displayHints = own.displayHints
        update.linkField = own.linkField
        update.versionPolicy = own.versionPolicy
        update.mergePolicy = own.mergePolicy
        update.retentionPolicy = own.retentionPolicy
        return update
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
