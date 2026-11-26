import Foundation

/// What a store set aside of a synced setting on its own, with no act of the person's: the rows it dropped, recorded when
/// it dropped them. `PreferencesSync` keeps each such row in the Marfa (`Record.Adopted.frozen`) until the person sets it
/// here, and deletes a row this Mac lacks for any other reason, which is the person's removal.
nonisolated struct PreferenceHold: Codable, Equatable, Sendable {
    /// The setting's defaults key.
    var setting: String
    /// The library whose entry it set aside, for a setting kept for each server; nil for every library.
    var library: String?
    /// The rows it set aside, by key; nil for every row but `kept`.
    var keys: [String]?
    /// With no `keys`, the rows the store's own write still held, which the person may yet remove.
    var kept: [String]?
    /// The libraries that took a hold made for every library.
    var taken: [String]?

    /// Which of `units`, the rows this Mac lacks of `setting`, the hold names for `library`.
    func names(_ units: [PreferenceUnit], library: String) -> [PreferenceUnit] {
        guard self.library == nil || self.library == library, !(taken ?? []).contains(library) else { return [] }
        return units.filter { unit in
            guard case .row(_, _, let key) = unit else { return keys == nil }
            if let keys { return keys.contains(key) }
            return !(kept ?? []).contains(key)
        }
    }
}

nonisolated enum PreferenceHolds {
    /// Bookkeeping of the sync, not a setting: Reset, restore points and files leave it alone.
    static let key = "preferencesHeld"

    static func read(_ defaults: UserDefaults) -> [PreferenceHold] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PreferenceHold].self, from: $0) } ?? []
    }

    static func write(_ holds: [PreferenceHold], to defaults: UserDefaults) {
        guard holds != read(defaults) else { return }
        if holds.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(holds) {
            defaults.set(data, forKey: key)
        }
    }

    /// Records that the store of `setting` dropped the rows `keys` names (or, with none, every row but `kept`), for
    /// `library` where it keeps one entry for each server.
    static func record(_ setting: String, library: String? = nil, keys: [String]?, kept: [String] = [], in defaults: UserDefaults) {
        guard keys.map({ !$0.isEmpty }) ?? true else { return }
        let hold = PreferenceHold(setting: setting, library: library, keys: keys?.sorted(), kept: keys == nil ? kept.sorted() : nil)
        write(read(defaults) + [hold], to: defaults)
    }

    /// Appends `data` to the set-aside list `list`, and records the hold.
    static func setAside(_ data: Data, under list: String, of setting: String, library: String? = nil, keys: [String]?,
                         kept: [String] = [], in defaults: UserDefaults)
    {
        defaults.set((defaults.array(forKey: list) as? [Data] ?? []) + [data], forKey: list)
        record(setting, library: library, keys: keys, kept: kept, in: defaults)
    }

    /// Appends `text` to the set-aside list `list`, and records the hold.
    static func setAside(_ text: String, under list: String, of setting: String, keys: [String]?, kept: [String] = [],
                         in defaults: UserDefaults)
    {
        defaults.set((defaults.stringArray(forKey: list) ?? []) + [text], forKey: list)
        record(setting, keys: keys, kept: kept, in: defaults)
    }

    /// Records that a value kept for each server lost the entries `unreadable` holds, by library, or every library's where
    /// what was `stored` was no object of libraries.
    static func recordByLibrary(_ unreadable: Data, of setting: String, from stored: Data, in defaults: UserDefaults) {
        guard keys(of: stored) != nil, let libraries = keys(of: unreadable) else { return record(setting, keys: nil, in: defaults) }
        for library in libraries { record(setting, library: library, keys: nil, in: defaults) }
    }

    /// The keys of a JSON object's entries, or nil where `data` is no object.
    static func keys(of data: Data) -> [String]? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).map { Array($0.keys) }
    }
}
