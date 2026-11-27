import Foundation

/// How much a list's row says: Standard draws the title, the date, the line under the title and the chips; Compact draws
/// the title and the date, with the type's mark where the list mixes types. Every list takes the density of Settings until a
/// saved view or a place chooses its own.
nonisolated enum Density: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case standard
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .compact: String(localized: "Compact")
        }
    }
}

/// The density each place that is not a saved view keeps for itself: one value in the defaults, by place, which syncs
/// through the Marfa (`PreferencesMap`). A saved view's density is in
/// its Mac settings (`ViewMacSettings.density`). A place with no entry follows Settings.
///
/// Stored text that cannot be read, or an entry a later version wrote with a density this one does not know, is moved
/// aside under a key of its own, kept and never removed; what can be read is kept.
nonisolated struct PlaceDensities: Equatable, Sendable {
    static let key = "placeDensities"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "placeDensitiesSetAside"

    private(set) var places: [String: Density] = [:]

    init(_ places: [String: Density] = [:]) {
        self.places = places
    }

    func density(for place: PlaceView) -> Density? {
        places[place.storageKey]
    }

    mutating func set(_ density: Density?, for place: PlaceView) {
        places[place.storageKey] = density
    }

    // MARK: Keeping

    /// The stored densities, and the stored data that could not be read: the whole of it where it is not an object of words,
    /// otherwise an object of the entries whose word is not a density.
    private static func read(_ data: Data) -> (readable: PlaceDensities, unreadable: Data?, dropped: PreferenceHolds.Dropped) {
        guard let words = try? JSONDecoder().decode([String: String].self, from: data) else { return (PlaceDensities(), data, .whole) }
        var readable: [String: Density] = [:]
        var unreadable: [String: String] = [:]
        for (place, word) in words {
            if let density = Density(rawValue: word) { readable[place] = density } else { unreadable[place] = word }
        }
        return (PlaceDensities(readable), unreadable.isEmpty ? nil : try? encode(unreadable), .entries(Set(unreadable.keys)))
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// The stored densities; data that cannot be read is no densities, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> PlaceDensities {
        defaults.data(forKey: key).map { read($0).readable } ?? PlaceDensities()
    }

    /// Changes the stored densities. What this write would replace and cannot read is kept aside first. `addressing`
    /// names the places the person resets on purpose.
    @MainActor
    static func update(in defaults: UserDefaults = .standard, addressing: Set<String> = [], _ change: (inout PlaceDensities) -> Void) {
        var value = PlaceDensities()
        var dropped: PreferenceHolds.Dropped = defaults.object(forKey: key) == nil ? .nothing : .whole
        if let saved = defaults.data(forKey: key) {
            let read = read(saved)
            value = read.readable
            dropped = read.dropped
            if let unreadable = read.unreadable {
                defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [unreadable], forKey: setAsideKey)
            }
        }
        change(&value)
        let writer = PreferenceHolds.Writer.person(dropped: dropped, addressed: addressing)
        if value.places.isEmpty {
            PreferenceHolds.willWrite(nil, forKey: key, in: defaults, by: writer)
            defaults.removeObject(forKey: key)
        } else if let data = try? encode(value.places.mapValues(\.rawValue)) {
            PreferenceHolds.willWrite(data, forKey: key, in: defaults, by: writer)
            defaults.set(data, forKey: key)
        }
    }
}
