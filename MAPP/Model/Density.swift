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

/// The density each place that is not a saved view keeps for itself on this Mac, as the table keeps its columns
/// (`ItemTableColumnLayouts`): one value in the defaults, by place, never written to Marfa. A saved view's density is in
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

    func density(for place: SidebarItem) -> Density? {
        places[place.storageKey]
    }

    mutating func set(_ density: Density?, for place: SidebarItem) {
        places[place.storageKey] = density
    }

    // MARK: Keeping

    /// The stored densities, and the stored data that could not be read: the whole of it where it is not an object of words,
    /// otherwise an object of the entries whose word is not a density.
    private static func read(_ data: Data) -> (readable: PlaceDensities, unreadable: Data?) {
        guard let words = try? JSONDecoder().decode([String: String].self, from: data) else { return (PlaceDensities(), data) }
        var readable: [String: Density] = [:]
        var unreadable: [String: String] = [:]
        for (place, word) in words {
            if let density = Density(rawValue: word) { readable[place] = density } else { unreadable[place] = word }
        }
        return (PlaceDensities(readable), unreadable.isEmpty ? nil : try? encode(unreadable))
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

    /// Changes the stored densities. What this write would replace and cannot read is kept aside first.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout PlaceDensities) -> Void) {
        var value = PlaceDensities()
        if let saved = defaults.data(forKey: key) {
            let (readable, unreadable) = read(saved)
            value = readable
            if let unreadable { defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [unreadable], forKey: setAsideKey) }
        }
        change(&value)
        if value.places.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? encode(value.places.mapValues(\.rawValue)) {
            defaults.set(data, forKey: key)
        }
    }
}
