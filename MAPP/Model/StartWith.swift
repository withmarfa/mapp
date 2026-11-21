import Foundation

/// What a window with nothing to restore shows first, as Settings > General > Opening says: the place the person last
/// used, or one they chose. A window restored with the app keeps what it showed. A Mac setting, one value in the defaults
/// (`key`), never written to Marfa.
nonisolated enum StartWith: Hashable, Sendable, RawRepresentable {
    case leftOff
    case place(SidebarItem)

    static let key = "startWith"
    /// The place the person last had a window in, which `leftOff` brings back.
    static let lastPlaceKey = "startLastPlace"
    static let standard = StartWith.leftOff

    private static let leftOffWord = "leftOff"

    /// A stored value that is not a place reads as `leftOff`.
    init?(rawValue: String) {
        if rawValue == Self.leftOffWord {
            self = .leftOff
        } else if let place = Self.place(from: rawValue) {
            self = .place(place)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .leftOff: Self.leftOffWord
        case .place(let place): place.storageKey
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> StartWith {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// Remembers where a window is, for `leftOff`.
    static func remember(_ place: SidebarItem, in defaults: UserDefaults = .standard) {
        defaults.set(place.storageKey, forKey: lastPlaceKey)
    }

    /// The place a window with nothing to restore opens in, or nil for the library's usual start.
    func startingPlace(in defaults: UserDefaults = .standard) -> SidebarItem? {
        switch self {
        case .leftOff: defaults.string(forKey: Self.lastPlaceKey).flatMap(Self.place(from:))
        case .place(let place): place
        }
    }

    private static func place(from text: String) -> SidebarItem? {
        try? JSONDecoder().decode(SidebarItem.self, from: Data(text.utf8))
    }
}
