import Foundation
import Marfa

/// What the app keeps about each saved view that the view itself does not hold: the layout it opens in, its Properties,
/// whether the board hides empty groups, and what the gallery's cards show. One value in the defaults, by view identifier,
/// which syncs through the Marfa (`PreferencesMap`) without the table's widths, which stay on this Mac. A view's name, query, sort and group are Marfa's (`ViewDraft`).
nonisolated struct ViewLayouts: Equatable, Sendable {
    static let key = "viewLayouts"
    /// Each entry is stored text that could not be read, in the order it was found.
    static let setAsideKey = "viewLayoutsSetAside"

    private(set) var views: [String: ViewMacSettings] = [:]
    /// The views whose stored settings this version cannot read, as stored, so a write keeps them.
    private(set) var unread: [String: StoredJSON] = [:]

    init(_ views: [String: ViewMacSettings] = [:]) {
        self.views = views
    }

    func settings(for id: ItemID) -> ViewMacSettings? {
        views[id.rawValue]
    }

    mutating func set(_ settings: ViewMacSettings, for id: ItemID) {
        views[id.rawValue] = settings
        unread[id.rawValue] = nil
    }

    mutating func forget(_ id: ItemID) {
        views[id.rawValue] = nil
        unread[id.rawValue] = nil
    }
}

/// One view's settings in this app, which sync but for the table's widths. A new member needs only its `CodingKeys` case
/// and its line in `init(from:)`: comparing, Undo, Revert View and Create View's copy take every member.
nonisolated struct ViewMacSettings: Codable, Hashable, Sendable {
    /// The layout the view opens in. Nil follows the window.
    var layout: ItemViewMode?
    var properties = ViewProperties()
    /// Whether the board leaves out a group with no items. The table's groups are made from its rows, so none is empty.
    var hidesEmptyGroups = false
    /// What the gallery draws on each card.
    var cards = ViewCards()
    /// How much each row of the list says. Nil follows Settings.
    var density: Density?
    /// The table's column widths as the table keeps them (`TableColumnCustomization`), which the person's drag of a
    /// divider records at once and Save does not wait for. Opaque: SwiftUI exposes no way to read or write a
    /// width alone.
    var widths: Data?
    /// Whether the calendar shows a week or a month. Nil is a week.
    var calendarScale: CalendarScale?
    /// Whether the list offers its quick actions. Nil follows `showsQuickActions(_:in:scope:)`.
    var quickActions: Bool?
    /// Where the view opens its items. Nil follows Settings.
    var opening: ItemOpening?
    /// The map's Style and whether it groups markers that crowd. Nil follows the defaults.
    var map: MapChoices?
    var digest: DigestChoices?

    init(
        layout: ItemViewMode? = nil, properties: ViewProperties = ViewProperties(), hidesEmptyGroups: Bool = false,
        cards: ViewCards = ViewCards(), density: Density? = nil, widths: Data? = nil,
        calendarScale: CalendarScale? = nil
    ) {
        self.layout = layout
        self.properties = properties
        self.hidesEmptyGroups = hidesEmptyGroups
        self.cards = cards
        self.density = density
        self.widths = widths
        self.calendarScale = calendarScale
    }

    /// The Properties list is stored under the key the table's columns used, so a view's choices carry over.
    private enum CodingKeys: String, CodingKey {
        case layout, hidesEmptyGroups, cards, density, widths, calendarScale, quickActions, opening, map, digest
        case properties = "columns"
    }

    /// A field this version does not know, or one a later version adds, never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try? container.decodeIfPresent(ItemViewMode.self, forKey: .layout)
        properties = (try? container.decodeIfPresent(ViewProperties.self, forKey: .properties)) ?? ViewProperties()
        hidesEmptyGroups = (try? container.decodeIfPresent(Bool.self, forKey: .hidesEmptyGroups)) ?? false
        cards = (try? container.decodeIfPresent(ViewCards.self, forKey: .cards)) ?? ViewCards()
        density = try? container.decodeIfPresent(Density.self, forKey: .density)
        widths = try? container.decodeIfPresent(Data.self, forKey: .widths)
        calendarScale = try? container.decodeIfPresent(CalendarScale.self, forKey: .calendarScale)
        quickActions = try? container.decodeIfPresent(Bool.self, forKey: .quickActions)
        opening = try? container.decodeIfPresent(ItemOpening.self, forKey: .opening)
        map = try? container.decodeIfPresent(MapChoices.self, forKey: .map)
        digest = try? container.decodeIfPresent(DigestChoices.self, forKey: .digest)
    }

    /// Whether a list offers its quick actions: as the person chose, else only at the Feed, the Archive and in a view
    /// whose From is the Feed, where items wait to be dealt with.
    static func showsQuickActions(_ chosen: Bool?, in shown: PlaceView, scope: ListScope) -> Bool {
        chosen ?? (shown.savedView == nil ? shown == .feed || shown == .archive : scope == .feed)
    }

    /// Whether the choices are the same, leaving the widths out, which are kept as they are dragged. Every other member
    /// counts, through the synthesized `==`, so a member added later needs no list here.
    func sameChoices(as other: ViewMacSettings) -> Bool {
        var mine = self, theirs = other
        mine.widths = nil
        theirs.widths = nil
        return mine == theirs
    }

    /// A path from the top of the stored settings to one value that is not an object, such as `["cards", "size"]`.
    typealias Path = [String]

    /// Each value as stored, by its path, at any depth. A member that is not set has no entry.
    var leaves: [Path: JSONValue] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        var leaves: [Path: JSONValue] = [:]
        func collect(_ value: JSONValue, at path: Path) {
            if case .object(let object) = value, !object.members.isEmpty {
                for member in object.members { collect(member.value, at: path + [member.key]) }
            } else if value != .null {
                leaves[path] = value
            }
        }
        collect(value, at: [])
        return leaves
    }

    /// The settings these leaves store, or nil where they do not decode.
    init?(leaves: [Path: JSONValue]) {
        func build(_ leaves: [Path: JSONValue]) -> JSONValue {
            // An empty object below which another Mac has since set a value is that object, not the empty one.
            if let whole = leaves[[]], leaves.count == 1 { return whole }
            let keys = Set(leaves.keys.compactMap(\.first)).sorted()
            return .object(JSONObject(members: keys.map { key in
                let below = leaves.reduce(into: [Path: JSONValue]()) { below, leaf in
                    if leaf.key.first == key { below[Array(leaf.key.dropFirst())] = leaf.value }
                }
                return JSONMember(key: key, value: build(below))
            }))
        }
        guard let data = try? JSONEncoder().encode(build(leaves)), let settings = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = settings
    }

    /// Puts back, at any depth, only the values that differ between the step's `before` and `after`, so a value another
    /// Mac changed meanwhile, even beside one of the step's in the same member, stays.
    mutating func undo(_ step: (before: ViewMacSettings, after: ViewMacSettings)) {
        let before = step.before.leaves, after = step.after.leaves
        var now = leaves
        for path in Set(before.keys).union(after.keys) where before[path] != after[path] { now[path] = before[path] }
        if let undone = Self(leaves: now) { self = undone }
    }
}

/// The settings as `@AppStorage` keeps them: JSON, with sorted keys so the same settings are the same text.
nonisolated extension ViewLayouts: RawRepresentable {
    var rawValue: String {
        StoredEntries.encode(views, keeping: unread).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init?(rawValue: String) {
        guard let (views, unread) = StoredEntries.decode(Data(rawValue.utf8), as: ViewMacSettings.self) else { return nil }
        self.init(views)
        self.unread = unread
    }
}

nonisolated extension ViewLayouts {
    /// The stored settings; text that cannot be read is no settings, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewLayouts {
        StoredBytes.text(defaults, key).flatMap(ViewLayouts.init(rawValue:)) ?? ViewLayouts()
    }

    /// Changes the stored settings. A view's settings this version cannot read stay as stored until the change replaces
    /// them, and are set aside first; stored text that is no object of views is set aside whole.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewLayouts) -> Void) {
        let whole = StoredBytes.text(defaults, key).flatMap { !$0.isEmpty && ViewLayouts(rawValue: $0) == nil ? $0 : nil }
        var value = stored(in: defaults)
        let unread = value.unread
        change(&value)
        let replaced = unread.filter { value.unread[$0.key] == nil }.sorted { $0.key < $1.key }
        for (name, entry) in replaced { StoredBytes.setAside(StoredJSON.object([name: entry]).text, under: setAsideKey, in: defaults) }
        if defaults.object(forKey: key) as? String != value.rawValue { defaults.set(value.rawValue, forKey: key) }
        if let whole {
            PreferenceHolds.setAside(
                whole, under: setAsideKey, of: key, keys: nil, kept: Array(value.views.keys),
                in: defaults)
        }
    }
}
