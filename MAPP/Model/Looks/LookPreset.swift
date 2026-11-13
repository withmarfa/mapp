import Foundation

/// What one type has to show a look with: its fields, and whether it is a file. A place of a look that asks for more than
/// the type has stays empty, so a look is always safe to read.
nonisolated struct LookSurface: Sendable {
    let info: ItemTypeInfo?
    let isFile: Bool

    init(_ type: TypeID, in catalogue: Catalogue) {
        info = catalogue.itemTypes[type]
        isFile = catalogue.isFileType(type)
    }

    func field(_ key: String) -> ItemTypeInfo.Field? { info?.fields.first { $0.key == key } }

    func offers(_ date: LookDate) -> Bool {
        guard case .field(let key) = date else { return true }
        if case .date? = field(key)?.kind { return true }
        return false
    }

    func offers(_ part: LookPart) -> Bool {
        switch part {
        case .field(let key): field(key) != nil
        case .time(let key):
            if case .date(includesTime: true)? = field(key)?.kind { true } else { false }
        case .opening: true
        case .site: field(MarfaMapping.urlField) != nil
        case .file: isFile
        }
    }

    func offers(_ fact: LookFact) -> Bool {
        switch fact {
        case .field(let key): field(key) != nil
        case .tags: true
        }
    }

    /// `look` with every place the type cannot fill taken out: the date falls back to `fallback`'s.
    func fitting(_ look: TypeLook, fallback: LookDate) -> TypeLook {
        TypeLook(
            date: offers(look.date) ? look.date : fallback, secondary: look.secondary.filter(offers), facts: look.facts.filter(offers))
    }
}

/// The ten starting looks, one for each kind of thing a person keeps. A type is given one from its fields
/// (`suggested(for:in:)`), and the preset fills the look's places from the fields the type has (`look(for:in:)`).
/// Marfa's core types, and any type that builds on them, are covered by the fields they share; a preset names no type.
nonisolated enum LookPreset: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case note, message, task, event, person, place, media, quote, clip, record

    var id: Self { self }

    // MARK: Suggesting

    /// The preset a type's fields suggest. The first that fits wins, so the order is the rule:
    ///
    /// 1. **Quote:** the type is, or builds on, Marfa's highlight (`core.highlight`), which no field alone tells.
    /// 2. **Place:** `latitude` and `longitude` with an address field (street, locality or postal code). An event or an
    ///    image has coordinates and no address, so it is not one. Place comes before Person, since a place builds on an
    ///    entity and carries its emails and phones.
    /// 3. **Person:** a person by `PageHeaderKind`, or a type that itself declares `emails` or `phones` (`Field.declaredBy`
    ///    is the type), as a bare `core.entity` does. A child that only inherits them, such as a repository built on an
    ///    entity, is not a person and takes the preset its own fields suggest.
    /// 4. **Media:** a file type (`Catalogue.isFileType`), or a type whose page is for reading (`PageHeaderKind.reading`,
    ///    a bookmark or media). It comes before Task, since media has a progress status.
    /// 5. **Record:** a number with a currency code. A record's date is Marfa's own `occurred_at` (`LookDate.occurred`),
    ///    which no type declares, so it cannot tell a record.
    /// 6. **Task:** a status field, whatever it is called.
    /// 7. **Event:** a start date (`Catalogue.isStartDate`). A task has one too, and has been taken already.
    /// 8. **Message:** a `from` field.
    /// 9. **Clip:** a `source_app` field, the app something was copied from.
    /// 10. **Note:** anything else, including a type with no fields at all and a type the catalogue lacks.
    static func suggested(for type: TypeID, in catalogue: Catalogue) -> LookPreset {
        guard let info = catalogue.itemTypes[type] else { return .note }
        if type == MarfaMapping.highlightType || catalogue.isSubtype(type, ofAnyOf: [MarfaMapping.highlightType]) { return .quote }
        let declares = info.declares
        if info.isPlace { return .place }
        let header = PageHeaderKind.of(type, in: catalogue)
        let reachesItself = info.fields.contains {
            $0.declaredBy == type && ($0.key == MarfaMapping.emailsField || $0.key == MarfaMapping.phonesField)
        }
        if header == .person || reachesItself { return .person }
        if catalogue.isFileType(type) || header == .reading { return .media }
        if info.fields.contains(where: { $0.kind == .number }), info.fields.contains(where: { $0.format == .currency }) { return .record }
        if info.statusField != nil { return .task }
        if info.fields.contains(where: { catalogue.isStartDate($0, of: type) }) { return .event }
        if declares(MarfaMapping.fromField) { return .message }
        if declares(MarfaMapping.sourceAppField) { return .clip }
        return .note
    }

    // MARK: Filling

    /// What the preset names for each place, before the type's fields are looked at.
    private struct Template {
        /// The date fields, the first the type has wins, and what an item shows where the type has none.
        var dateFields: [String] = []
        var fallback: LookDate
        /// The parts of the line under the title: each slot takes the first of its alternatives the type offers, and
        /// the slots are joined.
        var slots: [[LookPart]] = []
        /// The facts, each the first of its alternatives the type offers.
        var facts: [[LookFact]] = []
    }

    private var template: Template {
        let field = LookPart.field
        let fact = LookFact.field
        switch self {
        case .note:
            // The preset table gives a Note its tags, so its row shows them though no other preset's does.
            return Template(fallback: .edited, slots: [[.opening]], facts: [[.tags]])
        case .message:
            return Template(fallback: .occurred, slots: [[field(MarfaMapping.fromField)]])
        case .task:
            return Template(
                dateFields: [MarfaMapping.dueField], fallback: .edited,
                slots: [[field(MarfaMapping.projectField), field(MarfaMapping.repositoryField)]],
                facts: [[fact(MarfaMapping.priorityField)], [fact(MarfaMapping.assigneesField)]])
        case .event:
            return Template(
                dateFields: [MarfaMapping.startField], fallback: .edited,
                slots: [[.time(MarfaMapping.startField)], [field(MarfaMapping.placeField)]],
                facts: [[fact(MarfaMapping.attendeesField)]])
        case .person:
            return Template(
                fallback: .off, slots: [[field(MarfaMapping.jobTitleField)], [field(MarfaMapping.organizationField)]],
                facts: [[fact(MarfaMapping.emailsField), fact(MarfaMapping.phonesField)]])
        case .place:
            return Template(
                fallback: .off, slots: [[field(MarfaMapping.streetAddressField)], [field(MarfaMapping.localityField)]],
                facts: [[fact(MarfaMapping.categoryField)]])
        case .media:
            return Template(
                dateFields: [MarfaMapping.publishedField], fallback: .created,
                slots: [[.file, .site], [field(MarfaMapping.authorField)]], facts: [[fact(MarfaMapping.durationField)]])
        case .quote:
            return Template(
                fallback: .occurred, slots: [[field(MarfaMapping.passageField), .opening]],
                facts: [[fact(MarfaMapping.startLocationField)]])
        case .clip:
            return Template(fallback: .occurred, slots: [[.opening]], facts: [[fact(MarfaMapping.sourceAppField)]])
        case .record:
            // The numbers are the type's own, so they are added from its fields below.
            return Template(fallback: .occurred, slots: [[field(MarfaMapping.categoryField)]])
        }
    }

    /// The preset's look for `type`: each place filled from the fields the type has, and empty where it has none. The
    /// date is the first of the preset's date fields the type has, else the preset's own fallback.
    func look(for type: TypeID, in catalogue: Catalogue) -> TypeLook {
        let surface = LookSurface(type, in: catalogue)
        let template = template
        let date = template.dateFields.first { surface.offers(LookDate.field($0)) }.map { LookDate.field($0) } ?? template.fallback
        let secondary = template.slots.compactMap { $0.first(where: surface.offers) }
        var facts = template.facts.compactMap { $0.first(where: surface.offers) }
        if self == .record, let info = surface.info { facts = Self.amounts(of: info) }
        return TypeLook(date: date, secondary: secondary, facts: facts)
    }

    /// A record's numbers in the order the type declares them, with the currency code after the first, since the amount
    /// means nothing without it.
    private static func amounts(of info: ItemTypeInfo) -> [LookFact] {
        var numbers = info.fields.filter { $0.kind == .number }.map { LookFact.field($0.key) }
        if let currency = info.fields.first(where: { $0.format == .currency }), !numbers.isEmpty {
            numbers.insert(.field(currency.key), at: 1)
        }
        return numbers
    }
}
