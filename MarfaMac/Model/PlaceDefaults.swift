import Foundation

/// What a person changed in a place's default view: the filters, sort and grouping, the layout, the timeline's date, the
/// board's card density, the gallery's cards, the calendar's scale and its Properties list. A place that is not a saved
/// view opens as they left it. The table's column widths and the density a place keeps are kept apart
/// (`ItemTableColumnLayouts`, `PlaceDensities`).
///
/// Every field is optional or empty by default, and an entry with nothing in it is not kept, so a place nobody changed
/// has no entry.
nonisolated struct PlaceDefault: Codable, Equatable, Sendable {
    struct SortKey: Codable, Equatable, Sendable {
        var column: String
        var reversed: Bool
    }

    /// Where the table groups: by a column, each value or a date's span, or not at all. Nil is the place's own grouping.
    /// Stored as `none`, `column:<id>` for each value, `<bucket>:<id>` (`week:field.due_at`) for a date's span,
    /// `presence:<id>` for Set or Not Set, or `groups:<id>` for a status's groups.
    enum Grouping: Encodable, Equatable, Sendable {
        case none
        case column(String, by: GroupMode = .value)

        private static let columnPrefix = "column:"

        /// The stored word, or nil for one this version does not know, which leaves the place's own grouping.
        init?(word: String) {
            if word == "none" {
                self = .none
                return
            }
            guard let colon = word.firstIndex(of: ":") else { return nil }
            let id = String(word[word.index(after: colon)...])
            let head = String(word[..<colon])
            guard !id.isEmpty else { return nil }
            if head == "column" {
                self = .column(id)
            } else if head == "presence" {
                self = .column(id, by: .presence)
            } else if head == "groups" {
                self = .column(id, by: .statusGroups)
            } else if let bucket = LibraryViewGroup.Bucket(rawValue: head) {
                self = .column(id, by: .bucket(bucket))
            } else {
                return nil
            }
        }

        var word: String {
            switch self {
            case .none: "none"
            case .column(let id, .value): Self.columnPrefix + id
            case .column(let id, .bucket(let bucket)): bucket.rawValue + ":" + id
            case .column(let id, .presence): "presence:" + id
            case .column(let id, .statusGroups): "groups:" + id
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(word)
        }
    }

    /// The layout the person chose for the place. Nil follows the window.
    var layout: ItemViewMode?
    var sort: [SortKey] = []
    var grouping: Grouping?
    /// The groups put first, in order, and those left out, by key (`GroupKey`).
    var groupOrder: [String] = []
    var hiddenGroups: [String] = []
    /// Whether a group with no items is left out.
    var hidesEmptyGroups = false
    /// The filter row's clauses, which may be relative to the day (a view keeps none of those), and whether any one will do.
    var filter: [FilterClause] = []
    var matchesAny = false
    /// The date field the timeline places its items on.
    var timelineField: String?
    var compactBoard = false
    var cards = ViewCards()
    var calendarScale: CalendarScale?
    /// What shows after the title in every layout; empty is the types' looks.
    var properties = ViewProperties()
    /// The tiers a type, a collection or a source lists (From), and the Favorites view; nil is the place's own.
    var scope: ListScope?
    /// Whether archived items are listed; nil hides them.
    var archived: ArchivedItems?
    /// Whether a type lists its kinds; nil lists them.
    var includesKinds: Bool?

    init() {}

    /// A field this version does not know is left out. A field that is there and cannot be read fails the entry, which
    /// `PlaceDefaults` keeps aside, so it is never taken for a choice and written back as one. A grouping word this version
    /// does not know is the place's own grouping.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decodeIfPresent(ItemViewMode.self, forKey: .layout)
        sort = try container.decodeIfPresent([SortKey].self, forKey: .sort) ?? []
        grouping = try container.decodeIfPresent(String.self, forKey: .grouping).flatMap(Grouping.init(word:))
        groupOrder = try container.decodeIfPresent([String].self, forKey: .groupOrder) ?? []
        hiddenGroups = try container.decodeIfPresent([String].self, forKey: .hiddenGroups) ?? []
        hidesEmptyGroups = try container.decodeIfPresent(Bool.self, forKey: .hidesEmptyGroups) ?? false
        filter = try container.decodeIfPresent([FilterClause].self, forKey: .filter) ?? []
        matchesAny = try container.decodeIfPresent(Bool.self, forKey: .matchesAny) ?? false
        timelineField = try container.decodeIfPresent(String.self, forKey: .timelineField)
        compactBoard = try container.decodeIfPresent(Bool.self, forKey: .compactBoard) ?? false
        cards = try container.decodeIfPresent(ViewCards.self, forKey: .cards) ?? ViewCards()
        calendarScale = try container.decodeIfPresent(CalendarScale.self, forKey: .calendarScale)
        properties = try container.decodeIfPresent(ViewProperties.self, forKey: .properties) ?? ViewProperties()
        // A word this version does not know is the place's own choice.
        scope = try container.decodeIfPresent(String.self, forKey: .scope).flatMap(ListScope.init(rawValue:))
        archived = try container.decodeIfPresent(String.self, forKey: .archived).flatMap(ArchivedItems.init(rawValue:))
        includesKinds = try container.decodeIfPresent(Bool.self, forKey: .includesKinds)
    }

    var isEmpty: Bool { self == PlaceDefault() }

    /// This default with what it leaves unset taken from `other`. The grouping and its groups go together, as do the
    /// filters and whether any one will do.
    func filled(from other: PlaceDefault) -> PlaceDefault {
        var filled = self
        filled.layout = layout ?? other.layout
        if sort.isEmpty { filled.sort = other.sort }
        if grouping == nil, groupOrder.isEmpty, hiddenGroups.isEmpty {
            (filled.grouping, filled.groupOrder, filled.hiddenGroups) = (other.grouping, other.groupOrder, other.hiddenGroups)
        }
        if !hidesEmptyGroups { filled.hidesEmptyGroups = other.hidesEmptyGroups }
        if filter.isEmpty, !matchesAny { (filled.filter, filled.matchesAny) = (other.filter, other.matchesAny) }
        filled.timelineField = timelineField ?? other.timelineField
        if !compactBoard { filled.compactBoard = other.compactBoard }
        if cards == ViewCards() { filled.cards = other.cards }
        filled.calendarScale = calendarScale ?? other.calendarScale
        if properties == ViewProperties() { filled.properties = other.properties }
        filled.scope = scope ?? other.scope
        filled.archived = archived ?? other.archived
        filled.includesKinds = includesKinds ?? other.includesKinds
        return filled
    }

    /// Whether the person changed something the place would not show by itself: a layout that is the place's own does not
    /// count, since choosing it leaves the place as it was.
    func isChanged(naturalLayout: ItemViewMode) -> Bool {
        var changed = self
        if changed.layout == naturalLayout { changed.layout = nil }
        return !changed.isEmpty
    }

    // MARK: Filters, sort and grouping

    /// Keeps the filters, sort and grouping of the options, which are what a view would hold of them.
    mutating func keep(_ options: ItemTableOptions?) {
        let options = (options ?? ItemTableOptions()).settled
        sort = (options.sort ?? []).map { SortKey(column: $0.column.id, reversed: $0.order == .reverse) }
        let held: Grouping? = switch options.grouping {
        case .automatic: nil
        case .none: Grouping.none
        case .column(let id, let mode): Grouping.column(id, by: mode)
        }
        grouping = held
        groupOrder = options.groupOrder ?? []
        hiddenGroups = (options.hiddenGroups ?? []).sorted()
        filter = options.filter.complete.clauses
        matchesAny = options.filter.complete.matchesAny
        scope = options.scope
        archived = options.archived
        includesKinds = options.includesKinds
    }

    /// The options a place opens with: those the window holds, with the filters, sort and grouping this keeps. A column
    /// of a field no type of the place declares any more is dropped, with its condition, and the rest stays.
    func options(replacing held: ItemTableOptions?, in place: PlaceView, catalogue: Catalogue) -> ItemTableOptions {
        var options = held ?? ItemTableOptions()
        let declared = Self.declaredFields(in: place, catalogue: catalogue)
        func isKept(_ column: String) -> Bool {
            guard column.hasPrefix(Browser.fieldColumnPrefix) else { return true }
            return declared.contains(String(column.dropFirst(Browser.fieldColumnPrefix.count)))
        }
        let sort = sort.filter { isKept($0.column) }
            .map { ItemTableComparator(column: ViewDraft.placeholder($0.column), order: $0.reversed ? .reverse : .forward) }
        options.sort = sort.isEmpty ? nil : sort
        let grouping: ItemTableOptions.Grouping = switch self.grouping {
        case nil: .automatic
        case .none?: .none
        case .column(let id, let mode)?: isKept(id) ? .column(id, by: mode) : .automatic
        }
        if options.grouping != grouping { options.collapsed = nil }
        options.grouping = grouping
        let keepsGroups = grouping != .automatic
        options.groupOrder = keepsGroups && !groupOrder.isEmpty ? groupOrder : nil
        options.hiddenGroups = keepsGroups && !hiddenGroups.isEmpty ? Set(hiddenGroups) : nil
        options.filter = FilterState(clauses: filter.filter { isKept($0.field) }, matchesAny: matchesAny).complete
        options.scope = scope
        options.archived = archived
        options.includesKinds = includesKinds
        return options
    }

    /// The fields the types a place lists declare: its own type and the types below it for a type's place, and every type
    /// for any other, which lists items of many.
    private static func declaredFields(in place: PlaceView, catalogue: Catalogue) -> Set<String> {
        var types = Array(catalogue.itemTypes.values)
        if case .type(let id) = place.place {
            let wanted = catalogue.descendants(of: id).union([id])
            types = types.filter { wanted.contains($0.id) }
        }
        return Set(types.flatMap { $0.fields.map(\.key) })
    }
}

/// The default view each place that is not a saved view keeps for itself: one value in the defaults, by place, which syncs
/// through the Marfa (`PreferencesMap`) as a row of the app's own settings, since no record of Marfa models a place's default. A place's default cannot be renamed or
/// deleted; Reset View empties it.
///
/// Stored text that cannot be read, or one entry that cannot, is moved aside under a key of its own, kept and never
/// removed; the other places' entries go on working.
nonisolated struct PlaceDefaults: Equatable, Sendable {
    static let key = "placeDefaults"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "placeDefaultsSetAside"

    private(set) var places: [String: PlaceDefault] = [:]

    init(_ places: [String: PlaceDefault] = [:]) {
        self.places = places
    }

    func `default`(for place: PlaceView) -> PlaceDefault? {
        places[place.storageKey]
    }

    mutating func set(_ value: PlaceDefault?, for place: PlaceView) {
        places[place.storageKey] = value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The places that have an entry. A key that names no place this version knows is left out, so it is never judged.
    var keptPlaces: [PlaceView] {
        places.keys.compactMap(PlaceView.init(storageKey:))
    }

    // MARK: Keeping

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// The stored defaults, and the stored data that could not be read: the whole of it where it is not an object of
    /// places, otherwise an object of the entries that could not be read, so one bad entry leaves the other places' alone.
    private static func read(_ data: Data) -> (readable: PlaceDefaults, unreadable: Data?) {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (PlaceDefaults(), data) }
        var readable: [String: PlaceDefault] = [:]
        var unreadable: [String: Any] = [:]
        for (place, entry) in entries {
            guard JSONSerialization.isValidJSONObject(entry),
                  let raw = try? JSONSerialization.data(withJSONObject: entry),
                  let value = try? JSONDecoder().decode(PlaceDefault.self, from: raw)
            else {
                unreadable[place] = entry
                continue
            }
            readable[place] = value
        }
        let aside = unreadable.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)
        return (PlaceDefaults(readable), aside)
    }

    /// The stored defaults; data that cannot be read is no defaults, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> PlaceDefaults {
        defaults.data(forKey: key).map { read($0).readable } ?? PlaceDefaults()
    }

    /// Changes the stored defaults. What this write would replace and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout PlaceDefaults) -> Void) {
        var value = PlaceDefaults()
        if let saved = defaults.data(forKey: key) {
            let (readable, unreadable) = read(saved)
            value = readable
            if let unreadable { defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [unreadable], forKey: setAsideKey) }
        }
        change(&value)
        if value.places.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? encode(value.places) {
            defaults.set(data, forKey: key)
        }
    }
}
