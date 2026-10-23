import Foundation

// String raw values give these a single-string Codable form through RawRepresentable's own conformance, so a
// restored window or a dragged reference reads as the id itself.

/// An item's identity, opaque to the app: a source never derives it from a path.
nonisolated struct ItemID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    /// The app names an item before its source answers, and Marfa keeps an id its client mints, if it is a
    /// lowercase UUIDv7: the time in milliseconds, then randomness.
    static func mint(at date: Date = .now) -> ItemID {
        var bytes = UUID().uuid
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        withUnsafeMutableBytes(of: &bytes) { raw in
            for index in 0..<6 { raw[index] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - UInt64(index)))) }
            raw[6] = raw[6] & 0x0F | 0x70
            raw[8] = raw[8] & 0x3F | 0x80
        }
        return ItemID(UUID(uuid: bytes).uuidString.lowercased())
    }
}

nonisolated struct TypeID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    /// The root of the file types: a file and every kind of file below it, which the sidebar reaches through All
    /// Items and search rather than as a type.
    static let file = TypeID("core.file")
}

nonisolated struct EdgeID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Where a files source keeps an item: a folder at the top of the notes folder. A Marfa source has none.
nonisolated struct ContainerID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// The version of an item a reader holds. A files source counts within one session; Marfa's is the server's.
nonisolated struct ItemVersion: RawRepresentable, Hashable, Comparable, Sendable {
    let rawValue: Int64
    init(rawValue: Int64) { self.rawValue = rawValue }
    init(_ rawValue: Int64) { self.rawValue = rawValue }
    static func < (lhs: ItemVersion, rhs: ItemVersion) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct WriteID: Hashable, Sendable {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
