import Foundation

/// A JSON value this version does not interpret, kept as it was read so a store that rewrites its setting loses nothing a
/// later or an earlier copy wrote.
nonisolated enum StoredJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([StoredJSON])
    case object([String: StoredJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([StoredJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: StoredJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The value as JSON text with sorted keys, for text that is set aside.
    var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
}

/// A member name that is not known ahead, for a stored object that keeps the members its type does not name.
nonisolated struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

nonisolated extension KeyedDecodingContainer where K == DynamicKey {
    /// Every member whose name is not in `known`, as it was stored.
    func members(except known: Set<String>) throws -> [String: StoredJSON] {
        var others: [String: StoredJSON] = [:]
        for key in allKeys where !known.contains(key.stringValue) {
            others[key.stringValue] = try decode(StoredJSON.self, forKey: key)
        }
        return others
    }
}
