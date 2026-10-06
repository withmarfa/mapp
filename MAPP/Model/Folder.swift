import CryptoKit
import Foundation

/// A folder of notes: a directory at the top of the notes folder, named as the directory is. Its identifier
/// shares the items' space, since the ledger keeps folders beside notes and files and a place names a folder by
/// an item identifier.
nonisolated struct Folder: Identifiable, Hashable {
    let id: ItemID
    var name: String

    init(id: ItemID = .mint(), name: String) {
        self.id = id
        self.name = name
    }
}

extension UUID {
    /// The same identifier for the same text on every launch.
    nonisolated init(stableFrom text: String) {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
