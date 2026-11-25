import Foundation

/// The order of each place's views as the person arranged them, kept by the place's word (`Place.word`) as a list of
/// view words (`ViewChoice.word`): the place's own view, the Library's Favorites and its saved views, and the views the
/// person hid from the row. A view with no stored position follows the placed ones, by title (`ItemLibrary.views(in:order:)`).
nonisolated struct ViewOrders: Equatable, Sendable {
    static let key = "viewOrders"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "viewOrdersSetAside"

    private(set) var places: [String: [String]] = [:]

    init(_ places: [String: [String]] = [:]) {
        self.places = places
    }

    /// The views of `place` in the person's order. A word this copy does not know is left out here and kept stored.
    func order(in place: Place) -> [ViewChoice] {
        (places[place.word] ?? []).compactMap(ViewChoice.init(knownWord:))
    }

    /// The saved views of `place` in the person's order, for `ItemLibrary.views(in:order:)`.
    func savedOrder(in place: Place) -> [ItemID] {
        order(in: place).compactMap(\.savedView)
    }

    /// Keeps `views` as the order of `place`; an empty list forgets it. A word a later copy wrote stays at its position.
    mutating func set(_ views: [ViewChoice], in place: Place) {
        var words = views.map(\.word)
        for (index, word) in (places[place.word] ?? []).enumerated() where ViewChoice(knownWord: word) == nil {
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

    /// A hidden view is kept in its place's list as this prefix and its word, which an earlier copy does not know and
    /// so leaves alone.
    private static let hiddenPrefix = "hidden:"

    /// The views of `place` the person hid from the row.
    func hidden(in place: Place) -> Set<ViewChoice> {
        Set((places[place.word] ?? []).compactMap { word in
            word.hasPrefix(Self.hiddenPrefix) ? ViewChoice(knownWord: String(word.dropFirst(Self.hiddenPrefix.count))) : nil
        })
    }

    /// Hides `view` from the row of `place`, or shows it again. Hiding never deletes the view.
    mutating func setHidden(_ view: ViewChoice, _ isHidden: Bool, in place: Place) {
        let word = Self.hiddenPrefix + view.word
        var words = places[place.word] ?? []
        words.removeAll { $0 == word }
        if isHidden { words.append(word) }
        places[place.word] = words.isEmpty ? nil : words
    }

    // MARK: Keeping

    /// The stored orders, and the stored data that could not be read: the whole of it where it is not an object,
    /// otherwise an object of the entries that are not lists of words.
    private static func read(_ data: Data) -> (readable: ViewOrders, unreadable: Data?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (ViewOrders(), data) }
        var readable: [String: [String]] = [:]
        var unreadable: [String: Any] = [:]
        for (place, value) in object {
            if let words = value as? [String] { readable[place] = words } else { unreadable[place] = value }
        }
        let aside = unreadable.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)
        return (ViewOrders(readable), aside)
    }

    /// The stored orders; data that cannot be read is no orders, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> ViewOrders {
        defaults.data(forKey: key).map { read($0).readable } ?? ViewOrders()
    }

    /// Changes the stored orders. What this write would replace and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ViewOrders) -> Void) {
        var value = ViewOrders()
        if let saved = defaults.data(forKey: key) {
            let (readable, unreadable) = read(saved)
            value = readable
            if let unreadable { defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [unreadable], forKey: setAsideKey) }
        }
        change(&value)
        if value.places.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONSerialization.data(withJSONObject: value.places, options: .sortedKeys) {
            defaults.set(data, forKey: key)
        }
    }
}
