import Foundation

/// Where an item's Linked From list shows: at the foot of its page, or in the inspector.
nonisolated enum LinkedFromPlace: String, Codable, Sendable {
    case page, inspector
}

/// Where an item's properties show, for each type: MAPP's own setting, kept as one value in the defaults and never
/// sent to Marfa. The inspector always lists every property of an item. This says which of them the page shows too,
/// and where Linked From goes. A type the person has never customized has no entry and follows the defaults in
/// `PagePlacement`.
nonisolated struct PagePlacements: Equatable, Sendable {
    static let key = "pagePlacements"

    /// What the person chose for one type. A row not named here follows the default.
    struct Choice: Codable, Equatable, Sendable {
        /// Row identifiers (`PagePlacement`) the person chose to show on the page (true) or keep off it (false).
        var rows: [String: Bool] = [:]
        var linkedFrom: LinkedFromPlace?

        var isEmpty: Bool { rows.isEmpty && linkedFrom == nil }
    }

    /// By type identifier.
    private(set) var choices: [String: Choice]

    init(_ choices: [String: Choice] = [:]) {
        self.choices = choices.filter { !$0.value.isEmpty }
    }

    /// How the page treats items of `type`: the person's choice over the defaults.
    func placement(of type: TypeID, in catalogue: Catalogue) -> PagePlacement {
        PagePlacement(type: type, catalogue: catalogue, choice: choices[type.rawValue] ?? Choice())
    }

    func hasChoice(for type: TypeID) -> Bool { choices[type.rawValue] != nil }

    mutating func setShown(_ shown: Bool, row: String, of type: TypeID) {
        update(type) { $0.rows[row] = shown }
    }

    /// Chooses whether the page shows a row. Linked From is either on the page or in the inspector, so showing it
    /// moves it.
    mutating func set(_ shown: Bool, row: String, of type: TypeID) {
        if row == PagePlacement.linkedFrom {
            setLinkedFrom(shown ? .page : .inspector, of: type)
        } else {
            setShown(shown, row: row, of: type)
        }
    }

    mutating func setLinkedFrom(_ place: LinkedFromPlace, of type: TypeID) {
        update(type) { $0.linkedFrom = place }
    }

    /// Takes back every choice for the type, so it follows the defaults again.
    mutating func reset(_ type: TypeID) {
        choices[type.rawValue] = nil
    }

    private mutating func update(_ type: TypeID, _ change: (inout Choice) -> Void) {
        var choice = choices[type.rawValue] ?? Choice()
        change(&choice)
        choices[type.rawValue] = choice.isEmpty ? nil : choice
    }
}

/// The choice as `@AppStorage` keeps it: JSON with sorted keys, so the same choice is the same text.
nonisolated extension PagePlacements: RawRepresentable {
    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(choices)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init?(rawValue: String) {
        guard let choices = try? JSONDecoder().decode([String: Choice].self, from: Data(rawValue.utf8)) else { return nil }
        self.init(choices)
    }
}

nonisolated extension PagePlacements {
    static func stored(in defaults: UserDefaults = .standard) -> PagePlacements {
        defaults.string(forKey: key).flatMap(PagePlacements.init(rawValue:)) ?? PagePlacements()
    }

    static func update(in defaults: UserDefaults = .standard, _ change: (inout PagePlacements) -> Void) {
        var value = stored(in: defaults)
        change(&value)
        defaults.set(value.rawValue, forKey: key)
    }
}

/// What the page shows of one type's items. A row is named by its identifier: a field's key, a relationship's field
/// (the parent's is `child-of`), `#tags`, or `#linked` for Linked From.
nonisolated struct PagePlacement: Equatable, Sendable {
    static let tags = "#tags"
    static let linkedFrom = "#linked"

    /// The type's link field: the connector's own identity for the item, which says nothing to a person.
    let linkField: String?
    let choice: PagePlacements.Choice
    private let defaultLinkedFrom: LinkedFromPlace
    /// The keys of the type's fields that only a connector's bookkeeping needs (`isBookkeeping`).
    private let bookkeeping: Set<String>

    /// Every row on the page, as before any choice was made.
    static let standard = PagePlacement(linkField: nil, choice: .init(), defaultLinkedFrom: .inspector)

    init(linkField: String?, choice: PagePlacements.Choice, defaultLinkedFrom: LinkedFromPlace, bookkeeping: Set<String> = []) {
        self.linkField = linkField
        self.choice = choice
        self.defaultLinkedFrom = defaultLinkedFrom
        self.bookkeeping = bookkeeping
    }

    init(type: TypeID, catalogue: Catalogue, choice: PagePlacements.Choice) {
        // A person's page lists who they have been with, and a collection's lists what it holds, so each keeps its
        // links on the page. Every other item's links are for looking up, which the inspector is for.
        let kind = PageHeaderKind.of(type, in: catalogue)
        self.init(
            linkField: catalogue.itemTypes[type]?.linkField, choice: choice,
            defaultLinkedFrom: kind == .person || catalogue.isCollection(type) ? .page : .inspector,
            bookkeeping: Set((catalogue.itemTypes[type]?.fields ?? []).filter(Self.isBookkeeping).map(\.key)))
    }

    /// Whether a field is a connector's bookkeeping, which says nothing to a person reading the page: one that a
    /// connector's type declares (a core type's fields are Marfa's own vocabulary and always read as content), whose
    /// key names an identifier or a checksum of what the connector synced from (`entry_id`, `feed_hash`,
    /// `github_id`, `blob_sha`, `ical_uid`, `etag`). A catalogue says no more of a type than who declares its
    /// fields, so a field of a type a person made with such a key is read the same way; the choice overrides it.
    static func isBookkeeping(_ field: ItemTypeInfo.Field) -> Bool {
        guard !field.declaredBy.rawValue.hasPrefix("core.") else { return false }
        let key = field.key
        return key == "etag" || ["_id", "_hash", "_sha", "_uid"].contains { key.hasSuffix($0) }
    }

    func showsOnPage(_ row: String) -> Bool { choice.rows[row] ?? defaultShows(row) }

    var linkedFromPlace: LinkedFromPlace { choice.linkedFrom ?? defaultLinkedFrom }

    private func defaultShows(_ row: String) -> Bool { row != linkField && !bookkeeping.contains(row) }
}
