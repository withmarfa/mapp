import Foundation

/// What MAPP keeps on this Mac about each saved view, which Marfa does not keep: the layout it opens in, the
/// table's columns, whether the board hides empty groups, and what the gallery's cards show. One value in the defaults, by view identifier, never
/// written to Marfa. A view's name, query, sort and group are Marfa's (`ViewDraft`).
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

/// The table's columns for one view: which are shown and in what order, as the person arranged them.
nonisolated struct ViewColumns: Codable, Hashable, Sendable {
    /// The identifiers in the order the person gave. Empty follows the table's own order. A column not named
    /// follows those named.
    private(set) var order: [String] = []
    /// A column's choice where it differs from whether the column shows by default, so the same arrangement is the
    /// same value however it was reached.
    private(set) var shown: [String: Bool] = [:]

    init(order: [String] = [], shown: [String: Bool] = [:]) {
        self.order = order
        self.shown = shown
    }

    func isShown(_ column: ItemTableColumn) -> Bool {
        column.content == .title || (shown[column.id] ?? column.isShownByDefault)
    }

    /// Every column in the person's order, the name first. A stored identifier the columns no longer have is
    /// ignored, and a column the order does not name follows in the table's own order.
    func arranged(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        let name = columns.filter { $0.content == .title }
        let others = columns.filter { $0.content != .title }
        let byID = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var named: [ItemTableColumn] = []
        var seen = Set<String>()
        for id in order {
            if let column = byID[id], seen.insert(id).inserted { named.append(column) }
        }
        return name + named + others.filter { !seen.contains($0.id) }
    }

    /// The columns the table shows, in order.
    func shownColumns(_ columns: [ItemTableColumn]) -> [ItemTableColumn] {
        arranged(columns).filter(isShown)
    }

    mutating func setShown(_ column: ItemTableColumn, _ isShown: Bool) {
        guard column.content != .title else { return }
        shown[column.id] = isShown == column.isShownByDefault ? nil : isShown
    }

    /// Moves a column to sit before another, or last. The name stays first. The saved place of a column the table
    /// lacks is kept, since another place's table may have it again, so the move is spliced into the order.
    mutating func move(_ id: String, before other: String?, in columns: [ItemTableColumn]) {
        let own = columns.filter { $0.content != .title }.map(\.id)
        guard id != other, own.contains(id) else { return }
        var seen = Set<String>()
        var spliced = order.filter { seen.insert($0).inserted }
        spliced += own.filter { seen.insert($0).inserted }
        spliced.removeAll { $0 == id }
        spliced.insert(id, at: other.flatMap { spliced.firstIndex(of: $0) } ?? spliced.count)
        order = spliced == own ? [] : spliced
    }

    /// The columns as the table first lays them out.
    mutating func reset() {
        self = ViewColumns()
    }
}

/// One view's settings on this Mac.
nonisolated struct ViewMacSettings: Codable, Hashable, Sendable {
    /// The layout the view opens in. Nil follows the window.
    var layout: ItemViewMode?
    var columns = ViewColumns()
    /// Whether the board leaves out a group with no items. The table's groups are made from its rows, so none is empty.
    var hidesEmptyGroups = false
    /// What the gallery draws on each card.
    var cards = ViewCards()
    /// What the list's rows take of the view's own, where Settings otherwise decides.
    var rows = ViewRows()
    /// The table's column widths as the table keeps them (`TableColumnCustomization`), which the person's drag of a
    /// divider records at once and Save does not wait for. Opaque: SwiftUI exposes no way to read or write a
    /// width alone.
    var widths: Data?

    init(
        layout: ItemViewMode? = nil, columns: ViewColumns = ViewColumns(), hidesEmptyGroups: Bool = false,
        cards: ViewCards = ViewCards(), rows: ViewRows = ViewRows(), widths: Data? = nil
    ) {
        self.layout = layout
        self.columns = columns
        self.hidesEmptyGroups = hidesEmptyGroups
        self.cards = cards
        self.rows = rows
        self.widths = widths
    }

    /// A field this version does not know, or one a later version adds, never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try? container.decodeIfPresent(ItemViewMode.self, forKey: .layout)
        columns = (try? container.decodeIfPresent(ViewColumns.self, forKey: .columns)) ?? ViewColumns()
        hidesEmptyGroups = (try? container.decodeIfPresent(Bool.self, forKey: .hidesEmptyGroups)) ?? false
        cards = (try? container.decodeIfPresent(ViewCards.self, forKey: .cards)) ?? ViewCards()
        rows = (try? container.decodeIfPresent(ViewRows.self, forKey: .rows)) ?? ViewRows()
        widths = try? container.decodeIfPresent(Data.self, forKey: .widths)
    }

    /// Whether the choices a Save keeps are the same, leaving the widths out, which are kept as they are dragged.
    func sameChoices(as other: ViewMacSettings) -> Bool {
        layout == other.layout && columns == other.columns && hidesEmptyGroups == other.hidesEmptyGroups
            && cards == other.cards && rows == other.rows
    }

    /// Takes the choices of another and keeps its own widths.
    mutating func take(choicesOf other: ViewMacSettings) {
        layout = other.layout
        columns = other.columns
        hidesEmptyGroups = other.hidesEmptyGroups
        cards = other.cards
        rows = other.rows
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
