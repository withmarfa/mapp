import Foundation

/// The order of each place's views as the person arranged them, kept by the place's word (`Place.word`) as a list of
/// view words (`ViewChoice.word`): the place's own view, the Library's Favorites and its saved views. A view with no
/// stored position follows the placed ones, by title (`ItemLibrary.views(in:order:)`).
///
/// The views hidden from a place's row are a setting of their own, one entry for each place and view (`hiddenRowKey`),
/// so a reorder and a hide, or two hides of different views, made on two Macs never write over each other. Showing a
/// view again keeps its entry as shown rather than removing it: a Mac that holds no entry for a view has not read it,
/// so its absence is never taken as a change (`PreferencesMap.keptWhereAbsent`).
nonisolated struct ViewOrders: Equatable, Sendable {
    static let key = "viewOrders"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "viewOrdersSetAside"
    static let hiddenKey = "viewHidden"
    static let hiddenSetAsideKey = "viewHiddenSetAside"

    private(set) var places: [String: [String]] = [:]
    /// Whether each view is hidden from a place's row, by `hiddenRowKey`.
    private(set) var hiddenViews: [String: Bool] = [:]

    init(_ places: [String: [String]] = [:], hidden: [String: Bool] = [:]) {
        self.places = places
        hiddenViews = hidden
    }

    /// The views of `place` in the person's order. A word this copy does not know is left out here and kept stored.
    func order(in place: Place) -> [ViewChoice] {
        (places[place.word] ?? []).compactMap(ViewChoice.init(knownWord:))
    }

    /// The saved views of `place` in the person's order, for `ItemLibrary.views(in:order:)`.
    func savedOrder(in place: Place) -> [ItemID] {
        order(in: place).compactMap(\.savedView)
    }

    /// Keeps the positions of stored views this Mac has not read while reordering the views it holds.
    mutating func set(_ views: [ViewChoice], in place: Place) {
        var words = views.map(\.word)
        let given = Set(words)
        for (index, word) in (places[place.word] ?? []).enumerated() where !given.contains(word) {
            words.insert(word, at: min(index, words.count))
        }
        places[place.word] = words.isEmpty ? nil : words
    }

    /// `views` in the person's order: the placed ones first, then the rest as given, so a view made elsewhere after the
    /// person arranged the row comes last, and a view that is gone leaves no gap.
    func arranged(_ views: [ViewChoice], in place: Place) -> [ViewChoice] {
        let rank = Dictionary(order(in: place).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return views.enumerated().sorted { a, b in
            switch (rank[a.element], rank[b.element]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    // MARK: Hidden views

    /// The key of the entry that says whether `view` is hidden from the row of `place`: the two words as a JSON list.
    static func hiddenRowKey(_ view: ViewChoice, in place: Place) -> String {
        PreferenceJSON.text([place.word, view.word]) ?? ""
    }

    /// The views of `place` the person hid from the row.
    func hidden(in place: Place) -> Set<ViewChoice> {
        var views: Set<ViewChoice> = []
        for (key, isHidden) in hiddenViews where isHidden {
            guard let words = PreferenceJSON.value(key) as? [String], words.count == 2, words[0] == place.word,
                  let view = ViewChoice(knownWord: words[1]) else { continue }
            views.insert(view)
        }
        return views
    }

    /// Hides `view` from the row of `place`, or shows it again. Hiding never deletes the view. Only that view's entry
    /// changes, and one shown again stays as shown (see the type's comment).
    mutating func setHidden(_ view: ViewChoice, _ isHidden: Bool, in place: Place) {
        let key = Self.hiddenRowKey(view, in: place)
        guard isHidden || hiddenViews[key] != nil else { return }
        hiddenViews[key] = isHidden
    }

    // MARK: Keeping

    private static func load<Value>(_ key: String, as _: Value.Type, in defaults: UserDefaults) -> StoredMap<Value> {
        StoredMap(defaults, key: key) { $0 as? Value }
    }

    /// The stored orders and hidden views; data that cannot be read is none, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewOrders {
        ViewOrders(load(key, as: [String].self, in: defaults).readable, hidden: load(hiddenKey, as: Bool.self, in: defaults).readable)
    }

    /// Changes the stored orders and hidden views, writing only what changed. An entry this version cannot read stays as
    /// stored until the change sets it; stored data that is no map is set aside whole first (`StoredMap`).
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewOrders) -> Void) {
        let orders = load(key, as: [String].self, in: defaults)
        let hidden = load(hiddenKey, as: Bool.self, in: defaults)
        var value = ViewOrders(orders.readable, hidden: hidden.readable)
        change(&value)
        orders.save(value.places, encode: { $0 }, to: key, setAside: setAsideKey, in: defaults)
        hidden.save(value.hiddenViews, encode: { $0 }, to: hiddenKey, setAside: hiddenSetAsideKey, in: defaults)
    }
}
