import Foundation

/// Which header an item's page draws above its text, chosen by the core type the item's type builds on: the page
/// is the general one (title, byline, properties, Linked From), and these three extend it with what a person looks
/// for first. A type nobody at WithMarfa defined takes the nearest core type above it through the parents the
/// catalogue names, so the app names no type a person or an app made.
nonisolated enum PageHeaderKind: String, Encodable, Sendable {
    case general
    /// `core.event`: when and where.
    case event
    /// `core.entity.person`: who, and how to reach them.
    case person
    /// `core.bookmark` and `core.media`: something to read.
    case reading

    static func of(_ type: TypeID, in catalogue: Catalogue) -> PageHeaderKind {
        var visited: Set<TypeID> = []
        var current: TypeID? = type
        while let id = current, visited.insert(id).inserted {
            if let kind = builtIn[id] { return kind }
            current = catalogue.itemTypes[id]?.parent
        }
        return .general
    }

    private static let builtIn: [TypeID: PageHeaderKind] = [
        TypeID("core.event"): .event,
        TypeID("core.entity.person"): .person,
        TypeID("core.bookmark"): .reading,
        TypeID("core.media"): .reading,
    ]
}

/// What a kind of header adds to the general page for one item: the block it draws, the line under the title, and
/// the properties it already shows, which leave the property block so nothing is shown twice.
nonisolated struct PageHeaderLead: Equatable, Sendable {
    var kind = PageHeaderKind.general
    var event: EventHeader?
    var person: PersonHeader?
    /// A person's job and organization, or a reading item's description (its dek).
    var subtitle: String?
    /// Replaces the general byline (the source, then the day the item was made) where the kind knows better.
    var byline: PageByline?
    /// The type is left out of the byline where the kind's own line says what the item is.
    var showsType = true
    /// The keys of the item's properties the header draws.
    var consumed: Set<String> = []

    static let general = PageHeaderLead()

    /// The lead for `item`. `body` is its text, which a reading time is counted from.
    init(
        for item: Item, kind: PageHeaderKind, body: String?, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) {
        self.kind = kind
        switch kind {
        case .general:
            break
        case .event:
            if let event = EventHeader(item: item, now: now, calendar: calendar, locale: locale) {
                self.event = event
                consumed = EventHeader.keys
            }
        case .person:
            let person = PersonHeader(item: item)
            self.person = person
            subtitle = person.subtitle
            consumed = PersonHeader.keys
        case .reading:
            let reading = ReadingHeader(item: item, body: body, locale: locale, calendar: calendar)
            subtitle = reading.dek
            byline = reading.byline
            showsType = false
            consumed = ReadingHeader.keys
        }
    }

    private init() {}

    /// The rows of the property block with the kind's own readings of them: a person's phone number is a number to
    /// call, not text.
    func refine(_ rows: [PropertyRow]) -> [PropertyRow] {
        guard kind == .person else { return rows }
        return rows.map { row in
            guard row.id == "phone", case .text(let number) = row.value else { return row }
            return PropertyRow(id: row.id, label: row.label, value: .phone(number))
        }
    }
}

extension ItemLibrary {
    /// The web address "Open Original" opens: the `url` of an item whose page is for reading, if it is one.
    func originalAddress(of item: Item) -> URL? {
        guard PageHeaderKind.of(item.type, in: catalogue) == .reading else { return nil }
        return ReadingHeader.webAddress(item.value(of: "url")?.string?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
