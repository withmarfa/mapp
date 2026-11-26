import Foundation

/// Where each audio or video item was last left, in seconds, newest first. It stays on this Mac
/// (`PreferencesMap.staysOnMac`): a place changes with every pause, and another Mac's copy of the file is a different
/// listening. Only the newest `limit` are kept.
nonisolated enum PlaybackPlaces {
    struct Entry: Codable, Equatable {
        let item: ItemID
        let seconds: Double
    }

    static let key = "playbackPlaces"
    /// Stored data that could not be read, kept and never removed, in the order it was found.
    static let setAsideKey = "playbackPlacesSetAside"
    static let limit = 200

    /// The place kept for `item`, or nil where none is.
    static func place(of item: ItemID, in defaults: UserDefaults = .standard) -> Double? {
        entries(in: defaults).first { $0.item == item }?.seconds
    }

    /// Keeps `seconds` as the place of `item`. The very start keeps nothing, and a place that is not a time is not kept.
    static func keep(_ seconds: Double, of item: ItemID, in defaults: UserDefaults = .standard) {
        guard seconds.isFinite else { return }
        var all = entries(in: defaults).filter { $0.item != item }
        if seconds >= 1 { all.insert(Entry(item: item, seconds: seconds), at: 0) }
        if let data = try? JSONEncoder().encode(Array(all.prefix(limit))) { defaults.set(data, forKey: key) }
    }

    /// Where an item opens: its kept place, or the start where there is none or the place is not inside the file, as
    /// when the file was replaced by a shorter one.
    static func opening(kept: Double?, duration: Double) -> Double {
        guard let kept, kept.isFinite, kept > 0, duration.isFinite, kept < duration else { return 0 }
        return kept
    }

    private static func entries(in defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let all = try? JSONDecoder().decode([Entry].self, from: data) { return all }
        defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [data], forKey: setAsideKey)
        defaults.removeObject(forKey: key)
        return []
    }
}

/// How a time and a speed are written on the playback bar.
nonisolated enum PlaybackClock {
    /// Minutes and seconds, and hours where the time has them: "0:42", "3:18", "1:02:09".
    static func label(_ seconds: Double) -> String {
        let whole = seconds.isFinite ? max(0, Int(seconds)) : 0
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// The speeds the menu offers.
    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    /// A speed as "1×" or "1.25×".
    static func speedLabel(_ speed: Double, locale: Locale = .current) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "×"
    }

    /// How far a skip goes, in seconds.
    static let skip = 15.0
}
