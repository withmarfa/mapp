import Foundation

/// What one type's Layouts page offers for each place of its look, and the words for each. Pure: it reads the catalogue and
/// asks `LookSurface` what the type can fill, so a place never offers a field the type lacks.
nonisolated struct LayoutChoices {
    let type: TypeID
    let catalogue: Catalogue
    private let surface: LookSurface

    init(type: TypeID, catalogue: Catalogue) {
        self.type = type
        self.catalogue = catalogue
        surface = LookSurface(type, in: catalogue)
    }

    /// The fields a look can name: those a person reads, leaving out the title and text the row already shows, the
    /// connector's own identity and bookkeeping, and the status, which always comes first.
    private var fields: [ItemTypeInfo.Field] {
        guard let info = surface.info else { return [] }
        return info.fields.filter { field in
            field.key != info.titleKey && field.key != info.bodyKey && field.key != info.linkField && !field.isStatus
                && !PagePlacement.isBookkeeping(field)
        }
    }

    // MARK: Offers

    /// The dates a row can show, the type's own date fields first.
    var dates: [LookDate] {
        fields.filter { if case .date = $0.kind { true } else { false } }.map { .field($0.key) } + [.created, .edited, .occurred, .off]
    }

    /// The parts of the line under the title.
    var parts: [LookPart] {
        var parts: [LookPart] = [.opening]
        parts += fields.map { LookPart.field($0.key) }
        parts += fields.filter { surface.offers(LookPart.time($0.key)) }.map { LookPart.time($0.key) }
        parts += [.site, .file, .parent].filter(surface.offers)
        return parts
    }

    /// The facts after the status.
    var facts: [LookFact] {
        var facts: [LookFact] = fields.map { LookFact.field($0.key) }
        facts.append(.tags)
        facts += Relation.allCases.filter { surface.relations.contains($0) }.map { LookFact.relation($0) }
        facts += [CountFact.children, .progress, .members].filter(surface.offers).map { LookFact.count($0) }
        return facts
    }

    // MARK: Words

    func title(of date: LookDate) -> String {
        switch date {
        case .field(let key): fieldLabel(key)
        case .created: String(localized: "Created")
        case .edited: String(localized: "Edited")
        case .occurred: String(localized: "Happened")
        case .off: String(localized: "None")
        }
    }

    func title(of part: LookPart) -> String {
        switch part {
        case .field(let key): fieldLabel(key)
        case .time(let key): String(localized: "Time of \(fieldLabel(key))")
        case .opening: String(localized: "Opening Line")
        case .site: String(localized: "Website")
        case .file: String(localized: "File Kind and Size")
        case .parent: Relation.parent.label(in: catalogue)
        }
    }

    func title(of fact: LookFact) -> String {
        switch fact {
        case .field(let key): fieldLabel(key)
        case .tags: String(localized: "Tags")
        case .relation(let relation): relation.label(in: catalogue)
        case .count(let count):
            switch count {
            case .children: String(localized: "Number of Children")
            case .progress: String(localized: "Progress")
            case .members: String(localized: "Number of Members")
            case .rows(let table): String(localized: "Rows of \(table)")
            }
        }
    }

    private func fieldLabel(_ key: String) -> String {
        catalogue.label(ofField: key, for: type) ?? key
    }
}

/// How a type's look is told on the Layouts list: where it starts from, and how much was changed.
nonisolated extension LookPreset {
    /// "As a note", the way the type starts.
    var startsAs: String {
        switch self {
        case .note: String(localized: "As a note")
        case .message: String(localized: "As a message")
        case .task: String(localized: "As a task")
        case .event: String(localized: "As an event")
        case .person: String(localized: "As a person")
        case .place: String(localized: "As a place")
        case .media: String(localized: "As media")
        case .quote: String(localized: "As a quote")
        case .clip: String(localized: "As a clip")
        case .record: String(localized: "As a record")
        }
    }
}
