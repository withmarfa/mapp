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

/// A stored JSON object whose entries a store decodes one by one, so an entry this version cannot read, such as one a later
/// version wrote, stays as it was stored beside the readable ones instead of costing them.
nonisolated enum StoredEntries {
    /// Each entry of the object in `data` that decodes as `Value`, and the others as they were stored; nil where `data`
    /// is no JSON object.
    static func decode<Value: Decodable>(_ data: Data, as _: Value.Type) -> (readable: [String: Value], unread: [String: StoredJSON])? {
        if let all = try? JSONDecoder().decode([String: Value].self, from: data) { return (all, [:]) }
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var readable: [String: Value] = [:]
        var unread: [String: StoredJSON] = [:]
        for (key, entry) in entries {
            guard let text = try? JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed) else { return nil }
            if let value = try? JSONDecoder().decode(Value.self, from: text) {
                readable[key] = value
            } else if let kept = try? JSONDecoder().decode(StoredJSON.self, from: text) {
                unread[key] = kept
            } else {
                return nil
            }
        }
        return (readable, unread)
    }

    /// The object holding `readable` and, for a key it lacks, the entry `unread` kept, with sorted keys. Each readable
    /// entry is written as the encoder writes it alone, so keeping an unread one changes no other entry's text.
    static func encode<Value: Encodable>(_ readable: [String: Value], keeping unread: [String: StoredJSON]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard !unread.isEmpty else { return try? encoder.encode(readable) }
        var data = Data("{".utf8)
        for (index, key) in Set(readable.keys).union(unread.keys).sorted().enumerated() {
            guard let name = try? encoder.encode(key),
                  let value = readable[key].flatMap({ try? encoder.encode($0) }) ?? unread[key].flatMap({ try? encoder.encode($0) })
            else { return nil }
            if index > 0 { data.append(contentsOf: Array(",".utf8)) }
            data.append(name)
            data.append(contentsOf: Array(":".utf8))
            data.append(value)
        }
        data.append(contentsOf: Array("}".utf8))
        return data
    }
}
