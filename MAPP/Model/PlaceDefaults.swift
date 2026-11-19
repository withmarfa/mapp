import Foundation

/// What a person changed in a place's default view: the filters, sort and grouping, the layout, the timeline's date, the
/// board's card density, the gallery's cards and the calendar's scale. A place that is not a saved view opens as they
/// left it. The columns and the density a place keeps are kept apart (`ItemTableColumnLayouts`, `PlaceDensities`).
///
/// Every field is optional or empty by default, and an entry with nothing in it is not kept, so a place nobody changed
/// has no entry.
nonisolated struct PlaceDefault: Codable, Equatable, Sendable {
    struct SortKey: Codable, Equatable, Sendable {
        var column: String
        var reversed: Bool
    }

    /// Where the table groups: by a column, or not at all. Nil is the place's own grouping.
    enum Grouping: Codable, Equatable, Sendable {
        case none
        case column(String)

        private static let columnPrefix = "column:"

        init(from decoder: any Decoder) throws {
            let word = try decoder.singleValueContainer().decode(String.self)
            if word.hasPrefix(Self.columnPrefix) {
                self = .column(String(word.dropFirst(Self.columnPrefix.count)))
            } else {
                self = .none
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none: try container.encode("none")
            case .column(let id): try container.encode(Self.columnPrefix + id)
            }
        }
    }

    /// The layout the person chose for the place. Nil follows the window.
    var layout: ItemViewMode?
    var sort: [SortKey] = []
    var grouping: Grouping?
    var filters: [String: [String]] = [:]
    var negated: [String] = []
    /// The date field the timeline places its items on.
    var timelineField: String?
    var compactBoard = false
    var cards = ViewCards()
    var calendarScale: CalendarScale?

    init() {}

    /// A field this version does not know, or one a later version adds, never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try? container.decodeIfPresent(ItemViewMode.self, forKey: .layout)
        sort = (try? container.decodeIfPresent([SortKey].self, forKey: .sort)) ?? []
        grouping = try? container.decodeIfPresent(Grouping.self, forKey: .grouping)
        filters = (try? container.decodeIfPresent([String: [String]].self, forKey: .filters)) ?? [:]
        negated = (try? container.decodeIfPresent([String].self, forKey: .negated)) ?? []
        timelineField = try? container.decodeIfPresent(String.self, forKey: .timelineField)
        compactBoard = (try? container.decodeIfPresent(Bool.self, forKey: .compactBoard)) ?? false
        cards = (try? container.decodeIfPresent(ViewCards.self, forKey: .cards)) ?? ViewCards()
        calendarScale = try? container.decodeIfPresent(CalendarScale.self, forKey: .calendarScale)
    }

    var isEmpty: Bool { self == PlaceDefault() }

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
        case .column(let id): Grouping.column(id)
        }
        grouping = held
        let kept = options.filters.filter { !$0.value.isEmpty }
        filters = kept.mapValues { $0.sorted() }
        negated = options.negated.filter { kept[$0] != nil }.sorted()
    }

    /// The options a place opens with: those the window holds, with the filters, sort and grouping this keeps. A column
    /// of a field no type of the place declares any more is dropped, with its condition, and the rest stays.
    func options(replacing held: ItemTableOptions?, in place: SidebarItem, catalogue: Catalogue) -> ItemTableOptions {
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
        case .column(let id)?: isKept(id) ? .column(id) : .automatic
        }
        if options.grouping != grouping { options.collapsed = nil }
        options.grouping = grouping
        let filters = filters.filter { isKept($0.key) && !$0.value.isEmpty }
        options.filters = filters.mapValues(Set.init)
        options.negated = Set(negated.filter { filters[$0] != nil })
        return options
    }

    /// The fields the types a place lists declare: its own type and the types below it for a type's place, and every type
    /// for any other, which lists items of many.
    private static func declaredFields(in place: SidebarItem, catalogue: Catalogue) -> Set<String> {
        var types = Array(catalogue.itemTypes.values)
        if case .itemType(let id) = place {
            let wanted = catalogue.descendants(of: TypeID(id)).union([TypeID(id)])
            types = types.filter { wanted.contains($0.id) }
        }
        return Set(types.flatMap { $0.fields.map(\.key) })
    }
}

/// The default view each place that is not a saved view keeps for itself on this Mac: one value in the defaults, by place,
/// never written to Marfa, since no record of Marfa models a place's default. A place's default cannot be renamed or
/// deleted; Reset View empties it.
///
/// Stored text that cannot be read is moved aside under a key of its own, kept and never removed.
nonisolated struct PlaceDefaults: Equatable, Sendable {
    static let key = "placeDefaults"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "placeDefaultsSetAside"

    private(set) var places: [String: PlaceDefault] = [:]

    init(_ places: [String: PlaceDefault] = [:]) {
        self.places = places
    }

    func `default`(for place: SidebarItem) -> PlaceDefault? {
        places[place.storageKey]
    }

    mutating func set(_ value: PlaceDefault?, for place: SidebarItem) {
        places[place.storageKey] = value.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Keeping

    private static func encode(_ places: [String: PlaceDefault]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(places)
    }

    /// The stored defaults; data that cannot be read is no defaults, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> PlaceDefaults {
        guard let data = defaults.data(forKey: key), let places = try? JSONDecoder().decode([String: PlaceDefault].self, from: data) else {
            return PlaceDefaults()
        }
        return PlaceDefaults(places)
    }

    /// Changes the stored defaults. What this write would replace and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout PlaceDefaults) -> Void) {
        if let saved = defaults.data(forKey: key), (try? JSONDecoder().decode([String: PlaceDefault].self, from: saved)) == nil {
            defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [saved], forKey: setAsideKey)
        }
        var value = stored(in: defaults)
        change(&value)
        if value.places.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = encode(value.places) {
            defaults.set(data, forKey: key)
        }
    }
}
