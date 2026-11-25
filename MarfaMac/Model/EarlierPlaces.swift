import Foundation

/// How earlier copies of the app named a place, read once into a `PlaceView` so nothing a person kept is lost: they
/// stored a place as a JSON object, such as `{"itemType":{"_0":"core.task"}}`. Inbox is the Feed; All Items and Recents
/// are the Library; Favorites is the Library's Favorites view, and one favorite the Library with that item chosen; a
/// saved view is the view at its home. Files is no place now, so what was kept for it is left where it is, readable by
/// those copies, and the person is told once (`tellFilesOnce`). What an earlier copy kept is never removed.
nonisolated enum EarlierPlace {
    /// What an earlier place reads as.
    enum Reading: Equatable {
        case place(PlaceView, selecting: ItemID? = nil)
        case files
    }

    /// The reading of an earlier place's stored text, or nil for text in no earlier form.
    static func read(key: String) -> Reading? {
        parts(of: key).flatMap { read(name: $0.name, value: $0.value) }
    }

    private static func parts(of key: String) -> (name: String, value: String?)? {
        guard key.hasPrefix("{"), let object = try? JSONDecoder().decode([String: [String: String]].self, from: Data(key.utf8)),
              object.count == 1, let (name, values) = object.first else { return nil }
        return (name, values["_0"])
    }

    /// The reading of an earlier place by its case name and value, as its JSON object held them.
    static func read(name: String, value: String?) -> Reading? {
        switch (name, value) {
        case ("inbox", nil): .place(.feed)
        case ("allNotes", nil), ("recents", nil): .place(.library)
        case ("favorites", nil): .place(.favorites)
        case ("favoriteItem", let id?): .place(.library, selecting: ItemID(id))
        case ("itemType", let type?): .place(.type(TypeID(type)))
        case ("collection", let id?): .place(.collection(ItemID(id)))
        case ("source", let code?): .place(.source(code))
        case ("collections", nil): .place(.collections)
        case ("sources", nil): .place(.sources)
        // A saved view's key names no place (`PlaceView.storageKey`), so its home is found when it is shown.
        case ("view", let id?): .place(PlaceView(.library, .saved(ItemID(id))))
        case ("files", nil): .files
        default: nil
        }
    }

    /// The new key what an earlier copy kept under `key` is copied to, and whether it fills only what All Items left:
    /// Recents shares the Library with All Items. One favorite and Files stand for no place, so nothing is copied.
    private static func carriedKey(for key: String) -> (key: String, fills: Bool)? {
        guard let parts = parts(of: key), case .place(let place, nil)? = read(name: parts.name, value: parts.value) else { return nil }
        return (place.storageKey, parts.name == "recents")
    }

    /// `entries` with what earlier copies kept copied to the new keys, the earlier entries left for those copies. A new
    /// key already held comes first, then the one earlier place that stands for it, then Recents for the Library;
    /// `fill` takes from a later one what an earlier one left unset.
    static func carried<Value>(_ entries: [String: Value], fill: (Value, Value) -> Value = { held, _ in held }) -> [String: Value] {
        var sources: [String: [(fills: Bool, value: Value)]] = [:]
        for (key, value) in entries {
            guard let new = carriedKey(for: key) else { continue }
            sources[new.key, default: []].append((new.fills, value))
        }
        var result = entries
        for (key, found) in sources {
            let ordered = found.filter { !$0.fills } + found.filter(\.fills)
            result[key] = ordered.reduce(entries[key]) { held, source in held.map { fill($0, source.value) } ?? source.value }
        }
        return result
    }

    /// Whether what earlier copies kept for each place has been copied to the new keys on this Mac.
    static let readInKey = "earlierPlacesReadIn"

    /// Copies what earlier copies kept for each place to the new keys, once on this Mac, so a place opens as the person
    /// left it. The earlier entries stay for those copies, and an entry the person clears later does not come back.
    @MainActor static func readIn(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: readInKey) else { return }
        defaults.set(true, forKey: readInKey)
        let densities = PlaceDensities.stored(in: defaults).places
        if carried(densities) != densities { PlaceDensities.update(in: defaults) { $0 = PlaceDensities(carried($0.places)) } }
        let placeDefaults = PlaceDefaults.stored(in: defaults).places
        if carried(placeDefaults, fill: { $0.filled(from: $1) }) != placeDefaults {
            PlaceDefaults.update(in: defaults) { $0 = PlaceDefaults(carried($0.places) { $0.filled(from: $1) }) }
        }
        ItemTableColumnLayouts.readIn(in: defaults)
        StartWith.readIn(in: defaults)
    }

    /// Whether the person has been told that Files is no longer a place, on this Mac.
    static let filesToldKey = "filesNoLongerAPlaceTold"

    /// Tells the person once that Files is no longer a place in the sidebar.
    @MainActor static func tellFilesOnce(_ notices: Notices, in defaults: UserDefaults) {
        guard !defaults.bool(forKey: filesToldKey) else { return }
        defaults.set(true, forKey: filesToldKey)
        notices.tell(
            String(localized: "Files Is No Longer in the Sidebar"),
            String(localized: "Files is no longer a place in the sidebar. Files are listed under their types."))
    }
}
