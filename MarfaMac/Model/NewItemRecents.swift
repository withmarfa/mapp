import Foundation

/// The kinds, tags and parents the person last gave a new item in each library, newest first, which the new-item
/// line offers before anything is typed. They stay on this Mac (`PreferencesMap.staysOnMac`): they change with every
/// item added, and syncing them would write the shared settings item each time.
nonisolated struct NewItemRecents: Codable, Equatable {
    var kinds: [String] = []
    var tags: [String] = []
    var parents: [ItemID] = []

    static let key = "newItemRecents"
    /// Stored data that could not be read, kept and never removed, in the order it was found.
    static let setAsideKey = "newItemRecentsSetAside"
    /// How many of each are kept.
    static let limit = 6

    /// What `library` (`ItemLibrary.serverKey`) last used.
    static func stored(for library: String, in defaults: UserDefaults = .standard) -> NewItemRecents {
        all(in: defaults)[library] ?? NewItemRecents()
    }

    /// Puts what an item was just added with first.
    static func remember(kind: String, tags: [String], parent: ItemID?, for library: String, in defaults: UserDefaults = .standard) {
        var all = all(in: defaults)
        var recents = all[library] ?? NewItemRecents()
        recents.kinds = Array(([kind] + recents.kinds.filter { $0 != kind }).prefix(limit))
        recents.tags = Array((tags + recents.tags.filter { !tags.contains($0) }).prefix(limit))
        if let parent { recents.parents = Array(([parent] + recents.parents.filter { $0 != parent }).prefix(limit)) }
        all[library] = recents
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    private static func all(in defaults: UserDefaults) -> [String: NewItemRecents] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        if let all = try? JSONDecoder().decode([String: NewItemRecents].self, from: data) { return all }
        defaults.set((defaults.array(forKey: setAsideKey) as? [Data] ?? []) + [data], forKey: setAsideKey)
        defaults.removeObject(forKey: key)
        return [:]
    }
}
