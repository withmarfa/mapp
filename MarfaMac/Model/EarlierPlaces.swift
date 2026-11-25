import Foundation

/// How earlier copies of the app named a place, read once into a `PlaceView` so nothing a person kept is lost: they
/// stored a place as a JSON object, such as `{"itemType":{"_0":"core.task"}}`. Inbox is the Feed; All Items and Recents
/// are the Library; Favorites is the Library's Favorites view, and one favorite the Library with that item chosen; a
/// saved view is the view at its home. Files is no place now, so what was kept for it is left where it is, readable by
/// those copies, and the person is told once (`tellFilesOnce`).
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

    /// The new key what an earlier copy kept under `key` moves to: only where one earlier place stands for the new one,
    /// so neither Recents, which shares the Library with All Items, nor one favorite or Files is moved.
    static func carriedKey(for key: String) -> String? {
        guard let parts = parts(of: key), parts.name != "recents",
              case .place(let place, nil)? = read(name: parts.name, value: parts.value) else { return nil }
        return place.storageKey
    }

    /// `entries` with what earlier copies kept moved to the new keys. A new key already held wins, and the earlier entry
    /// goes; an entry no new key stands for is left as it is, for those copies.
    static func carried<Value>(_ entries: [String: Value]) -> [String: Value] {
        var result = entries
        for (key, value) in entries {
            guard let new = carriedKey(for: key) else { continue }
            result[key] = nil
            if entries[new] == nil { result[new] = value }
        }
        return result
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
