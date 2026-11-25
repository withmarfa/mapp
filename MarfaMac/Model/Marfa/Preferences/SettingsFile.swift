import Foundation

nonisolated extension SettingsFile {
    /// A part of this app's settings that Import Settings… offers on its own, named for the Settings page that holds it. Each
    /// field and table of `app.marfa-mac.preferences` belongs to one, so a setting's section follows from where it sits.
    enum Section: String, CaseIterable, Codable, Hashable, Sendable {
        case general, appearance, keyboard, editor, lists, layouts, search, sidebar

        init(_ field: PreferencesField) {
            switch field {
            case .general: self = .general
            case .appearance: self = .appearance
            case .editor: self = .editor
            case .lists: self = .lists
            case .search: self = .search
            }
        }

        init(_ table: PreferencesTable) {
            switch table {
            case .commands: self = .keyboard
            case .types: self = .layouts
            case .views, .places: self = .lists
            case .sidebar: self = .sidebar
            }
        }

        init(_ unit: PreferenceUnit) {
            switch unit {
            case .member(let field, _): self.init(field)
            case .row(let table, _, _): self.init(table)
            }
        }

        /// The section's name, as its Settings page is named.
        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .appearance: String(localized: "Appearance")
            case .keyboard: String(localized: "Keyboard")
            case .editor: String(localized: "Editor")
            case .lists: String(localized: "Lists")
            case .layouts: String(localized: "Layouts")
            case .search: String(localized: "Search")
            case .sidebar: String(localized: "Sidebar")
            }
        }
    }
}

nonisolated extension SyncedSetting {
    /// The section every unit this setting owns belongs to.
    var section: SettingsFile.Section {
        switch place {
        case .member(let field), .serverMember(let field, _): SettingsFile.Section(field)
        case .rows(let table, _, _, _, _, _), .serverRows(let table, _, _), .set(let table, _):
            SettingsFile.Section(table)
        case .sidebar: .sidebar
        }
    }
}

/// What Export Settings… writes and Import Settings… reads: this app's settings as JSON, by section, with the format's
/// name and version so a file that is something else, or from a later version of the app, is refused. A file moves
/// between Macs and Marfas, so it holds settings as they sit in a Marfa; a restore point, which stays on this Mac, holds
/// the defaults themselves (`SettingsSnapshot`).
///
/// The values are the sync's own (`PreferenceUnit` to JSON text, as `SyncedSetting.read` gives and `SyncedSetting.write`
/// takes), so a setting kept for each server carries only the entry of the library it was read for. A setting this Mac
/// cannot read is left out.
nonisolated struct SettingsFile: Codable, Equatable, Sendable {
    static let format = "marfa-mac-settings"
    static let version = 1

    /// The app that wrote the file (`PreferencesSync.appBuild`).
    let build: String
    let date: Date
    /// The settings of each section that holds any.
    let sections: [Section: PreferenceUnits]

    init(units: PreferenceUnits, build: String, date: Date) {
        self.build = build
        self.date = date
        var sections: [Section: PreferenceUnits] = [:]
        for (unit, text) in units { sections[Section(unit), default: [:]][unit] = text }
        self.sections = sections
    }

    /// The settings of `chosen`, by where they sit.
    func units(in chosen: Set<Section>) -> PreferenceUnits {
        var units: PreferenceUnits = [:]
        for section in chosen { units.merge(sections[section] ?? [:]) { first, _ in first } }
        return units
    }

    enum ReadError: Error, Equatable {
        /// Not JSON, or JSON that is not a settings file.
        case notOurs
        /// A settings file written by a later version of the app, which this one does not read.
        case newerVersion
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// The settings in `data`, or why it is not a file this version reads.
    static func read(_ data: Data) throws(ReadError) -> SettingsFile {
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == format else { throw .notOurs }
        guard header.version <= version else { throw .newerVersion }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(SettingsFile.self, from: data) else { throw .notOurs }
        return file
    }

    // MARK: The file's shape

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    /// One section as written: each field's members, and each table's rows by setting and key, every value as JSON text.
    private struct Stored: Codable {
        var fields: [String: [String: String]] = [:]
        var tables: [String: [String: [String: String]]] = [:]
    }

    private enum CodingKeys: String, CodingKey { case format, version, build, date, sections }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(Self.version, forKey: .version)
        try container.encode(build, forKey: .build)
        try container.encode(date, forKey: .date)
        var stored: [String: Stored] = [:]
        for (section, units) in sections {
            var part = Stored()
            for (unit, text) in units {
                switch unit {
                case .member(let field, let key): part.fields[field.rawValue, default: [:]][key] = text
                case .row(let table, let setting, let key): part.tables[table.rawValue, default: [:]][setting, default: [:]][key] = text
                }
            }
            stored[section.rawValue] = part
        }
        try container.encode(stored, forKey: .sections)
    }

    /// The section a file names is only how it was written: each setting is placed by where it sits. The fields and
    /// tables never change (`PreferencesType`), so a file that names another is not one of ours.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .format) == Self.format,
              try container.decode(Int.self, forKey: .version) == Self.version
        else { throw DecodingError.dataCorruptedError(forKey: .format, in: container, debugDescription: "Not this version's settings") }
        let build = try container.decode(String.self, forKey: .build)
        let date = try container.decode(Date.self, forKey: .date)
        var units: PreferenceUnits = [:]
        for part in try container.decode([String: Stored].self, forKey: .sections).values {
            for (name, members) in part.fields {
                guard let field = PreferencesField(rawValue: name) else {
                    throw DecodingError.dataCorruptedError(forKey: .sections, in: container, debugDescription: "Unknown field")
                }
                for (key, text) in members { units[.member(field, key)] = text }
            }
            for (name, settings) in part.tables {
                guard let table = PreferencesTable(rawValue: name) else {
                    throw DecodingError.dataCorruptedError(forKey: .sections, in: container, debugDescription: "Unknown table")
                }
                for (setting, rows) in settings {
                    for (key, text) in rows { units[.row(table, setting: setting, key: key)] = text }
                }
            }
        }
        self.init(units: units, build: build, date: date)
    }
}
