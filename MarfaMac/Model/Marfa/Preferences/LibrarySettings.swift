import CryptoKit
import Foundation
import os

/// The settings this Mac keeps for each library (`SyncedSetting.isPerServer`): the order each was last written in, and
/// the move of what a library kept under an earlier name to the name it has now (`MarfaHost.currentLibraryKey`).
///
/// Earlier builds named a library by its address as typed, so one Marfa can hold settings under two spellings, or
/// under the address it moved from. A move joins them part by part, so a part only one name held is kept. Where two
/// names held a part differently, the one written or removed later wins, by the order kept here; for values held before
/// this order was kept, the library that was open last wins. Where nothing says which was later, the value the Marfa
/// holds wins, else the first by name, and it is logged; until the library's Marfa is known, such a part does not move.
/// Every value that does not win is first saved in a file beside the restore points that the app never removes; where
/// it cannot be saved, nothing moves. A name whose setting cannot be read keeps it as stored, and the sync changes
/// nothing of that setting (`unsettled`) until it moves. What a store set aside from a name, as it could not read it,
/// is no removal: the Marfa's rows stand in for it once the Marfa is known, and its stored bytes go in the file.
@MainActor final class LibrarySettings {
    /// The order each part of each library's settings was last written in. Bookkeeping, not a setting.
    nonisolated static let orderKey = "librarySettingsOrder"
    nonisolated static let asideFolderName = "Library Settings Set Aside"
    static let settings = PreferencesMap.synced.filter(\.isPerServer)

    nonisolated struct Book: Codable, Equatable, Sendable {
        var next = 1
        /// By library, then by part (`PreferenceUnit` as JSON).
        var stamps: [String: [String: Stamp]] = [:]
        /// The settings each library held that could not be read when last looked at, by setting key.
        var unread: [String: Set<String>] = [:]
        /// The hash of what each setting's store had set aside when last looked at, by setting key.
        var asides: [String: String] = [:]
        /// The settings whose store set something aside that the setting's own value has not yet been seen to lose.
        var settingAside: Set<String> = []
        /// What each setting's store set aside from a library because it could not read it, by library then setting
        /// key, which the move stands in for with the Marfa's rows (`settle`).
        var lost: [String: [String: Lost]] = [:]
        /// Each setting's stored bytes when last seen holding a library that could not be read, by setting key.
        var unreadBytes: [String: Data] = [:]

        static func read(_ defaults: UserDefaults) -> Book? {
            defaults.data(forKey: orderKey).flatMap { try? JSONDecoder().decode(Book.self, from: $0) }
        }

        func save(_ defaults: UserDefaults) {
            guard self != Self.read(defaults), let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: orderKey)
        }
    }

    nonisolated struct Stamp: Codable, Equatable, Sendable {
        /// The value's hash; nil for a part seen removed.
        var hash: String?
        /// The write that last changed the part; 0 for the library open when the order began to be kept, and nil for
        /// any other value held then.
        var order: Int?
    }

    /// What a store set aside from one library's setting.
    nonisolated struct Lost: Codable, Equatable, Sendable {
        /// The parts set aside, by name; nil where the library's whole entry was, so it may have held any part.
        var parts: Set<String>?
        /// The setting's stored bytes before the store set them aside.
        var stored: Data?

        func covers(_ name: String) -> Bool { parts?.contains(name) ?? true }
    }

    enum Failure: Error, Equatable {
        /// The values that would not win could not be saved, so nothing moved.
        case notSetAside
    }

    /// Why the value kept won, as the file says.
    nonisolated enum Reason: String, Codable, Sendable {
        case later
        case lastOpen
        /// Nothing said which was later: the Marfa's value, else the first library by name, was kept.
        case unknown
    }

    private let defaults: UserDefaults
    /// Where the values that did not win are saved, one file a move.
    let aside: URL
    private let build: String
    private var seen: [Data?]?
    private var observer: (any NSObjectProtocol)?
    /// The settings, by the name a library has now, that some earlier name still holds because they could not be read
    /// or decided, which the sync leaves as they are (`PreferencesSync.unsettled`). Found again by each `settle`.
    private(set) var unsettled: [String: Set<String>] = [:]

    /// `lastOpen` is the key the library open last was stored under, which wins over other values held before the
    /// order was kept.
    init(defaults: UserDefaults, aside: URL, lastOpen: String?, build: String = PreferencesSync.appBuild) {
        self.defaults = defaults
        self.aside = aside
        self.build = build
        if Book.read(defaults) == nil {
            var book = Book()
            for setting in Self.settings {
                book.asides[setting.key] = asideHash(of: setting)
                for library in libraries(of: setting, in: book) {
                    guard case .units(let units) = setting.read(defaults, library: library) else { continue }
                    for (unit, text) in units {
                        book.stamps[library, default: [:]][Self.name(unit)] = Stamp(hash: Self.hash(text), order: library == lastOpen ? 0 : nil)
                    }
                }
            }
            book.save(defaults)
        }
        note()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.note() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: The order of writes

    private func raw() -> [Data?] {
        Self.settings.flatMap { setting in
            [defaults.object(forKey: setting.key), setting.setAsideKind.flatMap { defaults.object(forKey: Self.key(of: $0)) }].map { object in
                object.flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
            }
        }
    }

    private nonisolated static func key(of kind: SyncedSetting.SetAside) -> String {
        switch kind {
        case .data(let key), .string(let key): key
        }
    }

    private func asideHash(of setting: SyncedSetting) -> String? {
        guard let kind = setting.setAsideKind, let object = defaults.object(forKey: Self.key(of: kind)),
              let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        else { return nil }
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Stamps each part changed since the last look with the next write's order, and each part seen gone with a
    /// removal of that order. A part is seen gone only from a library whose setting was read before and now: one that
    /// could not be read, or whose store set something aside, loses its stamps instead, since that is no removal of the
    /// person's, and is kept as lost (`Book.lost`) with the bytes it was stored in. `carrying` gives each part a move
    /// wrote or removed the order of the value that won; `moving` names, by setting key, the libraries a move took that
    /// setting from, whose stamps and losses of it go.
    private func note(carrying: [String: [String: Int?]] = [:], moving: [String: Set<String>] = [:]) {
        let now = raw()
        guard now != seen || !carrying.isEmpty || !moving.isEmpty else { return }
        let before = seen
        seen = now
        var book = Book.read(defaults) ?? Book()
        let order = book.next
        var wrote = false
        var stamps: [String: [String: Stamp]] = [:]
        var unread: [String: Set<String>] = [:]
        var lost: [String: [String: Lost]] = [:]
        var unreadBytes: [String: Data] = [:]
        for (index, setting) in Self.settings.enumerated() {
            let aside = asideHash(of: setting)
            let valueChanged = before.map { $0[index * 2] != now[index * 2] } ?? true
            if aside != book.asides[setting.key] { book.settingAside.insert(setting.key) }
            book.asides[setting.key] = aside
            let forgiving = book.settingAside.contains(setting.key)
            if valueChanged { book.settingAside.remove(setting.key) }
            let moved = moving[setting.key] ?? []
            let storedBefore = before.flatMap { Self.storedBytes($0[index * 2]) }
            for library in libraries(of: setting, in: book) {
                let earlier = (book.stamps[library] ?? [:]).filter { Self.unit(named: $0.key).map(setting.owns) == true }
                var losing = book.lost[library]?[setting.key]
                guard case .units(let units) = setting.read(defaults, library: library) else {
                    unread[library, default: []].insert(setting.key)
                    stamps[library, default: [:]].merge(earlier) { _, kept in kept }
                    if let losing { lost[library, default: [:]][setting.key] = losing }
                    unreadBytes[setting.key] = defaults.data(forKey: setting.key)
                    continue
                }
                guard !moved.contains(library) else { continue }
                let wasUnread = book.unread[library]?.contains(setting.key) == true
                if wasUnread, forgiving { losing = Lost(parts: nil, stored: book.unreadBytes[setting.key] ?? storedBefore) }
                var parts: [String: Stamp] = [:]
                for (unit, text) in units {
                    let name = Self.name(unit)
                    let hash = Self.hash(text)
                    if let carried = carrying[library]?[name] {
                        parts[name] = Stamp(hash: hash, order: carried)
                    } else if let stamp = earlier[name], stamp.hash == hash {
                        parts[name] = stamp
                    } else {
                        parts[name] = Stamp(hash: hash, order: order)
                        wrote = true
                    }
                }
                for (name, stamp) in earlier where parts[name] == nil {
                    if let carried = carrying[library]?[name] {
                        parts[name] = Stamp(hash: nil, order: carried)
                    } else if stamp.hash == nil {
                        parts[name] = stamp
                    } else if !wasUnread, !forgiving {
                        parts[name] = Stamp(hash: nil, order: order)
                        wrote = true
                    } else if !wasUnread, losing == nil || losing?.parts != nil {
                        losing = Lost(parts: (losing?.parts ?? []).union([name]), stored: losing?.stored ?? storedBefore)
                    }
                }
                // A part written or removed since is the person's choice, which stands in for nothing.
                if let set = losing?.parts { losing?.parts = set.subtracting(parts.keys) }
                if let losing, losing.parts?.isEmpty != true { lost[library, default: [:]][setting.key] = losing }
                if !parts.isEmpty { stamps[library, default: [:]].merge(parts) { _, kept in kept } }
            }
        }
        if wrote { book.next += 1 }
        book.stamps = stamps
        book.unread = unread
        book.lost = lost
        book.unreadBytes = unreadBytes
        book.save(defaults)
    }

    /// The libraries `setting` holds a value for, those with a stamp of one of its parts, and those it could not read
    /// or that its store set something aside from.
    private func libraries(of setting: SyncedSetting, in book: Book) -> [String] {
        var libraries = Set(storedLibraries(of: setting))
        for (library, parts) in book.stamps where parts.keys.contains(where: { Self.unit(named: $0).map(setting.owns) == true }) {
            libraries.insert(library)
        }
        for (library, keys) in book.unread where keys.contains(setting.key) { libraries.insert(library) }
        for (library, settings) in book.lost where settings[setting.key] != nil { libraries.insert(library) }
        return libraries.sorted()
    }

    /// The data a setting's defaults value holds, from the property list `raw` kept of it.
    private nonisolated static func storedBytes(_ plist: Data?) -> Data? {
        plist.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }.flatMap { $0 as? Data }
    }

    private func storedLibraries(of setting: SyncedSetting) -> [String] {
        guard let data = defaults.data(forKey: setting.key),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return object.keys.sorted()
    }

    // MARK: Moving

    /// One part that two names held differently, as the file keeps it.
    nonisolated struct SetAside: Codable, Equatable, Sendable {
        nonisolated struct Value: Codable, Equatable, Sendable {
            /// The name the library's settings were kept under.
            var library: String
            /// The value as JSON text; none where the part was removed.
            var value: String?
            /// Whether the part was removed under this name.
            var removed: Bool?

            init(library: String, value: String?) {
                self.library = library
                self.value = value
                removed = value == nil ? true : nil
            }
        }

        /// The name the settings are kept under now.
        var library: String
        var setting: String
        var part: String
        var kept: Value
        var setAside: [Value]
        var why: Reason
    }

    /// What a store set aside from a name a move took, as the file keeps it.
    nonisolated struct Unreadable: Codable, Equatable, Sendable {
        var library: String
        var setting: String
        /// The parts set aside; none where the whole entry was.
        var parts: [String]?
        /// The setting's bytes as stored before the store set them aside.
        var stored: Data?
    }

    private nonisolated struct File: Codable {
        var about: String
        var date: Date
        var build: String
        var settings: [SetAside]
        var unreadable: [Unreadable]
    }

    nonisolated struct Moved: Equatable, Sendable {
        /// The names moved from, by the name moved to.
        var libraries: [String: [String]] = [:]
        /// The file the values that did not win were saved in, if any.
        var file: URL?
        var setAside: [SetAside] = []
        var unreadable: [Unreadable] = []
    }

    /// Moves what each library kept under an earlier name to the name `rename` gives it, nil for a name that stays. A
    /// setting the new name holds that cannot be read moves from no name; one an earlier name holds that cannot be read
    /// stays under it as stored, while the names that can be read move. A part held differently with nothing to say
    /// which is later moves only once the new name is the library's Marfa, so the Marfa's value can win. Where a store set
    /// aside what an earlier name held (`Book.lost`), that name holds the Marfa's rows in its place, so the setting moves
    /// only once the Marfa is known, and a value written or removed since still wins. What does not move is tried again
    /// at the next move, and is `unsettled` meanwhile. A name with only removals or losses left moves as one with values.
    @discardableResult
    func settle(rename: (String) -> String?) throws(Failure) -> Moved {
        note()
        let book = Book.read(defaults) ?? Book()
        var groups: [String: [String]] = [:]
        for setting in Self.settings {
            for library in libraries(of: setting, in: book) {
                guard let target = rename(library), target != library else { continue }
                if !(groups[target]?.contains(library) ?? false) { groups[target, default: []].append(library) }
            }
        }
        unsettled = [:]
        guard !groups.isEmpty else { return Moved() }
        let record = PreferencesSync.Record.read(defaults)

        var moved = Moved()
        var unsettled: [String: Set<String>] = [:]
        var writes: [(SyncedSetting, String, PreferenceUnits)] = []
        var carrying: [String: [String: Int?]] = [:]
        var moving: [String: Set<String>] = [:]
        for (target, sources) in groups.sorted(by: { $0.key < $1.key }) {
            let instance = Self.instance(of: target)
            let base = instance.flatMap { record.marfas[$0]?.base } ?? [:]
            settings: for setting in Self.settings {
                guard case .units(let own) = setting.read(defaults, library: target) else {
                    unsettled[target, default: []].insert(setting.key)
                    continue
                }
                let lost = sources.reduce(into: [String: Lost]()) { $0[$1] = book.lost[$1]?[setting.key] }
                if instance == nil, !lost.isEmpty {
                    unsettled[target, default: []].insert(setting.key)
                    continue
                }
                var readings: [(library: String, units: PreferenceUnits)] = [(target, own)]
                for source in sources.sorted() {
                    if case .units(let units) = setting.read(defaults, library: source) {
                        readings.append((source, units))
                    } else {
                        unsettled[target, default: []].insert(setting.key)
                    }
                }
                guard readings.count > 1 else { continue }
                var parts = Set(readings.flatMap(\.units.keys))
                for reading in readings {
                    for (name, stamp) in book.stamps[reading.library] ?? [:] where stamp.hash == nil {
                        if let unit = Self.unit(named: name), setting.owns(unit) { parts.insert(unit) }
                    }
                }
                for (unit, _) in base where setting.owns(unit) && lost.values.contains(where: { $0.covers(Self.name(unit)) }) {
                    parts.insert(unit)
                }
                var merged: PreferenceUnits = [:]
                var entries: [SetAside] = []
                var carried: [String: Int?] = [:]
                for unit in parts.sorted(by: { Self.name($0) < Self.name($1) }) {
                    let name = Self.name(unit)
                    let holders = readings.compactMap { reading -> (library: String, text: String?, order: Int?)? in
                        let stamp = book.stamps[reading.library]?[name]
                        if let text = reading.units[unit] { return (reading.library, text, stamp?.order) }
                        if let stamp, stamp.hash == nil { return (reading.library, nil, stamp.order) }
                        // What the store set aside is unknown, so the Marfa's row stands in for it, as no later value.
                        if lost[reading.library]?.covers(name) == true, let text = base[unit] { return (reading.library, text, nil) }
                        return nil
                    }
                    let dated = holders.filter { $0.order != nil }
                    let winner: (library: String, text: String?, order: Int?)
                    let why: Reason
                    if let latest = dated.max(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
                        winner = latest
                        why = latest.order == 0 ? .lastOpen : .later
                    } else {
                        if instance == nil, Set(holders.compactMap(\.text)).count > 1 {
                            unsettled[target, default: []].insert(setting.key)
                            continue settings
                        }
                        let byName = holders.sorted { $0.library < $1.library }
                        winner = byName.first { $0.text != nil && $0.text == base[unit] } ?? byName[0]
                        why = .unknown
                    }
                    if let text = winner.text { merged[unit] = text }
                    carried[name] = .some(winner.order)
                    let losers = holders.filter { $0.text != winner.text }
                    guard !losers.isEmpty else { continue }
                    entries.append(SetAside(
                        library: target, setting: setting.key, part: Self.describe(unit),
                        kept: .init(library: winner.library, value: winner.text),
                        setAside: losers.map { .init(library: $0.library, value: $0.text) }, why: why))
                }
                moved.setAside += entries
                for reading in readings.dropFirst() {
                    guard let losing = lost[reading.library] else { continue }
                    moved.unreadable.append(Unreadable(
                        library: reading.library, setting: setting.key,
                        parts: losing.parts.map { $0.compactMap { Self.unit(named: $0).map(Self.describe) }.sorted() }, stored: losing.stored))
                }
                carrying[target, default: [:]].merge(carried) { _, later in later }
                writes.append((setting, target, merged))
                for reading in readings.dropFirst() {
                    writes.append((setting, reading.library, [:]))
                    moving[setting.key, default: []].insert(reading.library)
                    if !(moved.libraries[target]?.contains(reading.library) ?? false) {
                        moved.libraries[target, default: []].append(reading.library)
                    }
                }
            }
        }
        self.unsettled = unsettled
        if !unsettled.isEmpty {
            Telemetry.logger(.sync).error("Settings kept for a library under an earlier name could not be read or decided, so they stay there for now")
        }
        guard !writes.isEmpty else { return Moved() }
        if !moved.setAside.isEmpty || !moved.unreadable.isEmpty {
            do {
                moved.file = try saveAside(moved.setAside, moved.unreadable)
            } catch {
                // Nothing moved, so none of it syncs until it does.
                for (setting, library, _) in writes where moving[setting.key]?.contains(library) != true {
                    self.unsettled[library, default: []].insert(setting.key)
                }
                throw error
            }
        }
        for (setting, library, units) in writes { setting.write(units, to: defaults, library: library) }
        note(carrying: carrying, moving: moving)
        if moved.setAside.contains(where: { $0.why == .unknown }) {
            Telemetry.logger(.sync).error("Settings kept for one library under two names differed with nothing to say which was later")
        }
        return moved
    }

    private func saveAside(_ entries: [SetAside], _ unreadable: [Unreadable]) throws(Failure) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let date = Date.now
        let url = aside.appending(path: "\(formatter.string(from: date)) \(UUID().uuidString.prefix(8)).json", directoryHint: .notDirectory)
        let file = File(
            about: "Settings this Mac kept for one library under more than one name, which the app joined. For each part, "
                + "\"kept\" is the value used now and \"setAside\" the values it replaced, as JSON text. To use one, "
                + "choose it again in the app. \"unreadable\" holds, as they were stored, the settings a name held that "
                + "the app could not read and set aside, for which the Marfa's values were kept. The app never removes this file.",
            date: date, build: build, settings: entries, unreadable: unreadable)
        do {
            try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            throw .notSetAside
        }
        return url
    }

    // MARK: Names

    /// The Marfa instance a library's name holds, where it is named by one.
    nonisolated static func instance(of library: String) -> String? {
        guard library.hasPrefix("marfa:") else { return nil }
        let name = String(library.dropFirst("marfa:".count))
        guard !name.isEmpty, !name.hasPrefix(MarfaHost.copyPrefix), !name.contains("://") else { return nil }
        return name
    }

    private nonisolated static func unit(named name: String) -> PreferenceUnit? {
        try? JSONDecoder().decode(PreferenceUnit.self, from: Data(name.utf8))
    }

    private nonisolated static func name(_ unit: PreferenceUnit) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(unit)).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: unit)
    }

    private nonisolated static func describe(_ unit: PreferenceUnit) -> String {
        switch unit {
        case .member(let field, let name): "\(field.rawValue).\(name)"
        case .row(let table, let setting, let key): "\(table.rawValue).\(setting).\(key)"
        }
    }

    private nonisolated static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
