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
/// An entry a later version wrote with a density this one does not know stays as stored beside the others; stored data
/// that cannot be read is moved aside under a key of its own, kept and never removed.
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

    private static func load(_ defaults: UserDefaults) -> StoredMap<Density> {
        StoredMap(defaults, key: key) { ($0 as? String).flatMap(Density.init(rawValue:)) }
    }

    /// The stored densities; data that cannot be read is no densities, never a failure.
    static func stored(in defaults: UserDefaults = .standard) -> PlaceDensities {
        PlaceDensities(load(defaults).readable)
    }

    /// Changes the stored densities. A place's density this version cannot read stays as stored until the change sets
    /// that place; stored data that is no map is set aside whole first (`StoredMap`).
    static func update(in defaults: UserDefaults = .standard, _ change: (inout PlaceDensities) -> Void) {
        let stored = load(defaults)
        var value = PlaceDensities(stored.readable)
        change(&value)
        stored.save(value.places, encode: \.rawValue, to: key, setAside: setAsideKey, in: defaults)
    }
}
