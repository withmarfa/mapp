import Foundation

/// What a window with nothing to restore shows first, as Settings > General > Opening says: the place the person last
/// used, or one they chose. A window restored with the app keeps what it showed. One value in the defaults (`key`),
/// which syncs through the Marfa (`PreferencesMap`); the place last used stays on this Mac.
///
/// Earlier copies kept both under keys of their own (`earlierKey`, `earlierLastPlaceKey`), which they still read, so
/// those are read in once (`EarlierPlace.readIn`) and never written.
nonisolated enum StartWith: Hashable, Sendable, RawRepresentable {
    case leftOff
    /// A place, and the item chosen in it, which only one favorite of an earlier copy names.
    case place(PlaceView, selecting: ItemID? = nil)

    static let key = "opening"
    /// The place the person last had a window in, which `leftOff` brings back.
    static let lastPlaceKey = "openingLastPlace"
    static let earlierKey = "startWith"
    static let earlierLastPlaceKey = "startLastPlace"
    static let standard = StartWith.leftOff

    private static let leftOffWord = "leftOff"
    private static let itemPrefix = "|item:"

    /// A stored value that is not a place reads as `leftOff`.
    init?(rawValue: String) {
        if rawValue == Self.leftOffWord {
            self = .leftOff
            return
        }
        var text = rawValue
        var item: ItemID?
        if let range = text.range(of: Self.itemPrefix), range.upperBound < text.endIndex {
            item = ItemID(String(text[range.upperBound...]))
            text = String(text[..<range.lowerBound])
        }
        guard let place = PlaceView(storageKey: text) else { return nil }
        self = .place(place, selecting: item)
    }

    /// What an earlier copy stored reads as the place that stands for it now (`EarlierPlace`); Files, which is no
    /// place now, reads as the Library.
    init?(earlier text: String) {
        if text == Self.leftOffWord {
            self = .leftOff
            return
        }
        switch EarlierPlace.read(key: text) {
        case .place(let place, let item)?: self = .place(place, selecting: item)
        case .files?: self = .place(.library)
        case nil: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .leftOff: Self.leftOffWord
        case .place(let place, nil): place.storageKey
        case .place(let place, let item?): place.storageKey + Self.itemPrefix + item.rawValue
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> StartWith {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// Remembers where a window is, for `leftOff`.
    static func remember(_ place: PlaceView, in defaults: UserDefaults = .standard) {
        defaults.set(place.storageKey, forKey: lastPlaceKey)
    }

    /// The place a window with nothing to restore opens in, with the item to choose there, or nil for the library's
    /// usual start.
    func start(in defaults: UserDefaults = .standard) -> (place: PlaceView, selecting: ItemID?)? {
        switch self {
        case .leftOff:
            guard case .place(let place, let item)? = defaults.string(forKey: Self.lastPlaceKey).flatMap(Self.init(rawValue:))
            else { return nil }
            return (place, item)
        case .place(let place, let item): return (place, item)
        }
    }

    /// Copies what an earlier copy kept to the new keys, where they hold nothing (`EarlierPlace.readIn`).
    static func readIn(in defaults: UserDefaults) {
        for (earlier, new) in [(earlierKey, key), (earlierLastPlaceKey, lastPlaceKey)] where defaults.string(forKey: new) == nil {
            if let start = defaults.string(forKey: earlier).flatMap(Self.init(earlier:)) { defaults.set(start.rawValue, forKey: new) }
        }
    }
}
