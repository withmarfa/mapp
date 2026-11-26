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

/// What a store or the sync reads of a stored setting: the bytes of its JSON, whether the defaults keep it as data or as
/// text, so both read the same value the same way. Another kind of value gives bytes that no store reads, so it is set aside
/// whole rather than written over.
nonisolated enum StoredBytes {
    static func read(_ defaults: UserDefaults, _ key: String) -> Data? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        if let data = stored as? Data { return data }
        if let text = stored as? String { return Data(text.utf8) }
        return Data(String(describing: stored).utf8)
    }

    static func text(_ defaults: UserDefaults, _ key: String) -> String? {
        read(defaults, key).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Appends `entry` to the set-aside list `list`, unless it already holds it.
    static func setAside(_ entry: Data, under list: String, in defaults: UserDefaults) {
        let kept = defaults.array(forKey: list) as? [Data] ?? []
        guard !kept.contains(entry) else { return }
        defaults.set(kept + [entry], forKey: list)
    }

    /// Appends `entry` to the set-aside list of text `list`, unless it already holds it.
    static func setAside(_ entry: String, under list: String, in defaults: UserDefaults) {
        let kept = defaults.stringArray(forKey: list) ?? []
        guard !kept.contains(entry) else { return }
        defaults.set(kept + [entry], forKey: list)
    }

    /// `entry` as the object `{name: entry}`, so a copy set aside says which entry it was.
    static func keyed(_ name: String, _ entry: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: [name: entry], options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
    }
}

/// A synced map a store keeps as data, read entry by entry. An entry this version cannot read stays as stored until the
/// person's change replaces it, and is then set aside with its key. A stored value that is no map is set aside whole, and
/// the rows the store's write no longer holds are held in the Marfa (`PreferenceHolds`).
nonisolated struct StoredMap<Value> {
    private(set) var readable: [String: Value] = [:]
    private var unread: [String: Any] = [:]
    /// The stored bytes, where they are no map.
    private var whole: Data?

    init(_ defaults: UserDefaults, key: String, decode: (Any) -> Value?) {
        guard let bytes = StoredBytes.read(defaults, key) else { return }
        guard let entries = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            whole = bytes
            return
        }
        for (name, entry) in entries {
            if let value = decode(entry) { readable[name] = value } else { unread[name] = entry }
        }
    }

    /// Stores `entries`, the readable ones after the person's change, beside each unread entry they leave alone; writes
    /// nothing where that is what is stored.
    func save(_ entries: [String: Value], encode: (Value) -> Any, to key: String, setAside list: String, in defaults: UserDefaults) {
        var object = entries.mapValues(encode)
        for (name, entry) in unread.sorted(by: { $0.key < $1.key }) {
            if object[name] == nil {
                object[name] = entry
            } else {
                StoredBytes.setAside(StoredBytes.keyed(name, entry), under: list, in: defaults)
            }
        }
        if object.isEmpty {
            if defaults.object(forKey: key) != nil { defaults.removeObject(forKey: key) }
        } else if let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
                  defaults.object(forKey: key) as? Data != data
        {
            defaults.set(data, forKey: key)
        }
        if let whole {
            PreferenceHolds.setAside(whole, under: list, of: key, keys: nil, kept: Array(entries.keys), in: defaults)
        }
    }
}
