import Foundation

/// The whole member is copied on a write to another type. Only its value is decoded for a page.
nonisolated struct PlacementEntry: Sendable, Equatable {
    let text: Substring
    private let value: Substring

    var choice: PagePlacements.Choice? {
        try? JSONDecoder().decode(PagePlacements.Choice.self, from: Data(value.utf8))
    }

    init?(key: String, choice: PagePlacements.Choice) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(choice) else { return nil }
        value = String(decoding: encoded, as: UTF8.self)[...]
        text = (StoredJSON.string(key).text + ":" + value)[...]
    }

    private init(text: Substring, value: Substring) {
        self.text = text
        self.value = value
    }

    private struct Object: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.container(keyedBy: DynamicKey.self)
        }
    }

    /// Foundation checks the object structure. Locate the outer members in the source because decoding and re-encoding
    /// a sibling would change its spelling, including escapes and numbers that this version cannot represent.
    static func read(_ text: String) -> [String: [Self]]? {
        let decoder = JSONDecoder()
        guard (try? decoder.decode(Object.self, from: Data(text.utf8))) != nil else { return nil }
        let scalars = text.unicodeScalars
        guard let open = scalars.firstIndex(of: "{"), let close = scalars.lastIndex(of: "}") else { return nil }
        var start = scalars.index(after: open)
        var valueStart = start
        var key: String?
        var depth = 0
        var quoted = false
        var escaped = false
        var entries: [String: [Self]] = [:]
        for i in scalars[start...close].indices {
            let character = scalars[i]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
                continue
            }
            switch character {
            case "\"": quoted = true
            case "{", "[": depth += 1
            case ":" where depth == 0:
                let name = String(scalars[start..<i])
                guard let decoded = try? decoder.decode(String.self, from: Data(name.utf8)) else { return nil }
                key = decoded
                valueStart = scalars.index(after: i)
            case "," where depth == 0, "}" where i == close:
                if let key {
                    entries[key, default: []].append(Self(text: text[start..<i], value: text[valueStart..<i]))
                }
                key = nil
                start = scalars.index(after: i)
            case "}", "]": depth -= 1
            default: break
            }
        }
        return entries
    }
}
