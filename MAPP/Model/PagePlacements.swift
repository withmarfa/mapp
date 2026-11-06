import Foundation

/// Where an item's Linked From list shows: at the foot of its page, or in the inspector.
nonisolated enum LinkedFromPlace: String, Codable, Sendable {
    case page, inspector
}

/// Where an item's properties show, for each type: MAPP's own setting, kept as one value in the defaults and never
/// sent to Marfa. The inspector always lists every property of an item. This says which of them the page shows too,
/// which are pinned under its title (at most four, in order), and where Linked From goes. A type the person has never
/// customized has no entry and follows the defaults in `PagePlacement`.
nonisolated struct PagePlacements: Equatable, Sendable {
    static let key = "pagePlacements"

    /// What the person chose for one type. A row not named here follows the default.
    struct Choice: Codable, Equatable, Sendable {
        /// Row identifiers (`PagePlacement`) the person chose to show on the page (true) or keep off it (false).
        var rows: [String: Bool] = [:]
        var linkedFrom: LinkedFromPlace?
        /// The row identifiers pinned under the title, in order. Nil follows the default pins; an empty list is a
        /// choice, that nothing is pinned. Optional so a choice saved before pins existed still decodes.
        var pins: [String]?

        var isEmpty: Bool { rows.isEmpty && linkedFrom == nil && pins == nil }
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

    /// The properties pinned for `type`, in order: the person's list, or the default pins with none chosen. At most
    /// four, none twice. An identifier the type no longer has stays in the list, and the page skips it.
    func pins(of type: TypeID, in catalogue: Catalogue) -> [String] {
        placement(of: type, in: catalogue).pins
    }

    /// Pins exactly these (the first four, none twice), taking the place of the default pins.
    mutating func setPins(_ pins: [String], of type: TypeID) {
        update(type) { $0.pins = PagePlacement.limited(pins) }
    }

    /// Pins `row` after the others. Returns whether it is pinned: false where four are already, and the list is left
    /// alone. A row already pinned stays where it is. The default pins are the list to add to while none is chosen,
    /// which is why the catalogue is asked.
    @discardableResult
    mutating func pin(_ row: String, of type: TypeID, in catalogue: Catalogue) -> Bool {
        let pins = pins(of: type, in: catalogue)
        if pins.contains(row) { return true }
        guard pins.count < PagePlacement.pinLimit else { return false }
        setPins(pins + [row], of: type)
        return true
    }

    mutating func unpin(_ row: String, of type: TypeID, in catalogue: Catalogue) {
        setPins(pins(of: type, in: catalogue).filter { $0 != row }, of: type)
    }

    /// Moves a pinned row to `index` among the pins, which is kept within them. A row that is not pinned stays unpinned.
    mutating func movePin(_ row: String, to index: Int, of type: TypeID, in catalogue: Catalogue) {
        var pins = pins(of: type, in: catalogue)
        guard let from = pins.firstIndex(of: row) else { return }
        pins.remove(at: from)
        pins.insert(row, at: min(max(index, 0), pins.count))
        setPins(pins, of: type)
    }

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
/// (the parent's is `child-of`), `#type`, `#source`, `#updated` (the item's own type, source and last edit), `#tags`,
/// or `#linked` for Linked From.
nonisolated struct PagePlacement: Equatable, Sendable {
    static let type = "#type"
    static let source = "#source"
    static let updated = "#updated"
    static let tags = "#tags"
    static let linkedFrom = "#linked"
    /// The relationship the parent is held in.
    static let parent = "child-of"
    /// The most properties a page pins.
    static let pinLimit = 4

    /// The properties pinned under the title, in order (`pinLimit` at most, none twice): the person's choice, or with
    /// none the type's own, then the status, the parent and the last edit. A default pin that a saved choice turned
    /// off (`choice.rows[id] == false`) stays off, since that is the person's choice too.
    let pins: [String]

    /// The type's link field: the connector's own identity for the item, which says nothing to a person.
    let linkField: String?
    let choice: PagePlacements.Choice
    private let defaultLinkedFrom: LinkedFromPlace
    /// The keys of the type's fields that only a connector's bookkeeping needs (`isBookkeeping`).
    private let bookkeeping: Set<String>

    /// Every row on the page, as before any choice was made.
    static let standard = PagePlacement(linkField: nil, choice: .init(), defaultLinkedFrom: .inspector)

    init(
        linkField: String?, choice: PagePlacements.Choice, defaultLinkedFrom: LinkedFromPlace, bookkeeping: Set<String> = [],
        pins: [String] = []
    ) {
        self.linkField = linkField
        self.choice = choice
        self.defaultLinkedFrom = defaultLinkedFrom
        self.bookkeeping = bookkeeping
        self.pins = pins
    }

    init(type: TypeID, catalogue: Catalogue, choice: PagePlacements.Choice) {
        // A person's page lists who they have been with, and a collection's lists what it holds, so each keeps its
        // links on the page. Every other item's links are for looking up, which the inspector is for.
        let kind = PageHeaderKind.of(type, in: catalogue)
        let info = catalogue.itemTypes[type]
        let pins = choice.pins
            ?? [Self.type, info?.statusField?.key, Self.parent, Self.updated].compactMap { $0 }.filter { choice.rows[$0] != false }
        self.init(
            linkField: info?.linkField, choice: choice,
            defaultLinkedFrom: kind == .person || catalogue.isCollection(type) ? .page : .inspector,
            bookkeeping: Set((info?.fields ?? []).filter(Self.isBookkeeping).map(\.key)), pins: Self.limited(pins))
    }

    /// The first `pinLimit` of `rows`, each once.
    static func limited(_ rows: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(rows.filter { seen.insert($0).inserted }.prefix(pinLimit))
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
