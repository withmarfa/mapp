import Foundation

/// Where one setting sits in `app.marfa-mac.preferences`: a member of a field, or a row of a table.
nonisolated enum PreferenceUnit: Hashable, Sendable, Codable {
    case member(PreferencesField, String)
    case row(PreferencesTable, setting: String, key: String)
}

/// Settings by where they sit, each as its JSON text: a member's value written with sorted keys, or a row's `value`.
typealias PreferenceUnits = [PreferenceUnit: String]

/// JSON text written one way, so two Macs holding the same setting hold the same text, and the defaults' property list
/// values written as JSON and read back as they were.
nonisolated enum PreferenceJSON {
    /// A `Data` value, which JSON has no kind for, is kept as an object holding only this member.
    static let dataMember = "$data"

    static func text(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func value(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    /// The text written the one way, or nil where it is not JSON.
    static func canonical(_ text: String) -> String? { value(text).flatMap(Self.text) }

    /// A value read from the defaults, as JSON.
    static func json(fromDefaults value: Any) -> Any {
        switch value {
        case let data as Data: [dataMember: data.base64EncodedString()]
        case let list as [Any]: list.map(json(fromDefaults:))
        case let object as [String: Any]: object.mapValues(json(fromDefaults:))
        case let date as Date: date.timeIntervalSinceReferenceDate
        default: value
        }
    }

    /// JSON as the defaults keep it: what `json(fromDefaults:)` made of a value gives the value back.
    static func defaultsValue(fromJSON value: Any) -> Any {
        switch value {
        case let object as [String: Any]:
            if object.count == 1, let text = object[dataMember] as? String, let data = Data(base64Encoded: text) { return data }
            return object.mapValues(defaultsValue(fromJSON:))
        case let list as [Any]: return list.map(defaultsValue(fromJSON:))
        default: return value
        }
    }

    /// The value the defaults keep for the JSON `text`, or nil where it is not JSON or not a property list, such as one
    /// holding `null`, which the defaults refuse by raising.
    static func defaultsValue(_ text: String) -> Any? {
        guard let json = value(text) else { return nil }
        let value = defaultsValue(fromJSON: json)
        return PropertyListSerialization.propertyList(value, isValidFor: .binary) ? value : nil
    }

    /// A list of words in a stable order, for a value that is a set however the store ordered it.
    static func sortingWordLists(_ value: Any) -> Any {
        guard let object = value as? [String: Any] else { return value }
        return object.mapValues { member in
            (member as? [String]).map { $0.sorted() } ?? member
        }
    }
}

/// What a synced setting holds on this Mac: its settings by where they sit, or nothing to read because the stored text
/// cannot be read. The store sets such text aside itself, so it is neither sent nor written over.
nonisolated enum PreferenceReading: Equatable, Sendable {
    case units(PreferenceUnits)
    case unreadable
}

nonisolated extension SyncedSetting {
    /// Whether `unit` is one this setting reads and writes.
    func owns(_ unit: PreferenceUnit) -> Bool {
        switch (place, unit) {
        case (.member(let field), .member(let unitField, let name)),
             (.serverMember(let field, _), .member(let unitField, let name)):
            field == unitField && name == key
        case (.rows(let table, let setting, _, _, _, _), .row(let unitTable, let unitSetting, _)),
             (.serverRows(let table, let setting, _), .row(let unitTable, let unitSetting, _)),
             (.set(let table, let setting), .row(let unitTable, let unitSetting, _)):
            table == unitTable && setting == unitSetting
        case (.sidebar, .row(let table, _, _)):
            table == .sidebar
        default:
            false
        }
    }

    /// What this Mac holds of the setting, for `library` where it is kept for each server. A stored value of another kind
    /// than the store keeps, such as text where it keeps data, is unreadable, so it is set aside rather than written over.
    func read(_ defaults: UserDefaults, library: String) -> PreferenceReading {
        switch place {
        case .member(let field):
            guard let value = defaults.object(forKey: key) else { return .units([:]) }
            guard let text = PreferenceJSON.text(PreferenceJSON.json(fromDefaults: value)) else { return .unreadable }
            return .units([.member(field, key): text])
        case .serverMember(let field, _):
            guard let servers = Self.storedObject(defaults, key, .data) else { return .unreadable }
            guard let entry = servers[library] else { return .units([:]) }
            guard let text = PreferenceJSON.text(PreferenceJSON.sortingWordLists(entry)) else { return .unreadable }
            return .units([.member(field, key): text])
        case .rows(let table, let setting, let storage, let wrapper, let local, _):
            guard let stored = Self.storedObject(defaults, key, storage) else { return .unreadable }
            var entries = stored
            if let wrapper {
                guard let inner = stored[wrapper].map({ $0 as? [String: Any] }) ?? [:] else { return .unreadable }
                entries = inner
            }
            return Self.rows(entries, table: table, setting: setting, dropping: local)
        case .serverRows(let table, let setting, _):
            guard let servers = Self.storedObject(defaults, key, .data) else { return .unreadable }
            guard let entry = servers[library] else { return .units([:]) }
            guard let entries = entry as? [String: Any] else { return .unreadable }
            return Self.rows(entries, table: table, setting: setting, dropping: [])
        case .set(let table, let setting):
            guard let stored = defaults.object(forKey: key) else { return .units([:]) }
            guard let text = stored as? String, let words = PreferenceJSON.value(text) as? [String] else { return .unreadable }
            return .units(Dictionary(words.map { (.row(table, setting: setting, key: $0), "true") }) { first, _ in first })
        case .sidebar:
            guard let servers = Self.storedObject(defaults, key, .data) else { return .unreadable }
            guard let entry = servers[library] else { return .units([:]) }
            guard let layout = entry as? [String: Any], let units = PreferencesSidebar.rows(of: layout) else { return .unreadable }
            return .units(units)
        }
    }

    /// Whether `text` is a value this setting can store: JSON, and a property list where the defaults keep the value
    /// itself rather than JSON text. A member's `null` stands for no value.
    func accepts(_ text: String) -> Bool {
        switch place {
        case .member: PreferenceJSON.value(text) is NSNull || (PreferenceJSON.defaultsValue(text) != nil && reader.map { $0.reads(text) } ?? true)
        case .serverMember, .rows, .serverRows, .set, .sidebar: PreferenceJSON.value(text) != nil
        }
    }

    /// Makes what this Mac holds of the setting what `units` say, for `library` where it is kept for each server. A
    /// value the setting does not accept (`accepts`) is skipped, so this Mac keeps what it held there, and set aside
    /// under the store's own key where it has one.
    func write(_ units: PreferenceUnits, to defaults: UserDefaults, library: String) {
        var mine = units.filter { owns($0.key) }
        let refused = mine.filter { !accepts($0.value) }
        if !refused.isEmpty {
            let held = if case .units(let held) = read(defaults, library: library) { held } else { PreferenceUnits() }
            for (unit, text) in refused {
                if let setAsideKind { Self.setAside(text, in: setAsideKind, defaults) }
                mine[unit] = held[unit]
            }
        }
        switch place {
        case .member(let field):
            if let text = mine[.member(field, key)], let value = PreferenceJSON.defaultsValue(text) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        case .serverMember(let field, let setAside):
            var servers = Self.storedObject(defaults, key, .data) ?? [:]
            if let text = mine[.member(field, key)] {
                if let value = PreferenceJSON.value(text), !(value is NSNull) {
                    servers[library] = value
                } else {
                    Self.setAside(text, in: setAside, defaults)
                    servers[library] = nil
                }
            } else {
                servers[library] = nil
            }
            Self.store(servers, as: .data, key, defaults)
        case .rows(_, _, let storage, let wrapper, let local, _):
            let current = Self.storedObject(defaults, key, storage).map { stored in
                wrapper.map { stored[$0] as? [String: Any] ?? [:] } ?? stored
            } ?? [:]
            var entries = Self.entries(mine)
            for (name, entry) in entries {
                guard var object = entry as? [String: Any], let kept = current[name] as? [String: Any] else { continue }
                for member in local { object[member] = kept[member] }
                entries[name] = object
            }
            if let wrapper {
                Self.store(entries.isEmpty ? [:] : [wrapper: entries], as: storage, key, defaults)
            } else {
                Self.store(entries, as: storage, key, defaults)
            }
        case .serverRows:
            var servers = Self.storedObject(defaults, key, .data) ?? [:]
            let entries = Self.entries(mine)
            servers[library] = entries.isEmpty ? nil : entries
            Self.store(servers, as: .data, key, defaults)
        case .set:
            let words = mine.compactMap { unit, _ -> String? in
                if case .row(_, _, let word) = unit { word } else { nil }
            }.sorted()
            if words.isEmpty {
                defaults.removeObject(forKey: key)
            } else if let text = PreferenceJSON.text(words) {
                defaults.set(text, forKey: key)
            }
        case .sidebar:
            var servers = Self.storedObject(defaults, key, .data) ?? [:]
            let layout = PreferencesSidebar.layout(from: mine)
            servers[library] = layout.isEmpty ? nil : layout
            Self.store(servers, as: .data, key, defaults)
        }
    }

    // MARK: Parts

    /// The JSON object stored under `key` as `storage` keeps it: an empty one where nothing is stored, nil where what is
    /// stored is not one, or is of another kind than `storage`.
    private static func storedObject(_ defaults: UserDefaults, _ key: String, _ storage: Storage) -> [String: Any]? {
        guard let stored = defaults.object(forKey: key) else { return [:] }
        let data: Data? = switch storage {
        case .data: stored as? Data
        case .string: (stored as? String).map { Data($0.utf8) }
        }
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func rows(_ entries: [String: Any], table: PreferencesTable, setting: String, dropping local: [String])
        -> PreferenceReading
    {
        var units: PreferenceUnits = [:]
        for (name, entry) in entries {
            var value = entry
            if !local.isEmpty, var object = entry as? [String: Any] {
                for member in local { object[member] = nil }
                value = object
            }
            guard let text = PreferenceJSON.text(value) else { return .unreadable }
            units[.row(table, setting: setting, key: name)] = text
        }
        return .units(units)
    }

    /// Each row's value as JSON by its key.
    private static func entries(_ units: PreferenceUnits) -> [String: Any] {
        var entries: [String: Any] = [:]
        for (unit, text) in units {
            guard case .row(_, _, let name) = unit, let value = PreferenceJSON.value(text) else { continue }
            entries[name] = value
        }
        return entries
    }

    private static func store(_ object: [String: Any], as storage: Storage, _ key: String, _ defaults: UserDefaults) {
        guard !object.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return }
        switch storage {
        case .data: defaults.set(data, forKey: key)
        case .string: defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
        }
    }

    static func setAside(_ text: String, in setAside: SetAside, _ defaults: UserDefaults) {
        switch setAside {
        case .data(let key): defaults.set((defaults.array(forKey: key) as? [Data] ?? []) + [Data(text.utf8)], forKey: key)
        case .string(let key): defaults.set((defaults.stringArray(forKey: key) ?? []) + [text], forKey: key)
        }
    }
}

/// The sidebar layout as rows: one for each of its lists (`layout`, by the list's name), and one for each place's
/// section (`home`) and each mark's color (`color`), by the place.
///
/// A mark's color and a place's section change one at a time, so each is a row that two Macs can change apart. The lists
/// (`order`, `tabs`, `groups`, `hidden`, `collapsed`) each say where many things sit relative to each other, so a row
/// for each entry would need positions that two Macs fight over; each list is one row, and the later arrangement wins
/// whole. A member a later version of the app adds is a `layout` row too.
nonisolated enum PreferencesSidebar {
    static let layoutSetting = "layout"
    static let homeSetting = "home"
    static let colorSetting = "color"
    private static let split = ["homes": homeSetting, "colors": colorSetting]
    /// Lists that are sets, whose order says nothing.
    private static let sets: Set<String> = ["hidden", "collapsed"]

    static func rows(of layout: [String: Any]) -> PreferenceUnits? {
        var units: PreferenceUnits = [:]
        for (member, value) in layout {
            if let setting = split[member], let places = value as? [String: Any] {
                for (place, entry) in places {
                    guard let text = PreferenceJSON.text(entry) else { return nil }
                    units[.row(.sidebar, setting: setting, key: place)] = text
                }
            } else {
                let stable = sets.contains(member) ? ((value as? [String])?.sorted() ?? value) : value
                guard let text = PreferenceJSON.text(stable) else { return nil }
                units[.row(.sidebar, setting: layoutSetting, key: member)] = text
            }
        }
        return units
    }

    /// The layout the rows make; a row that is not JSON is left out.
    static func layout(from units: PreferenceUnits) -> [String: Any] {
        var layout: [String: Any] = [:]
        for (unit, text) in units {
            guard case .row(.sidebar, let setting, let key) = unit, let value = PreferenceJSON.value(text) else { continue }
            if let member = split.first(where: { $0.value == setting })?.key {
                var places = layout[member] as? [String: Any] ?? [:]
                places[key] = value
                layout[member] = places
            } else if setting == layoutSetting {
                layout[key] = value
            }
        }
        return layout
    }
}
