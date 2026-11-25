import Foundation

/// Where an item's Linked From list shows: at the foot of its page, or only in the panel.
nonisolated enum LinkedFromPlace: String, Codable, Sendable {
    case page, inspector
}

/// Where an item's properties show, for each type: the app's own setting, kept as one value in the defaults and synced
/// through the Marfa (`PreferencesMap`). The page lists every property of an item behind Show More. This says which of them
/// show, which are pinned under its title (at most four, in order), and where Linked From goes. A type the
/// person has never customized has no entry and follows the defaults in `PagePlacement`.
nonisolated struct PagePlacements: Equatable, Sendable {
    static let key = "pagePlacements"
    /// Each entry is stored text that could not be read, in the order it was found.
    static let setAsideKey = "pagePlacementsSetAside"

    /// What the person chose for one type. A row not named here follows the default.
    struct Choice: Codable, Equatable, Sendable {
        /// How each row the person placed shows on the type's pages, by its identifier (`PagePlacement`).
        var shows: [String: RowShows] = [:]
        /// The word a row's `shows` holds that this version does not name, by row, as it was stored. Rewriting the choice
        /// keeps it until the person chooses how that row shows.
        var otherShows: [String: String] = [:]
        var linkedFrom: LinkedFromPlace?
        /// The row identifiers pinned under the title, in order, while pinned properties are on
        /// (`PageKey.pinsProperties`). Nil follows the default pins; an empty list is a choice, that nothing is pinned.
        var pins: [String]?
        /// The row identifiers in the order the page lists them. A row not named keeps its own order after those named.
        /// Nil follows the default order.
        var rowOrder: [String]?
        /// Every member this version does not name, as it was stored: an older or a later copy wrote it, and rewriting the
        /// row keeps it.
        var others: [String: StoredJSON] = [:]

        var isEmpty: Bool {
            shows.isEmpty && otherShows.isEmpty && linkedFrom == nil && pins == nil && rowOrder == nil && others.isEmpty
        }

        init(shows: [String: RowShows] = [:], linkedFrom: LinkedFromPlace? = nil, pins: [String]? = nil, rowOrder: [String]? = nil) {
            self.shows = shows
            self.linkedFrom = linkedFrom
            self.pins = pins
            self.rowOrder = rowOrder
        }

        private static let known: Set<String> = ["shows", "rows", "linkedFrom", "pins", "rowOrder"]

        /// Every member is optional on reading, and `shows` is read first. A choice saved as shown or hidden (`rows`,
        /// true or false) is read as When It Has a Value or Hidden. A word a later version adds to `shows` is kept apart
        /// in `otherShows`, and the row follows the default while it is there.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            if let words = try container.decodeIfPresent([String: String].self, forKey: DynamicKey("shows")) {
                shows = words.compactMapValues(RowShows.init(rawValue:))
                otherShows = words.filter { RowShows(rawValue: $0.value) == nil }
            } else if let rows = try container.decodeIfPresent([String: Bool].self, forKey: DynamicKey("rows")) {
                shows = rows.mapValues { $0 ? .whenSet : .hidden }
            }
            linkedFrom = try container.decodeIfPresent(LinkedFromPlace.self, forKey: DynamicKey("linkedFrom"))
            pins = try container.decodeIfPresent([String].self, forKey: DynamicKey("pins"))
            rowOrder = try container.decodeIfPresent([String].self, forKey: DynamicKey("rowOrder"))
            others = try container.members(except: Self.known)
        }

        /// Writes `rows` (true unless hidden) beside `shows`, always, even with none placed. A copy from before `shows`
        /// requires `rows`, and one that does not find it sets the whole document aside, so a stored shape must never
        /// lose a member an older copy requires. This version reads `shows` and ignores `rows` when both are there. A row
        /// whose word is another version's is written to `rows` as shown.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            let words = shows.mapValues(\.rawValue).merging(otherShows) { known, _ in known }
            if !words.isEmpty { try container.encode(words, forKey: DynamicKey("shows")) }
            let rows = shows.mapValues { $0 != .hidden }.merging(otherShows.mapValues { _ in true }) { known, _ in known }
            try container.encode(rows, forKey: DynamicKey("rows"))
            try container.encodeIfPresent(linkedFrom, forKey: DynamicKey("linkedFrom"))
            try container.encodeIfPresent(pins, forKey: DynamicKey("pins"))
            try container.encodeIfPresent(rowOrder, forKey: DynamicKey("rowOrder"))
            for (name, value) in others { try container.encode(value, forKey: DynamicKey(name)) }
        }
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

    /// Lists the rows in this order (each once), which the property block follows.
    mutating func setRowOrder(_ order: [String]?, of type: TypeID) {
        update(type) { $0.rowOrder = order.map(PagePlacement.unique) }
    }

    /// Chooses how a row shows on the type's pages.
    mutating func setShows(_ shows: RowShows, row: String, of type: TypeID) {
        update(type) {
            $0.shows[row] = shows
            $0.otherShows[row] = nil
        }
    }

    /// Chooses whether the page shows a row at all: showing a hidden row shows it when it has a value, and showing a
    /// row that shows already leaves it as it is. Linked From is either on the page or in the panel, so showing it
    /// moves it.
    mutating func set(_ shown: Bool, row: String, of type: TypeID, in catalogue: Catalogue) {
        if row == PagePlacement.linkedFrom {
            setLinkedFrom(shown ? .page : .inspector, of: type, in: catalogue)
        } else if !shown {
            setShows(.hidden, row: row, of: type)
        } else if placement(of: type, in: catalogue).shows(row) == .hidden {
            setShows(.whenSet, row: row, of: type)
        }
    }

    /// Moves `row` up (negative) or down by `offset` among `visible`, the rows the page lists in the order it lists them,
    /// and keeps that move in the type's order. Returns false at either end, or for a row not in `visible`.
    @discardableResult
    mutating func move(_ row: String, by offset: Int, in visible: [String], of type: TypeID) -> Bool {
        var order = PagePlacement.unique(visible)
        guard let from = order.firstIndex(of: row), order.indices.contains(from + offset) else { return false }
        order.swapAt(from, from + offset)
        moveRow(row, among: order, of: type)
        return true
    }

    /// Keeps a dragged row's new place: `order` is every row the page lists, folded ones too, in the order the drag
    /// left them, and the type's order takes exactly that for the rows it names. A saved row `order` does not name
    /// (a pinned row, or one this item lacks) keeps its place after the row that preceded it in the saved order, or
    /// first where none did, for the items that have it.
    mutating func setDraggedOrder(_ order: [String], of type: TypeID) {
        var merged = PagePlacement.unique(order)
        let named = Set(merged)
        let saved = choices[type.rawValue]?.rowOrder ?? []
        for (at, row) in saved.enumerated() where !named.contains(row) && !merged.contains(row) {
            if at > 0, let after = merged.firstIndex(of: saved[at - 1]) {
                merged.insert(row, at: after + 1)
            } else {
                merged.insert(row, at: 0)
            }
        }
        setRowOrder(merged, of: type)
    }

    /// Keeps the move of `row` in the type's order. `visible` is the rows the page lists, in the order they are in after
    /// the move: the row goes where it stands among them, and every other row, shown or not, keeps its saved place, so a
    /// pinned row or one this item lacks keeps its position for the items that have it. A row the saved order does not
    /// name takes the place the page lists it in, after the named ones.
    mutating func moveRow(_ row: String, among visible: [String], of type: TypeID) {
        let visible = PagePlacement.unique(visible)
        guard let at = visible.firstIndex(of: row) else { return }
        var order = PagePlacement.unique((choices[type.rawValue]?.rowOrder ?? []) + visible)
        order.removeAll { $0 == row }
        // After the row it now follows on the page, or, first of all, before the one it now precedes.
        if at > 0, let after = order.firstIndex(of: visible[at - 1]) {
            order.insert(row, at: after + 1)
        } else if at + 1 < visible.count, let before = order.firstIndex(of: visible[at + 1]) {
            order.insert(row, at: before)
        } else {
            order.append(row)
        }
        setRowOrder(order, of: type)
    }

    /// Chooses where Linked From goes. A place equal to the type's default is not kept, so the type follows its default
    /// again.
    mutating func setLinkedFrom(_ place: LinkedFromPlace, of type: TypeID, in catalogue: Catalogue) {
        let isDefault = place == placement(of: type, in: catalogue).defaultLinkedFromPlace
        update(type) { $0.linkedFrom = isDefault ? nil : place }
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
        // This write replaces every type's choices, so text it could not read is kept rather than lost.
        if let text = defaults.string(forKey: key), PagePlacements(rawValue: text) == nil {
            defaults.set((defaults.stringArray(forKey: setAsideKey) ?? []) + [text], forKey: setAsideKey)
        }
        var value = stored(in: defaults)
        change(&value)
        defaults.set(value.rawValue, forKey: key)
    }
}

/// How a row shows on a type's pages: when the item has a value for it (the default), always, even empty, or only
/// under Show More, greyed.
nonisolated enum RowShows: String, Codable, CaseIterable, Sendable {
    case whenSet, always, hidden
}

/// What the page shows of one type's items. A row is named by its identifier: a field's key, a relationship's field
/// (the parent's is `child-of`), `#tags`, `#location`, or `#linked` for Linked From.
nonisolated struct PagePlacement: Equatable, Sendable {
    /// The item's type, which the kicker's type name opens the panel for. It is not a row.
    static let type = "#type"
    /// An event's time, the one row an event's start, end, day and zone show in. It leads the rows, and a choice stored
    /// under this key hides it as any other row's does.
    static let when = "when"
    static let tags = "#tags"
    /// The Location row, which stands for an item's latitude and longitude, and its name for the place where it has one.
    static let location = "#location"
    static let linkedFrom = "#linked"
    /// The relationship a parent's sub-items are held in.
    static let subItems = RelationField.inversePrefix + MarfaMapping.parentEdge
    /// The relationship the links in other items' text are held in, which Referenced By lists.
    static let referencedBy = RelationField.inversePrefix + MarfaMapping.bodyLinkEdge
    /// The relationship the parent is held in.
    static let parent = "child-of"
    /// The most properties a page pins.
    static let pinLimit = 4

    /// The properties pinned under the title while pinned properties are on, in order (`pinLimit` at most, none twice):
    /// the person's choice, or with none the status and the parent. A default pin the person hid stays off.
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
        // links on the page. Every other item's links are for looking up, which the panel is for.
        let kind = PageHeaderKind.of(type, in: catalogue)
        let info = catalogue.itemTypes[type]
        let defaults: [String] = [info?.statusField?.key, Self.parent].compactMap { $0 }.filter { choice.shows[$0] != .hidden }
        let pins = choice.pins ?? defaults
        self.init(
            linkField: info?.linkField, choice: choice,
            defaultLinkedFrom: kind == .person || catalogue.isCollection(type) ? .page : .inspector,
            bookkeeping: Set((info?.fields ?? []).filter(Self.isBookkeeping).map(\.key)), pins: Self.limited(pins))
    }

    /// The first `pinLimit` of `rows`, each once.
    static func limited(_ rows: [String]) -> [String] {
        Array(unique(rows).prefix(pinLimit))
    }

    static func unique(_ rows: [String]) -> [String] {
        var seen: Set<String> = []
        return rows.filter { seen.insert($0).inserted }
    }

    /// `items` in the person's row order: those it names first, in its order, then the rest as they were.
    func ordered<Item>(_ items: [Item], id: (Item) -> String) -> [Item] {
        guard let order = choice.rowOrder, !order.isEmpty else { return items }
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let named = items.filter { position[id($0)] != nil }.sorted { position[id($0)]! < position[id($1)]! }
        return named + items.filter { position[id($0)] == nil }
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

    /// How `row` shows: the person's choice, or when it has a value, but for what only a connector's bookkeeping needs.
    func shows(_ row: String) -> RowShows { choice.shows[row] ?? (defaultShows(row) ? .whenSet : .hidden) }

    func showsOnPage(_ row: String) -> Bool { shows(row) != .hidden }

    var linkedFromPlace: LinkedFromPlace { choice.linkedFrom ?? defaultLinkedFrom }

    /// Where Linked From goes for this type when the person has chosen nothing.
    var defaultLinkedFromPlace: LinkedFromPlace { defaultLinkedFrom }

    /// Unless chosen, a row shows when it has a value, but for the type's connector link, a connector's bookkeeping and a
    /// parent's sub-items and Referenced By, which the foot lists.
    private func defaultShows(_ row: String) -> Bool {
        row != linkField && !bookkeeping.contains(row) && row != Self.subItems && row != Self.referencedBy
    }
}
