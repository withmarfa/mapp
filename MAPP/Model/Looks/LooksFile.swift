import Foundation

/// The file Export Looks writes and Import Looks reads: every look of one server's types as JSON, keyed by type
/// identifier, with the format's name and version so a file that is something else is refused. It names no server.
nonisolated struct LooksFile: Codable, Equatable, Sendable {
    static let format = "mapp-looks"
    static let version = 1

    let format: String
    let version: Int
    let looks: [String: TypeLook]

    init(looks: [TypeID: TypeLook]) {
        format = Self.format
        version = Self.version
        self.looks = Dictionary(looks.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The looks as the file holds them, each as a complete choice.
    var choices: [TypeID: TypeLookChoice] {
        Dictionary(looks.map { (TypeID($0.key), TypeLookChoice($0.value)) }, uniquingKeysWith: { first, _ in first })
    }

    /// The file's text: readable, with its keys in a fixed order so two exports of one set of looks are alike.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The looks in `data`, or nil where it is not a looks file this version reads: not JSON, not this format, another
    /// version, or a look with a word it does not know.
    static func read(_ data: Data) -> LooksFile? {
        guard let file = try? JSONDecoder().decode(LooksFile.self, from: data),
              file.format == format, file.version == version else { return nil }
        return file
    }
}
