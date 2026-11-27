import Foundation

/// The units a store's reading removed because it could not read them, reported just before the store writes. The next
/// step that follows the Marfa holds each such row as the Marfa has it (`PreferencesSync.Record.Adopted.held`), where it
/// would otherwise send the removal. An entry can only stop a deletion being sent, never cause a write: a missing, stale
/// or unreadable list gives the step's outcome without it.
///
/// Kept under its own defaults key, which Reset, restore points and settings files leave alone. The list changes only on
/// the main actor, where every synced setting is written.
nonisolated enum PreferenceHolds {
    static let key = "preferencesHolds"

    struct Entry: Codable, Equatable, Sendable {
        var id = UUID()
        /// The setting's defaults key.
        var key: String
        /// The library of a setting kept for each server; nil for any library.
        var library: String?
        var unit: PreferenceUnit
        /// What the unit held before the store's write.
        var before: String
        /// Set once a step found this Mac still holding `before`, as after a crash before the store wrote, or a write made
        /// while the step read; the next such step drops the entry.
        var seenPending = false

        func isSame(_ other: Entry) -> Bool {
            key == other.key && library == other.library && unit == other.unit && before == other.before
        }
    }

    /// The list as stored; one that cannot be read is empty.
    static func read(_ defaults: UserDefaults) -> [Entry] {
        stored(defaults)
    }

    /// Records each unit the stored value holds that writing `value` (nil for a removal) under `key` removes. A store
    /// calls it immediately before a write that removes what it could not read. A stored value the sync cannot split
    /// records nothing, and nor does a unit the write keeps.
    @MainActor
    static func willWrite(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        guard !PreferencesMap.keptWhereAbsent.contains(key),
              let setting = PreferencesMap.synced.first(where: { $0.key == key })
        else { return }
        let held = defaults.object(forKey: key)
        let libraries: [String?] = if setting.isPerServer {
            (SyncedSetting.storedObject(held, .data) ?? [:]).keys.sorted()
        } else {
            [nil]
        }
        var list = stored(defaults)
        let earlier = list
        for library in libraries {
            guard case .units(let before) = setting.read(stored: held, library: library ?? ""),
                  case .units(let after) = setting.read(stored: value, library: library ?? "")
            else { continue }
            for (unit, text) in before.sorted(by: { "\($0.key)" < "\($1.key)" }) where after[unit] == nil {
                let entry = Entry(key: key, library: library, unit: unit, before: text)
                list.removeAll { $0.isSame(entry) }
                list.append(entry)
            }
        }
        if list != earlier { save(list, in: defaults) }
    }

    /// Saves what a step leaves of the entries it `read`: those it is `keeping`, as it keeps them, and every entry
    /// written since it read. Writes only a change, since every write to the defaults asks for another step.
    @MainActor
    static func finish(read: [Entry], keeping: [Entry], in defaults: UserDefaults) {
        let readIDs = Set(read.map(\.id))
        let kept = Dictionary(keeping.map { ($0.id, $0) }) { first, _ in first }
        let current = stored(defaults)
        let left = current.compactMap { entry in readIDs.contains(entry.id) ? kept[entry.id] : entry }
        if left != current { save(left, in: defaults) }
    }

    private static func stored(_ defaults: UserDefaults) -> [Entry] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    private static func save(_ list: [Entry], in defaults: UserDefaults) {
        guard !list.isEmpty else { return defaults.removeObject(forKey: key) }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
