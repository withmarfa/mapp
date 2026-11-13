import Foundation

/// The date a type's rows, cards and table show: a date field of the type, when the item was made or last changed, when
/// it happened, or none. An item that holds no value in the field shows when it was last changed.
nonisolated enum LookDate: Hashable, Sendable {
    case field(String)
    case created
    case edited
    /// Marfa's own `occurred_at`, which every item has and no type can declare as a field: when the item happened (a
    /// quote was captured, something was copied, a message was sent, a record took place). An item with none shows when
    /// it was created (`Item.occurred`).
    case occurred
    /// No date is shown.
    case off
}

/// One part of the line under a title. A look joins up to two of them, the ones that have a value, with ", ".
nonisolated enum LookPart: Hashable, Sendable {
    /// A field of the type, shown as its value.
    case field(String)
    /// A date field of the type, shown as its time of day alone, so a day shown elsewhere is not shown twice. It is only
    /// for a field that includes a time, and an all-day value shows nothing for this part.
    case time(String)
    /// The item's opening line, as the server gives it (`Item.preview`).
    case opening
    /// The website a web address names, worked out from the type's `url`.
    case site
    /// A file's kind and size, worked out from the file.
    case file
}

/// One thing on the bottom line, after the status. Later kinds MAPP builds (a count, a reading time, a relation) are new
/// cases here.
nonisolated enum LookFact: Hashable, Sendable {
    /// A field of the type: an option, a list of people, a number or a date.
    case field(String)
    case tags
}

/// How one type looks wherever its items are listed or shown as cards or rows of a table: the date, the line under the
/// title and the facts on the bottom line. A type with a status field always shows its status first, so the status
/// is no fact. It is the one look every view reads; a view adds only its layout and density.
nonisolated struct TypeLook: Hashable, Sendable {
    var date: LookDate
    /// At most two parts (`maxSecondary`), in order.
    var secondary: [LookPart]
    /// The facts in the order they show; a view shows as many as it has room for.
    var facts: [LookFact]

    static let maxSecondary = 2

    /// The look of a type with nothing to show.
    static let empty = TypeLook(date: .off, secondary: [], facts: [])

    init(date: LookDate, secondary: [LookPart], facts: [LookFact]) {
        self.date = date
        self.secondary = Array(secondary.prefix(Self.maxSecondary))
        self.facts = facts
    }
}

/// What a person chose for one type, place by place. A place not chosen is nil: it is worked out from the type's preset
/// and its parent every time, so improving a preset improves every look not chosen.
nonisolated struct TypeLookChoice: Hashable, Sendable {
    var date: LookDate?
    var secondary: [LookPart]?
    var facts: [LookFact]?

    init(date: LookDate? = nil, secondary: [LookPart]? = nil, facts: [LookFact]? = nil) {
        self.date = date
        self.secondary = secondary.map { Array($0.prefix(TypeLook.maxSecondary)) }
        self.facts = facts
    }

    /// Every place chosen, as the look it holds.
    init(_ look: TypeLook) {
        self.init(date: look.date, secondary: look.secondary, facts: look.facts)
    }

    var isEmpty: Bool { date == nil && secondary == nil && facts == nil }
}

// MARK: Stored words

/// The words a look is stored and exported in: `field:due_at`, `time:starts_at`, `opening`, `tags`. A word this version does not know
/// makes the whole look unreadable, never a look with a place missing.
nonisolated protocol LookWord: Codable, Sendable {
    var word: String { get }
    init?(word: String)
}

nonisolated extension LookWord {
    init(from decoder: any Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(word: word) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown look word"))
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(word)
    }

    /// The key after `prefix` (`field:` or `time:`), where the word names a field.
    fileprivate static func fieldKey(in word: String, after prefix: String = "field:") -> String? {
        guard word.hasPrefix(prefix), word.count > prefix.count else { return nil }
        return String(word.dropFirst(prefix.count))
    }
}

nonisolated extension LookDate: LookWord {
    var word: String {
        switch self {
        case .field(let key): "field:" + key
        case .created: "created"
        case .edited: "edited"
        case .occurred: "occurred"
        case .off: "none"
        }
    }

    init?(word: String) {
        switch word {
        case "created": self = .created
        case "edited": self = .edited
        case "occurred": self = .occurred
        case "none": self = .off
        default:
            guard let key = Self.fieldKey(in: word) else { return nil }
            self = .field(key)
        }
    }
}

nonisolated extension LookPart: LookWord {
    var word: String {
        switch self {
        case .field(let key): "field:" + key
        case .time(let key): "time:" + key
        case .opening: "opening"
        case .site: "site"
        case .file: "file"
        }
    }

    init?(word: String) {
        switch word {
        case "opening": self = .opening
        case "site": self = .site
        case "file": self = .file
        default:
            if let key = Self.fieldKey(in: word) {
                self = .field(key)
            } else if let key = Self.fieldKey(in: word, after: "time:") {
                self = .time(key)
            } else {
                return nil
            }
        }
    }
}

nonisolated extension LookFact: LookWord {
    var word: String {
        switch self {
        case .field(let key): "field:" + key
        case .tags: "tags"
        }
    }

    init?(word: String) {
        if word == "tags" {
            self = .tags
        } else if let key = Self.fieldKey(in: word) {
            self = .field(key)
        } else {
            return nil
        }
    }
}

nonisolated extension TypeLook: Codable {
    private enum CodingKeys: String, CodingKey { case date, secondary, facts }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try values.decode(LookDate.self, forKey: .date),
            secondary: try values.decode([LookPart].self, forKey: .secondary),
            facts: try values.decode([LookFact].self, forKey: .facts))
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(date, forKey: .date)
        try values.encode(secondary, forKey: .secondary)
        try values.encode(facts, forKey: .facts)
    }
}

nonisolated extension TypeLookChoice: Codable {
    private enum CodingKeys: String, CodingKey { case date, secondary, facts }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try values.decodeIfPresent(LookDate.self, forKey: .date),
            secondary: try values.decodeIfPresent([LookPart].self, forKey: .secondary),
            facts: try values.decodeIfPresent([LookFact].self, forKey: .facts))
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(date, forKey: .date)
        try values.encodeIfPresent(secondary, forKey: .secondary)
        try values.encodeIfPresent(facts, forKey: .facts)
    }
}
