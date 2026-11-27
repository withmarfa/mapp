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

    /// The stored entries of `Value`, and the stored data that could not be read: the whole of it where it is not an
    /// object, otherwise an object of the entries that are not of `Value`.
    private static func read<Value>(_ data: Data, as _: Value.Type) -> (readable: [String: Value], unreadable: Data?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([:], data) }
        var readable: [String: Value] = [:]
        var unreadable: [String: Any] = [:]
        for (entry, value) in object {
            if let value = value as? Value { readable[entry] = value } else { unreadable[entry] = value }
        }
        let aside = unreadable.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)
        return (readable, aside)
    }

    /// The stored orders and hidden views; data that cannot be read is none, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewOrders {
        ViewOrders(
            defaults.data(forKey: key).map { read($0, as: [String].self).readable } ?? [:],
            hidden: defaults.data(forKey: hiddenKey).map { read($0, as: Bool.self).readable } ?? [:])
    }

    /// Changes the stored orders and hidden views, writing only the setting that changed. What a write would replace
    /// and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewOrders) -> Void) {
        var setAside: Set<String> = []
        func load<Value>(_ key: String, as type: Value.Type, setAside aside: String) -> [String: Value] {
            guard let saved = defaults.data(forKey: key) else { return [:] }
            let (readable, unreadable) = read(saved, as: type)
            if let unreadable {
                defaults.set((defaults.array(forKey: aside) as? [Data] ?? []) + [unreadable], forKey: aside)
                setAside.insert(key)
            }
            return readable
        }
        func save(_ entries: [String: Any], to key: String) {
            if entries.isEmpty {
                defaults.removeObject(forKey: key)
            } else if let data = try? JSONSerialization.data(withJSONObject: entries, options: .sortedKeys) {
                defaults.set(data, forKey: key)
            }
        }
        let before = ViewOrders(
            load(key, as: [String].self, setAside: setAsideKey), hidden: load(hiddenKey, as: Bool.self, setAside: hiddenSetAsideKey))
        var value = before
        change(&value)
        if value.places != before.places || setAside.contains(key) { save(value.places, to: key) }
        if value.hiddenViews != before.hiddenViews || setAside.contains(hiddenKey) { save(value.hiddenViews, to: hiddenKey) }
    }
}
