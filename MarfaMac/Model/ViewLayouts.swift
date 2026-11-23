import Foundation

/// What MAPP keeps about each saved view that the view itself does not hold: the layout it opens in, its Properties,
/// whether the board hides empty groups, and what the gallery's cards show. One value in the defaults, by view identifier,
/// which syncs through the Marfa (`PreferencesMap`) without the table's widths, which stay on this Mac. A view's name, query, sort and group are Marfa's (`ViewDraft`).
nonisolated struct ViewLayouts: Equatable, Sendable {
    static let key = "viewLayouts"
    /// Each entry is stored text that could not be read, in the order it was found.
    static let setAsideKey = "viewLayoutsSetAside"

    private(set) var views: [String: ViewMacSettings] = [:]

    init(_ views: [String: ViewMacSettings] = [:]) {
        self.views = views
    }

    func settings(for id: ItemID) -> ViewMacSettings? {
        views[id.rawValue]
    }

    mutating func set(_ settings: ViewMacSettings, for id: ItemID) {
        views[id.rawValue] = settings
    }

    mutating func forget(_ id: ItemID) {
        views[id.rawValue] = nil
    }
}

/// One view's settings on this Mac.
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
        case layout, hidesEmptyGroups, cards, density, widths, calendarScale
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
    }

    /// Whether the choices a Save keeps are the same, leaving the widths out, which are kept as they are dragged.
    func sameChoices(as other: ViewMacSettings) -> Bool {
        layout == other.layout && properties == other.properties && hidesEmptyGroups == other.hidesEmptyGroups
            && cards == other.cards && density == other.density && calendarScale == other.calendarScale
    }

    /// Takes the choices of another and keeps its own widths.
    mutating func take(choicesOf other: ViewMacSettings) {
        layout = other.layout
        properties = other.properties
        hidesEmptyGroups = other.hidesEmptyGroups
        cards = other.cards
        density = other.density
        calendarScale = other.calendarScale
    }
}

/// The settings as `@AppStorage` keeps them: JSON, with sorted keys so the same settings are the same text.
nonisolated extension ViewLayouts: RawRepresentable {
    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(views)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init?(rawValue: String) {
        guard let views = try? JSONDecoder().decode([String: ViewMacSettings].self, from: Data(rawValue.utf8)) else { return nil }
        self.init(views)
    }
}

nonisolated extension ViewLayouts {
    /// The stored settings; text that cannot be read is no settings, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewLayouts {
        defaults.string(forKey: key).flatMap(ViewLayouts.init(rawValue:)) ?? ViewLayouts()
    }

    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewLayouts) -> Void) {
        // This write replaces every view's settings, so text it could not read is kept rather than lost.
        if let text = defaults.string(forKey: key), !text.isEmpty, ViewLayouts(rawValue: text) == nil {
            defaults.set((defaults.stringArray(forKey: setAsideKey) ?? []) + [text], forKey: setAsideKey)
        }
        var value = stored(in: defaults)
        change(&value)
        defaults.set(value.rawValue, forKey: key)
    }
}
