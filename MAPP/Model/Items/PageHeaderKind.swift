import Foundation

/// Which header an item's page draws above its text, chosen by the core type the item's type builds on: the page
/// is the general one (title, byline, properties, Linked From), and these extend it with what a person looks
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
    /// `core.file.webpage`: the page itself. A file has no text to edit, so the page draws a title and byline above
    /// the HTML (`WebPageItemPage`), not the editor's header.
    case webpage

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
        TypeID("core.file.webpage"): .webpage,
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
        case .general, .webpage:
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

    /// The rows of the property block with the kind's own readings of them: a person's number to call is a link, not
    /// text. Marfa declares no phone format, so a list entry's text reads as a number to call by what it holds, never by
    /// the name of the field that holds it.
    func refine(_ rows: [PropertyRow]) -> [PropertyRow] {
        guard kind == .person else { return rows }
        return rows.map { row in
            guard row.fromList, case .text(let text) = row.value, Self.isDialable(text) else { return row }
            return PropertyRow(id: row.id, label: row.label, value: .phone(text), fromList: true)
        }
    }

    /// Whether the text is a telephone number as people write one: digits, with a leading plus, spaces, brackets,
    /// dots and dashes between them, and at least five digits.
    static func isDialable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isNumber).count >= 5, let first = trimmed.first, first == "+" || first == "(" || first.isNumber else { return false }
        return trimmed.allSatisfy { $0.isNumber || " +()-.".contains($0) }
    }
}

extension ItemLibrary {
    /// The web address "Open Original" opens: the `url` of an item whose page is for reading, if it is one.
    func originalAddress(of item: Item) -> URL? {
        guard PageHeaderKind.of(item.type, in: catalogue) == .reading else { return nil }
        return ReadingHeader.webAddress(item.value(of: "url")?.string?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What "Open in Browser" opens for `item`, if it is a Web Page. `fetchedFile` is the page's file once the window
    /// has it.
    func browserTarget(of item: Item, fetchedFile: URL?) -> BrowserTarget? {
        guard PageHeaderKind.of(item.type, in: catalogue) == .webpage else { return nil }
        return BrowserTarget.of(item, fetchedFile: fetchedFile)
    }

    /// Whether the item is a Web Page, which has the "Open in Browser" action.
    func isWebPage(_ item: Item) -> Bool { PageHeaderKind.of(item.type, in: catalogue) == .webpage }
}
