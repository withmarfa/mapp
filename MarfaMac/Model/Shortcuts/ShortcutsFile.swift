import Foundation

/// What Export Shortcuts writes and Import Shortcuts reads: the app's own shortcuts as JSON, with the format's name and
/// version so a file that is something else, or from a later version of the app, is refused. It holds every menu command's shortcut as
/// it was, and the shortcuts that work in any app.
nonisolated struct ShortcutsFile: Codable, Equatable, Sendable {
    static let format = "marfa-mac-shortcuts"
    static let version = 1

    let format: String
    let version: Int
    /// A menu command's identifier to its shortcut, or to nothing for a command with none.
    let shortcuts: [String: Shortcut?]
    /// An any-app command's identifier to its shortcut. Optional, so a file without the section still reads.
    let anyApp: [String: Shortcut]?

    init(shortcuts: [String: Shortcut?], anyApp: [String: Shortcut]) {
        format = Self.format
        version = Self.version
        self.shortcuts = shortcuts
        self.anyApp = anyApp
    }

    enum ReadError: Error, Equatable {
        /// Not JSON, or JSON that is not a shortcuts file.
        case notOurs
        /// A shortcuts file written by a later version of the app, which this one does not read.
        case newerVersion
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    /// The shortcuts in `data`, or why it is not a file this version reads.
    static func read(_ data: Data) throws(ReadError) -> ShortcutsFile {
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == format else { throw .notOurs }
        guard header.version <= version else { throw .newerVersion }
        guard header.version == version, let file = try? JSONDecoder().decode(ShortcutsFile.self, from: data) else { throw .notOurs }
        return file
    }
}
