import Foundation

/// An item's `marfa://` link, Marfa's `app_url`: `marfa://<instance id>/<item id>`, where the instance id is the one
/// `GET /` answers, a lowercase UUID, and the item id a lowercase UUIDv7, the only form `GET /items/{id}` accepts.
/// Only the scheme is case-insensitive. Validate the serialized URL before extracting either ID.
nonisolated struct ItemAppLink: Hashable, Sendable {
    static let scheme = "marfa"

    /// The Marfa the item is in, as its `GET /` names it.
    let instanceID: String
    let item: ItemID

    /// The link to `item` in the Marfa `instanceID` names, or nil where either is not in the form a link holds.
    init?(instanceID: String, item: ItemID) {
        guard Self.isUUID(Array(instanceID.utf8)), Self.isUUIDv7(Array(item.rawValue.utf8)) else { return nil }
        self.instanceID = instanceID
        self.item = item
    }

    /// Judges the text as delivered (`absoluteString`), which Foundation may already have normalized; whatever it
    /// folds yields only ids that are still checked.
    init?(_ url: URL) {
        self.init(parsing: url.absoluteString)
    }

    init?(parsing text: String) {
        let bytes = Array(text.utf8)
        let prefix = Array("\(Self.scheme)://".utf8)
        let hostStart = prefix.count
        let slash = hostStart + Self.uuidLength
        guard bytes.count == slash + 1 + Self.uuidLength,
              zip(bytes, prefix).allSatisfy({ Self.lowercased($0) == $1 }),
              bytes[slash] == UInt8(ascii: "/")
        else { return nil }
        let host = Array(bytes[hostStart..<slash])
        let path = Array(bytes[(slash + 1)...])
        guard Self.isUUID(host), Self.isUUIDv7(path) else { return nil }
        instanceID = String(decoding: host, as: UTF8.self)
        item = ItemID(String(decoding: path, as: UTF8.self))
    }

    /// The link as Marfa writes it, with the scheme in lowercase.
    var url: URL {
        URL(string: "\(Self.scheme)://\(instanceID)/\(item.rawValue)")!
    }

    private static let uuidLength = 36
    private static let hyphens: Set<Int> = [8, 13, 18, 23]

    /// Groups of 8, 4, 4, 4 and 12 lowercase hexadecimal digits joined by hyphens.
    private static func isUUID(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == uuidLength else { return false }
        for (index, byte) in bytes.enumerated() {
            if hyphens.contains(index) {
                guard byte == UInt8(ascii: "-") else { return false }
            } else {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                else { return false }
            }
        }
        return true
    }

    /// A lowercase UUID with `7` first in its third group and `8`, `9`, `a` or `b` first in its fourth, as Marfa's
    /// contract defines a UUIDv7.
    private static func isUUIDv7(_ bytes: [UInt8]) -> Bool {
        isUUID(bytes) && bytes[14] == UInt8(ascii: "7") && Array("89ab".utf8).contains(bytes[19])
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }
}
