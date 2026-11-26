import CryptoKit
import Foundation
import os

/// The settings this Mac keeps for each library (`SyncedSetting.isPerServer`): the order each was last written in, and
/// the move of what a library kept under an earlier name to the name it has now (`MarfaHost.currentLibraryKey`).
///
/// Earlier builds named a library by its address as typed, so one Marfa can hold settings under two spellings, or
/// under the address it moved from. A move joins them part by part, so a part only one name held is kept. Where two
/// names held a part differently, the one written later wins, by the order kept here; for values held before this
/// order was kept, the library that was open last wins. Where nothing says which was later, the value the Marfa
/// holds wins, else the first by name, and it is logged. Every value that does not win is first saved in a file beside
/// the restore points that the app never removes; where it cannot be saved, nothing moves.
@MainActor final class LibrarySettings {
    /// The order each part of each library's settings was last written in. Bookkeeping, not a setting.
    nonisolated static let orderKey = "librarySettingsOrder"
    nonisolated static let asideFolderName = "Library Settings Set Aside"
    static let settings = PreferencesMap.synced.filter(\.isPerServer)

    nonisolated struct Book: Codable, Equatable, Sendable {
        var next = 1
        /// By library, then by part (`PreferenceUnit` as JSON).
        var stamps: [String: [String: Stamp]] = [:]

        static func read(_ defaults: UserDefaults) -> Book? {
            defaults.data(forKey: orderKey).flatMap { try? JSONDecoder().decode(Book.self, from: $0) }
        }

        func save(_ defaults: UserDefaults) {
            guard self != Self.read(defaults), let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: orderKey)
        }
    }

    nonisolated struct Stamp: Codable, Equatable, Sendable {
        var hash: String
        /// The write that last changed the part; 0 for the library open when the order began to be kept, and nil for
        /// any other value held then.
        var order: Int?
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

    /// `lastOpen` is the key the library open last was stored under, which wins over other values held before the
    /// order was kept.
    init(defaults: UserDefaults, aside: URL, lastOpen: String?, build: String = PreferencesSync.appBuild) {
        self.defaults = defaults
        self.aside = aside
        self.build = build
        if Book.read(defaults) == nil {
            var book = Book()
            for (library, parts) in held() {
                book.stamps[library] = parts.mapValues { Stamp(hash: $0.hash, order: library == lastOpen ? 0 : nil) }
            }
            if !book.stamps.isEmpty { book.save(defaults) }
            seen = raw()
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

    private func raw() -> [Data?] { Self.settings.map { defaults.data(forKey: $0.key) } }

    /// Every library's parts that can be read, each with its value and the value's hash.
    private func held() -> [String: [String: (unit: PreferenceUnit, text: String, hash: String)]] {
        var held: [String: [String: (unit: PreferenceUnit, text: String, hash: String)]] = [:]
        for setting in Self.settings {
            for library in libraries(of: setting) {
                guard case .units(let units) = setting.read(defaults, library: library) else { continue }
                for (unit, text) in units { held[library, default: [:]][Self.name(unit)] = (unit, text, Self.hash(text)) }
            }
        }
        return held
    }

    /// Stamps each part changed since the last look with the next write's order, or with `carrying`'s order for a
    /// part a move wrote.
    private func note(carrying: [String: [String: Int?]] = [:]) {
        let now = raw()
        guard now != seen || !carrying.isEmpty else { return }
        seen = now
        var book = Book.read(defaults) ?? Book()
        let order = book.next
        var wrote = false
        var stamps: [String: [String: Stamp]] = [:]
        let unreadable = librariesNotRead()
        for library in unreadable { stamps[library] = book.stamps[library] }
        for (library, parts) in held() {
            for (name, part) in parts {
                if let carried = carrying[library]?[name] {
                    stamps[library, default: [:]][name] = Stamp(hash: part.hash, order: carried)
                } else if let stamp = book.stamps[library]?[name], stamp.hash == part.hash {
                    stamps[library, default: [:]][name] = stamp
                } else {
                    stamps[library, default: [:]][name] = Stamp(hash: part.hash, order: order)
                    wrote = true
                }
            }
        }
        if wrote { book.next += 1 }
        book.stamps = stamps
        book.save(defaults)
    }

    /// The libraries some setting holds a value of that cannot be read, whose stamps are kept as they were.
    private func librariesNotRead() -> Set<String> {
        var libraries: Set<String> = []
        for setting in Self.settings {
            for library in self.libraries(of: setting) where setting.read(defaults, library: library) == .unreadable {
                libraries.insert(library)
            }
        }
        return libraries
    }

    private func libraries(of setting: SyncedSetting) -> [String] {
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
            /// The value as JSON text.
            var value: String
        }

        /// The name the settings are kept under now.
        var library: String
        var setting: String
        var part: String
        var kept: Value
        var setAside: [Value]
        var why: Reason
    }

    private nonisolated struct File: Codable {
        var about: String
        var date: Date
        var build: String
        var settings: [SetAside]
    }

    nonisolated struct Moved: Equatable, Sendable {
        /// The names moved from, by the name moved to.
        var libraries: [String: [String]] = [:]
        /// The file the values that did not win were saved in, if any.
        var file: URL?
        var setAside: [SetAside] = []
    }

    /// Moves what each library kept under an earlier name to the name `rename` gives it, nil for a name that stays. A
    /// setting a name holds that cannot be read is not moved from any name, and is tried again at the next move.
    @discardableResult
    func settle(rename: (String) -> String?) throws(Failure) -> Moved {
        note()
        var groups: [String: [String]] = [:]
        for setting in Self.settings {
            for library in libraries(of: setting) {
                guard let target = rename(library), target != library else { continue }
                if !(groups[target]?.contains(library) ?? false) { groups[target, default: []].append(library) }
            }
        }
        guard !groups.isEmpty else { return Moved() }
        let book = Book.read(defaults) ?? Book()
        let record = PreferencesSync.Record.read(defaults)

        var moved = Moved()
        var writes: [(SyncedSetting, String, PreferenceUnits)] = []
        var carrying: [String: [String: Int?]] = [:]
        for (target, sources) in groups.sorted(by: { $0.key < $1.key }) {
            let names = [target] + sources.sorted()
            let base = Self.instance(of: target).flatMap { record.marfas[$0]?.base } ?? [:]
            for setting in Self.settings {
                var readings: [(library: String, units: PreferenceUnits)] = []
                for library in names {
                    guard case .units(let units) = setting.read(defaults, library: library) else {
                        readings = []
                        break
                    }
                    readings.append((library, units))
                }
                guard readings.count == names.count else { continue }
                var merged: PreferenceUnits = [:]
                for unit in Set(readings.flatMap(\.units.keys)).sorted(by: { Self.name($0) < Self.name($1) }) {
                    let holders = readings.compactMap { reading in
                        reading.units[unit].map { (library: reading.library, text: $0, order: book.stamps[reading.library]?[Self.name(unit)]?.order) }
                    }
                    let dated = holders.filter { $0.order != nil }
                    let winner: (library: String, text: String, order: Int?)
                    let why: Reason
                    if let latest = dated.max(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
                        winner = latest
                        why = latest.order == 0 ? .lastOpen : .later
                    } else {
                        winner = holders.first { $0.text == base[unit] } ?? holders[0]
                        why = .unknown
                    }
                    merged[unit] = winner.text
                    carrying[target, default: [:]][Self.name(unit)] = .some(winner.order)
                    let losers = holders.filter { $0.text != winner.text }
                    guard !losers.isEmpty else { continue }
                    moved.setAside.append(SetAside(
                        library: target, setting: setting.key, part: Self.describe(unit),
                        kept: .init(library: winner.library, value: winner.text),
                        setAside: losers.map { .init(library: $0.library, value: $0.text) }, why: why))
                }
                writes.append((setting, target, merged))
                for source in sources { writes.append((setting, source, [:])) }
                for source in sources where !(moved.libraries[target]?.contains(source) ?? false) {
                    moved.libraries[target, default: []].append(source)
                }
            }
        }
        guard !writes.isEmpty else { return Moved() }
        if !moved.setAside.isEmpty { moved.file = try saveAside(moved.setAside) }
        for (setting, library, units) in writes { setting.write(units, to: defaults, library: library) }
        note(carrying: carrying)
        if moved.setAside.contains(where: { $0.why == .unknown }) {
            Telemetry.logger(.sync).error("Settings kept for one library under two names differed with nothing to say which was later")
        }
        return moved
    }

    private func saveAside(_ entries: [SetAside]) throws(Failure) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let date = Date.now
        let url = aside.appending(path: "\(formatter.string(from: date)) \(UUID().uuidString.prefix(8)).json", directoryHint: .notDirectory)
        let file = File(
            about: "Settings this Mac kept for one library under more than one name, which the app joined. For each part, "
                + "\"kept\" is the value used now and \"setAside\" the values it replaced, as JSON text. To use one, "
                + "choose it again in the app. The app never removes this file.",
            date: date, build: build, settings: entries)
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
