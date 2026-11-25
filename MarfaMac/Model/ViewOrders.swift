import Foundation

/// The order of each place's views as the person arranged them, and the views they hid from its row, kept by the place's
/// word (`Place.word`) as lists of view words (`ViewChoice.word`): the place's own view, the Library's Favorites and its
/// saved views. The order and the hidden views are two settings, so each is its own row in Marfa's settings: a reorder
/// on one Mac and a hide on another never write over each other. A view with no stored position follows the placed
/// ones, by title (`ItemLibrary.views(in:order:)`).
nonisolated struct ViewOrders: Equatable, Sendable {
    static let key = "viewOrders"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "viewOrdersSetAside"
    static let hiddenKey = "viewHidden"
    static let hiddenSetAsideKey = "viewHiddenSetAside"

    private(set) var places: [String: [String]] = [:]
    /// The views hidden from each place's row.
    private(set) var hiddenPlaces: [String: [String]] = [:]

    init(_ places: [String: [String]] = [:], hidden: [String: [String]] = [:]) {
        self.places = places
        hiddenPlaces = hidden
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

    /// The views of `place` the person hid from the row.
    func hidden(in place: Place) -> Set<ViewChoice> {
        Set((hiddenPlaces[place.word] ?? []).compactMap(ViewChoice.init(knownWord:)))
    }

    /// Hides `view` from the row of `place`, or shows it again. Hiding never deletes the view.
    mutating func setHidden(_ view: ViewChoice, _ isHidden: Bool, in place: Place) {
        var words = hiddenPlaces[place.word] ?? []
        words.removeAll { $0 == view.word }
        if isHidden { words.append(view.word) }
        hiddenPlaces[place.word] = words.isEmpty ? nil : words
    }

    // MARK: Keeping

    /// The stored lists, and the stored data that could not be read: the whole of it where it is not an object,
    /// otherwise an object of the entries that are not lists of words.
    private static func read(_ data: Data) -> (readable: [String: [String]], unreadable: Data?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([:], data) }
        var readable: [String: [String]] = [:]
        var unreadable: [String: Any] = [:]
        for (place, value) in object {
            if let words = value as? [String] { readable[place] = words } else { unreadable[place] = value }
        }
        let aside = unreadable.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)
        return (readable, aside)
    }

    /// The stored orders and hidden views; data that cannot be read is none, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewOrders {
        ViewOrders(
            defaults.data(forKey: key).map { read($0).readable } ?? [:],
            hidden: defaults.data(forKey: hiddenKey).map { read($0).readable } ?? [:])
    }

    /// Changes the stored orders and hidden views, writing only the setting that changed. What a write would replace
    /// and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewOrders) -> Void) {
        var setAside: Set<String> = []
        func load(_ key: String, setAside aside: String) -> [String: [String]] {
            guard let saved = defaults.data(forKey: key) else { return [:] }
            let (readable, unreadable) = read(saved)
            if let unreadable {
                defaults.set((defaults.array(forKey: aside) as? [Data] ?? []) + [unreadable], forKey: aside)
                setAside.insert(key)
            }
            return readable
        }
        func save(_ lists: [String: [String]], to key: String) {
            if lists.isEmpty {
                defaults.removeObject(forKey: key)
            } else if let data = try? JSONSerialization.data(withJSONObject: lists, options: .sortedKeys) {
                defaults.set(data, forKey: key)
            }
        }
        let before = ViewOrders(load(key, setAside: setAsideKey), hidden: load(hiddenKey, setAside: hiddenSetAsideKey))
        var value = before
        change(&value)
        if value.places != before.places || setAside.contains(key) { save(value.places, to: key) }
        if value.hiddenPlaces != before.hiddenPlaces || setAside.contains(hiddenKey) { save(value.hiddenPlaces, to: hiddenKey) }
    }
}
