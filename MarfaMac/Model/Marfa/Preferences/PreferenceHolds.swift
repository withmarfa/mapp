import Foundation

/// What the stores report just before they write a synced setting: each unit a store dropped because it could not read
/// it, or that a store's own reading rewrote, and each unit the person's write changed or reset. The next step that
/// follows the Marfa turns a report into a freeze (`PreferencesSync.Record.Frozen`), so the Marfa keeps the row, as it
/// keeps one a store dropped while the sync wrote it. A report can only stop a unit being sent, never cause one: a
/// missing, stale or unreadable list gives the step's outcome without it.
///
/// Kept under its own defaults key, which Reset, restore points and settings files leave alone. The list changes only on
/// the main actor, where every synced setting is written.
nonisolated enum PreferenceHolds {
    static let key = "preferencesHolds"

    /// The settings whose stores read them again after Import, Restore or Reset wrote them (`PreferencesSync.replaced`):
    /// what those wrote is the person's, so the reading reports only what it drops.
    @MainActor static var reloadingReplaced: Set<String> = []

    #if DEBUG
    static let hooks = TestHooks()
    #endif

    /// What a person's write drops of the stored value because its store could not read it.
    enum Dropped: Sendable, Equatable {
        case nothing
        /// The entries by name: a row's key.
        case entries(Set<String>)
        /// The whole stored value, including one of another kind than the store keeps.
        case whole
    }

    /// Who makes a write, which decides what of it is held.
    enum Writer: Sendable, Equatable {
        /// The store alone, reading what is stored: no change of the person's is in the write.
        case store
        /// The person, or the app's own housekeeping: sent as before, but for what the store dropped. `addressed` names
        /// the entries the person reset, removed or chose on purpose, each released even where nothing is watched.
        case person(dropped: Dropped, addressed: Set<String>)
        /// The person's change to `library`'s sidebar layout, with the layout as the store gave it before the change, so
        /// the rows the store filled from its defaults are told from the person's.
        case sidebar(library: String, before: Data?)

        /// The person's write that drops nothing and resets nothing.
        static let person = Writer.person(dropped: .nothing, addressed: [])
    }

    struct Entry: Codable, Equatable, Sendable {
        enum Kind: Codable, Equatable, Sendable {
            /// One unit: what was stored before the write and what the write left.
            case unit(PreferenceUnit, before: String?, left: String?, seenPending: Bool)
            /// A stored value that could not be read at all: what the write left, and the units the person wrote.
            case whole(left: PreferenceUnits, except: Set<PreferenceUnit>)
            /// The person wrote `value` for the unit, which ends a hold on it.
            case release(PreferenceUnit, value: String?)
        }

        var id = UUID()
        /// The setting's defaults key.
        var key: String
        /// The library of a setting kept for each server; nil for any library.
        var library: String?
        /// The app that wrote the entry; another tries the unit again.
        var build: String
        var kind: Kind

        var isRelease: Bool {
            if case .release = kind { true } else { false }
        }

        func isFor(_ unit: PreferenceUnit, key: String, library: String?) -> Bool {
            guard self.key == key, self.library == library else { return false }
            switch kind {
            case .unit(let held, _, _, _), .release(let held, _): return held == unit
            case .whole: return false
            }
        }
    }

    struct List: Codable, Equatable, Sendable {
        /// The settings with an entry, or a freeze in the sync's record, whose writes are always read in full.
        var watched: Set<String> = []
        var entries: [Entry] = []

        mutating func append(_ entry: Entry) {
            switch entry.kind {
            case .unit(let unit, let before, let left, _):
                var added = entry
                if let index = entries.lastIndex(where: { $0.isFor(unit, key: entry.key, library: entry.library) }),
                   case .unit(_, let earlier, let earlierLeft, _) = entries[index].kind
                {
                    entries.remove(at: index)
                    // What the earlier write left is what this one found, so together they are one change of what was there.
                    if earlierLeft == before { added.kind = .unit(unit, before: earlier, left: left, seenPending: false) }
                }
                entries.append(added)
                watched.insert(entry.key)
            case .release(let unit, _):
                entries.removeAll { $0.isRelease && $0.isFor(unit, key: entry.key, library: entry.library) }
                entries.append(entry)
            case .whole:
                entries.removeAll { $0.key == entry.key && $0.library == entry.library && $0.kind == entry.kind }
                entries.append(entry)
                watched.insert(entry.key)
            }
        }
    }

    /// The list as stored; one that cannot be read is empty.
    static func read(_ defaults: UserDefaults) -> List {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(List.self, from: $0) } ?? List()
    }

    private static func save(_ list: List, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: Reporting

    /// Records what writing `value` (nil for a removal) under `key` will drop, rewrite or release. A store calls it
    /// immediately before it writes a synced setting, after every early return.
    @MainActor
    static func willWrite(_ value: Any?, forKey key: String, in defaults: UserDefaults, by writer: Writer) {
        guard !PreferencesMap.keptWhereAbsent.contains(key),
              let setting = PreferencesMap.synced.first(where: { $0.key == key })
        else { return }
        var list = read(defaults)
        let stored = defaults.object(forKey: key)
        if writer == .person, !list.watched.contains(key), isOwnKind(stored, of: setting) { return }
        #if DEBUG
        hooks.readings.update { $0 += 1 }
        #endif
        let before = list
        let dropsOnly = writer == .store && reloadingReplaced.contains(key)
        for scope in scopes(of: setting, stored: stored, value: value) {
            report(scope, of: setting, by: writer, dropsOnly: dropsOnly, in: &list)
        }
        if list != before { save(list, in: defaults) }
    }

    private struct Scope {
        var library: String?
        var stored: PreferenceReading
        var written: PreferenceReading
    }

    /// The parts of the setting a write is judged by: each library of one kept for each server, or the whole value. A
    /// stored value that is no object of libraries is one part, for whichever library the sync follows, read as written
    /// for the library `value` names.
    private static func scopes(of setting: SyncedSetting, stored: Any?, value: Any?) -> [Scope] {
        guard setting.isPerServer else {
            return [Scope(library: nil, stored: setting.read(stored: stored, library: ""), written: setting.read(stored: value, library: ""))]
        }
        let written = SyncedSetting.storedObject(value, .data)
        guard let libraries = SyncedSetting.storedObject(stored, .data) else {
            let reading: PreferenceReading = if value == nil {
                .units([:])
            } else if let written {
                written.count == 1 ? setting.read(stored: value, library: written.keys.first ?? "") : .units([:])
            } else {
                .unreadable
            }
            return [Scope(library: nil, stored: .unreadable, written: reading)]
        }
        return Set(libraries.keys).union(written.map { Set($0.keys) } ?? []).sorted().map { library in
            Scope(library: library, stored: setting.read(stored: stored, library: library),
                  written: setting.read(stored: value, library: library))
        }
    }

    private static func report(_ scope: Scope, of setting: SyncedSetting, by writer: Writer, dropsOnly: Bool, in list: inout List) {
        guard case .units(let r1) = scope.written else { return }
        let build = PreferencesSync.appBuild
        func entry(_ kind: Entry.Kind) -> Entry { Entry(key: setting.key, library: scope.library, build: build, kind: kind) }
        let addressed: Set<PreferenceUnit> = if case .person(_, let names) = writer { Set(names.compactMap { unit(named: $0, of: setting) }) } else { [] }
        guard case .units(let r0) = scope.stored else {
            let except: Set<PreferenceUnit> = switch writer {
            case .store: dropsOnly ? Set(r1.keys) : []
            case .person: Set(r1.keys)
            case .sidebar(_, let before):
                Set(sidebarRows(before).keys).union(r1.keys).filter { sidebarRows(before)[$0] != r1[$0] }
            }
            list.append(entry(.whole(left: r1, except: except)))
            guard writer != .store else { return }
            // What was stored cannot be read, so every unit the write sets or removes may end a hold, watched or not.
            for unit in except.union(addressed).sorted(by: { "\($0)" < "\($1)" }) {
                list.append(entry(.release(unit, value: r1[unit])))
            }
            return
        }
        let changed = Set(r0.keys).union(r1.keys).filter { r0[$0] != r1[$0] }
        var held: [PreferenceUnit: (before: String?, left: String?)] = [:]
        switch writer {
        case .store:
            for unit in changed where !dropsOnly || r1[unit] == nil { held[unit] = (r0[unit], r1[unit]) }
        case .person(let dropped, _):
            let units: [PreferenceUnit] = switch dropped {
            case .nothing: []
            case .whole: Array(r0.keys)
            case .entries(let names):
                r0.keys.filter { unit in
                    if case .row(_, _, let name) = unit { names.contains(name) } else { false }
                }
            }
            for unit in units where r1[unit] == nil && !addressed.contains(unit) { held[unit] = (r0[unit], nil) }
        case .sidebar(let library, let before):
            guard scope.library == library else { break }
            let filled = sidebarRows(before)
            for (unit, text) in r1 where r0[unit] == nil && filled[unit] == text { held[unit] = (nil, text) }
        }
        for (unit, values) in held.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            list.append(entry(.unit(unit, before: values.before, left: values.left, seenPending: false)))
        }
        guard writer != .store else { return }
        // An unwatched setting has no hold to end, but a whole hold written before the next step could freeze a unit
        // this write removed, and every removal is addressed.
        let released = list.watched.contains(setting.key) ? changed.subtracting(held.keys).union(addressed) : addressed
        for unit in released.sorted(by: { "\($0)" < "\($1)" }) {
            list.append(entry(.release(unit, value: r1[unit])))
        }
    }

    /// The rows of a sidebar layout as encoded, or none where it cannot be read.
    private static func sidebarRows(_ layout: Data?) -> PreferenceUnits {
        guard let layout, let object = (try? JSONSerialization.jsonObject(with: layout)) as? [String: Any] else { return [:] }
        return PreferencesSidebar.rows(of: object) ?? [:]
    }

    /// The unit of the entry `name` of a setting kept as rows.
    private static func unit(named name: String, of setting: SyncedSetting) -> PreferenceUnit? {
        switch setting.place {
        case .rows(let table, let row, _, _, _, _), .serverRows(let table, let row, _), .set(let table, let row):
            .row(table, setting: row, key: name)
        case .member, .serverMember, .sidebar:
            nil
        }
    }

    /// Whether `stored` is of the kind the setting keeps, or nothing, so a write over it needs no splitting.
    private static func isOwnKind(_ stored: Any?, of setting: SyncedSetting) -> Bool {
        guard let stored else { return true }
        switch setting.place {
        case .member: return true
        case .rows(_, _, .data, _, _, _), .serverMember, .serverRows: return stored is Data
        case .rows(_, _, .string, _, _, _), .set: return stored is String
        case .sidebar: return false
        }
    }

    // MARK: Steps

    /// Saves what a step left of the entries it read (`kept`), beside every entry written since it read them, and
    /// watches the settings with an entry or any freeze (`frozen`, by defaults key). Writes only a change.
    @MainActor
    static func finish(read: List, keeping kept: [Entry], frozen: Set<String>, in defaults: UserDefaults) {
        let current = Self.read(defaults)
        let now = Set(current.entries.map(\.id))
        let judged = Set(read.entries.map(\.id))
        var list = List()
        list.entries = kept.filter { now.contains($0.id) } + current.entries.filter { !judged.contains($0.id) }
        list.watched = Set(list.entries.map(\.key)).union(frozen)
        if list != current { save(list, in: defaults) }
    }

    /// Drops every entry of the settings Import, Restore or Reset replaced, but for the units each kept (`except`).
    @MainActor
    static func drop(_ keys: Set<String>, except: Set<PreferenceUnit>, in defaults: UserDefaults) {
        var list = read(defaults)
        let before = list
        list.entries.removeAll { entry in
            guard keys.contains(entry.key) else { return false }
            if case .unit(let unit, _, _, _) = entry.kind, except.contains(unit) { return false }
            return true
        }
        if list != before { save(list, in: defaults) }
    }
}
