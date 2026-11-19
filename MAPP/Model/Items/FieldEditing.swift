import Foundation

/// Why a field on the page cannot be changed: Marfa does not let a person change what it ships, and a field a type
/// inherits is the parent's to change.
nonisolated enum FieldLock: Hashable, Sendable {
    /// The type that declares the field is above this one.
    case inherited(from: TypeID)
    /// The type is Marfa's own: `core`, `system` and `marfa` types are refused every change.
    case shipped
}

nonisolated extension TypeID {
    /// The roots the contract reserves for what Marfa ships (`types/id-reserved-namespace`): the server refuses to
    /// replace or delete a type under them (`types/shipped-immutable`). This is the one place MAPP tells a shipped
    /// type from the owner's; the catalogue carries no provenance.
    var isShipped: Bool {
        guard let root = rawValue.split(separator: ".", maxSplits: 1).first else { return false }
        return ["core", "system", "marfa"].contains(String(root))
    }
}

nonisolated extension ItemTypeInfo {
    /// Whether a person can change `field` on this type, or what stops them. Only a field the type declares itself,
    /// on a type of the owner's, is theirs to change.
    func lock(of field: Field) -> FieldLock? {
        if field.declaredBy != id { return .inherited(from: field.declaredBy) }
        return id.isShipped ? .shipped : nil
    }
}

/// A change a person makes to one field of a type, which changes the type for every item of it. Only what the
/// contract lets a change keep every item's values for is here: the field's label, the choices of a choice field
/// and the field itself. A field's name is never changed, since no replacement carries the values held under the old
/// name to the new one (`types/field-removed`), and a choice word is never renamed for the same reason.
nonisolated enum FieldEdit: Hashable, Sendable {
    case rename(key: String, label: String)
    /// The whole list of choices, in the order to offer them.
    case setChoices(key: String, choices: [String])
    case remove(key: String)

    var key: String {
        switch self {
        case .rename(let key, _), .setChoices(let key, _), .remove(let key): key
        }
    }
}

/// Why a change to a field is not sent at all.
nonisolated enum FieldEditRefusal: Error, Hashable, Sendable {
    case locked(FieldLock)
    case unknownField
    case blankLabel
    case labelTooLong
    /// Another field of the type already has this name.
    case labelInUse(String)
    case notAChoiceField
    case noChoices
    case blankChoice
    case repeatedChoice(String)
    /// The field holds the title, the text or the link to the source of items, which a type cannot do without.
    case holdsPageContent

    var message: String {
        switch self {
        case .locked(.shipped):
            String(localized: "Marfa’s own types can’t be changed. Add the field to a type of your own instead.")
        case .locked(.inherited):
            String(localized: "This field belongs to a type above this one, so it can only be changed there.")
        case .unknownField:
            String(localized: "This type no longer has that field.")
        case .blankLabel:
            String(localized: "A field needs a name.")
        case .labelTooLong:
            String(localized: "A field’s name can be 100 characters at most.")
        case .labelInUse(let label):
            String(localized: "This type already has a field named “\(label)”.")
        case .notAChoiceField:
            String(localized: "This field doesn’t offer choices.")
        case .noChoices:
            String(localized: "A choice field needs at least one choice.")
        case .blankChoice:
            String(localized: "A choice needs a name.")
        case .repeatedChoice(let choice):
            String(localized: "“\(choice)” is in the list twice.")
        case .holdsPageContent:
            String(localized: "The page shows this field as the item’s title, its text or its link to the source, so it can’t be removed.")
        }
    }
}

/// One change to one field, checked against the type as the page shows it. `shown` is the field as it stood then,
/// which the server's own definition must still match when the change is sent.
nonisolated struct FieldEditPlan: Hashable, Sendable {
    let type: TypeID
    let edit: FieldEdit
    let shown: ItemTypeInfo.Field
    /// The choices the edit takes away, which items may still hold.
    var removedChoices: [String] = []
}

nonisolated extension ItemTypeInfo {
    /// The plan for `edit` on this type, or why it cannot be made. Nothing is sent before the plan holds.
    func plan(_ edit: FieldEdit) throws(FieldEditRefusal) -> FieldEditPlan {
        guard let field = fields.first(where: { $0.key == edit.key }) else { throw .unknownField }
        if let lock = lock(of: field) { throw .locked(lock) }
        switch edit {
        case .rename(_, let label):
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw .blankLabel }
            guard name.unicodeScalars.count <= 100 else { throw .labelTooLong }
            let clash = fields.contains { $0.key != field.key && Self.same($0.label, name) }
            guard !clash else { throw .labelInUse(name) }
            return FieldEditPlan(type: id, edit: .rename(key: field.key, label: name), shown: field)
        case .setChoices(_, let choices):
            guard case .choice(let old) = field.kind else { throw .notAChoiceField }
            let words = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !words.isEmpty else { throw .noChoices }
            guard !words.contains(where: \.isEmpty) else { throw .blankChoice }
            var seen: Set<String> = []
            for word in words where !seen.insert(word).inserted { throw .repeatedChoice(word) }
            return FieldEditPlan(
                type: id, edit: .setChoices(key: field.key, choices: words), shown: field,
                removedChoices: old.filter { !seen.contains($0) })
        case .remove:
            guard field.key != titleKey, field.key != bodyKey, field.key != linkField else { throw .holdsPageContent }
            return FieldEditPlan(type: id, edit: edit, shown: field)
        }
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Why the server did not take a change to a field, in terms the page can word for a person.
nonisolated enum TypeSchemaFailure: Error, Hashable, Sendable {
    case unreachable
    /// MAPP’s sign-in does not have `schema.write`, or no write on the type.
    case notPermitted
    case keyRefused
    /// The type is not as the page showed it: another app changed it, or removed it, since MAPP read it.
    case changedOnServer
    /// The server refused the change, with its own sentence.
    case refused(String)
    /// This library has no server to keep the change.
    case unsupported
    case failed(String)

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "MAPP can’t reach the server. Changing a field changes the type for every item, so it needs the server. Try again once it’s back.")
        case .notPermitted:
            String(localized: "This connection can’t change a type. Ask whoever runs the server to allow it, or sign in again and approve it.")
        case .keyRefused:
            String(localized: "The server has ended MAPP’s sign-in. Sign in again in Settings.")
        case .changedOnServer:
            String(localized: "This type has changed on the server since MAPP last read it, so nothing was changed. Look at the field again and try once more.")
        case .refused(let reason):
            reason
        case .unsupported:
            String(localized: "This library doesn’t keep changes to types.")
        case .failed(let message):
            message
        }
    }
}

/// Where a change to a field of a type is kept: on the server, for every app. The working copy does not take the change
/// until its stream reopens, so the library holds the answer itself meanwhile.
nonisolated protocol TypeSchemaSource: Sendable {
    /// Sends the change, after reading the type's own definition from the server again and finding the field as
    /// `plan.shown` says. Nothing is sent, and nothing changes, if it is not.
    func apply(_ plan: FieldEditPlan) async throws(TypeSchemaFailure)
}

nonisolated extension ItemTypeInfo {
    /// The type once `plan` is made: the field changed, here and in every type below that inherits it.
    func applying(_ plan: FieldEditPlan) -> ItemTypeInfo {
        guard fields.contains(where: { $0.key == plan.edit.key && $0.declaredBy == plan.type }) else { return self }
        let changed: [Field] = fields.compactMap { field in
            guard field.key == plan.edit.key, field.declaredBy == plan.type else { return field }
            switch plan.edit {
            case .rename(_, let label):
                return field.with(label: label)
            case .setChoices(_, let choices):
                return field.with(kind: .choice(choices))
            case .remove:
                return nil
            }
        }
        return ItemTypeInfo(
            id: id, label: label, plural: plural, fields: changed, titleField: titleField, bodyField: bodyField,
            parent: parent, icon: icon, description: description, version: version, roles: roles,
            compatibleWith: compatibleWith, linkField: linkField)
    }
}

nonisolated extension ItemTypeInfo.Field {
    func with(label: String? = nil, kind: Kind? = nil) -> ItemTypeInfo.Field {
        var changed = ItemTypeInfo.Field(key: key, label: label ?? self.label, kind: kind ?? self.kind, declaredBy: declaredBy)
        changed.required = required
        changed.description = description
        changed.format = format
        changed.isInteger = isInteger
        changed.minimum = minimum
        changed.maximum = maximum
        changed.maxItems = maxItems
        return changed
    }
}

nonisolated extension Catalogue {
    /// The catalogue once the server has taken `plan`: the declaring type and every type below it show the change.
    func applying(_ plan: FieldEditPlan) -> Catalogue {
        var changed = self
        for id in [plan.type] + descendants(of: plan.type).sorted(by: { $0.rawValue < $1.rawValue }) {
            if let info = itemTypes[id] { changed.itemTypes[id] = info.applying(plan) }
        }
        return changed
    }
}
