import Foundation

/// A copy of this Mac's settings saved before something replaced them all at once, which Restore Earlier Settings… brings
/// back.
nonisolated struct RestorePoint: Equatable, Identifiable, Sendable {
    /// What was about to replace the settings.
    enum Reason: String, CaseIterable, Codable, Sendable {
        /// The first sync on this Mac made the Marfa's settings from this Mac's.
        case firstSync
        /// This Mac took the settings another Mac keeps in the Marfa.
        case adoption
        case reset
        case `import`
        /// Another Marfa's settings were loaded.
        case switching
        /// An earlier restore point was brought back, so the restore can be undone.
        case restoring

        /// What the point was saved before, as Restore Earlier Settings… lists it beside the date.
        var title: String {
            switch self {
            case .firstSync: String(localized: "Before First Sync")
            case .adoption: String(localized: "Before Taking Another Mac’s Settings")
            case .reset: String(localized: "Before Reset")
            case .import: String(localized: "Before Import")
            case .switching: String(localized: "Before Switching Marfa")
            case .restoring: String(localized: "Before Restoring")
            }
        }
    }

    /// The point's file name without its extension.
    let id: String
    let date: Date
    let reason: Reason
}

/// This Mac's settings exactly as the app's own defaults hold them: every key in `MacSettings.keys` and each key under
/// `MacSettings.prefixes`, each value as a binary property list, so a date, data, a dictionary of any shape and a number
/// JSON cannot hold all come back as they were. Only the app's persistent domain is read, never a value the defaults
/// inherit from the arguments, the global domain or the registration domain, so a restore never makes a system setting
/// the app's own. A setting kept for each server holds every server's entry, a value its store cannot read is held as it
/// is, and the settings that stay on this Mac are held too, so a restore puts back whatever Reset, an import or a sync
/// step replaced.
nonisolated struct SettingsSnapshot: Equatable, Sendable {
    /// Each value as a binary property list, by defaults key.
    let values: [String: Data]

    init(values: [String: Data]) { self.values = values }

    /// The settings `domain`, the persistent domain `defaults` writes, holds. Throws `.notSaved` where a value cannot be
    /// kept as a property list, so no point is saved that would lose it.
    @MainActor init(of defaults: UserDefaults, domain: String) throws(RestorePoints.Failure) {
        var values: [String: Data] = [:]
        for (key, value) in Self.covered(in: defaults, domain: domain) {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else {
                throw .notSaved
            }
            values[key] = data
        }
        self.values = values
    }

    /// The value the snapshot holds for `key`, as the defaults keep it.
    func value(forKey key: String) -> Any? {
        values[key].flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
    }

    /// Two snapshots are the same where they hold the same values, however each was written.
    static func == (lhs: SettingsSnapshot, rhs: SettingsSnapshot) -> Bool {
        guard lhs.values.keys == rhs.values.keys, let left = lhs.decoded(), let right = rhs.decoded() else {
            return lhs.values == rhs.values
        }
        return NSDictionary(dictionary: left).isEqual(to: right)
    }

    /// Every value as the defaults keep it, or nil where any cannot be read.
    private func decoded() -> [String: Any]? {
        var decoded: [String: Any] = [:]
        for (key, data) in values {
            guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
            decoded[key] = value
        }
        return decoded
    }

    /// Every covered key `domain` holds, with its value.
    @MainActor static func covered(in defaults: UserDefaults, domain: String) -> [String: Any] {
        (defaults.persistentDomain(forName: domain) ?? [:]).filter { isCovered($0.key) }
    }

    @MainActor static func isCovered(_ key: String) -> Bool {
        MacSettings.keys.contains(key) || MacSettings.prefixes.contains(where: key.hasPrefix)
    }

    /// Each value as the defaults keep it, or nil where any cannot be read, so nothing is written from a point that cannot
    /// be put back whole. A key the snapshot does not cover is left out.
    @MainActor func checked() -> [String: Any]? {
        decoded()?.filter { Self.isCovered($0.key) }
    }

    /// Makes `domain`, the persistent domain `defaults` writes, hold `checked` (from `checked()`) for every covered key:
    /// each key it lacks is removed.
    @MainActor static func write(_ checked: [String: Any], to defaults: UserDefaults, domain: String) {
        for key in Set(covered(in: defaults, domain: domain).keys).union(checked.keys) {
            if let value = checked[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}

/// The restore points, each one JSON file in a folder of its own: a `SettingsSnapshot`, each value in base64, with the
/// reason, the date and the app's build. The newest `kept` are kept, and a point the same in reason and settings as the
/// newest is not saved again, so a step that runs again after a retry never pushes a real point out.
///
/// A file is named for the moment it was saved, in milliseconds, so the names order the points without reading them.
nonisolated final class RestorePoints: Sendable {
    static let kept = 10

    let folder: URL
    /// Whether the folder goes when the last reference to these points does.
    private let isTemporary: Bool

    init(folder: URL) {
        self.folder = folder
        isTemporary = false
    }

    private init(temporary folder: URL) {
        self.folder = folder
        isTemporary = true
    }

    deinit {
        if isTemporary { try? FileManager.default.removeItem(at: folder) }
    }

    /// The app's own, in its Application Support folder.
    static var standard: RestorePoints {
        RestorePoints(folder: AppPaths.applicationSupport.appending(path: "Restore Points", directoryHint: .isDirectory))
    }

    /// New points in a folder of their own, removed with them, for a library that is not the person's own, as the unit
    /// tests' and previews' are, so no two ever see each other's points.
    static func temporary() -> RestorePoints {
        RestorePoints(temporary: AppPaths.temporary("Restore Points \(UUID().uuidString)"))
    }

    enum Failure: Error, Equatable {
        /// The point could not be written.
        case notSaved
        /// The point is gone or cannot be read.
        case unreadable
    }

    /// The points that can be read, newest first. A file that cannot be read is left out.
    func list() -> [RestorePoint] {
        names().compactMap { name in
            guard let stored = try? read(name) else { return nil }
            return RestorePoint(id: name, date: stored.date, reason: stored.reason)
        }
    }

    /// The settings `point` holds.
    func snapshot(of point: RestorePoint.ID) throws(Failure) -> SettingsSnapshot {
        guard names().contains(point), let stored = try? read(point) else { throw .unreadable }
        return SettingsSnapshot(values: stored.settings)
    }

    /// Saves `snapshot` as the newest point and removes the oldest beyond `kept`. Answers nil, and saves nothing, where
    /// the newest point already holds the same reason and settings.
    @discardableResult
    func save(_ snapshot: SettingsSnapshot, reason: RestorePoint.Reason, build: String, date: Date = .now) throws(Failure)
        -> RestorePoint?
    {
        let names = names()
        if let newest = names.first, let stored = try? read(newest), stored.reason == reason,
           SettingsSnapshot(values: stored.settings) == snapshot
        {
            return nil
        }
        // A later name than the newest's, so two points saved in the same millisecond keep their order.
        let moment = max(Int64((date.timeIntervalSince1970 * 1000).rounded(.down)), (names.first.flatMap(Self.moment) ?? -1) + 1)
        let name = String(format: "%015lld", moment) + "-" + UUID().uuidString.prefix(8).lowercased()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let stored = Stored(reason: reason, date: date, build: build, settings: snapshot.values)
            try encoder.encode(stored).write(to: url(name), options: .atomic)
        } catch {
            throw .notSaved
        }
        for old in ([name] + names).dropFirst(Self.kept) { try? FileManager.default.removeItem(at: url(old)) }
        return RestorePoint(id: name, date: date, reason: reason)
    }

    // MARK: Files

    private struct Stored: Codable {
        let reason: RestorePoint.Reason
        let date: Date
        let build: String
        let settings: [String: Data]
    }

    private func url(_ name: String) -> URL { folder.appending(path: "\(name).json", directoryHint: .notDirectory) }

    /// The points' names, newest first; a file not named as a point is not one.
    private func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { Self.moment($0) != nil }
            .sorted(by: >)
    }

    private static func moment(_ name: String) -> Int64? {
        let parts = name.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 15 else { return nil }
        return Int64(parts[0])
    }

    private func read(_ name: String) throws -> Stored {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Stored.self, from: Data(contentsOf: url(name)))
    }
}
