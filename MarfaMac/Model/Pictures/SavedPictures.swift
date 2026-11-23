import Foundation

/// A picture a connector saved as a file attached to an item: the file's `source_url` says which web address it was
/// saved from. Nothing here names a type, since the match is on the attachment and its address alone.
nonisolated enum SavedPictures {
    /// The `core.file` field that holds the web address a file was sourced from.
    static let sourceField = "source_url"

    /// Whether two web addresses name the same picture. The scheme and the host are the same in any case, and the
    /// default port is the same as none; the path and the query are compared exactly as written, so a trailing slash,
    /// another case or a longer path is another picture. The fragment is ignored, since no website is sent it.
    static func same(_ first: URL, _ second: URL) -> Bool {
        guard let first = parts(of: first), let second = parts(of: second) else { return false }
        return first == second
    }

    private struct Parts: Equatable {
        let scheme: String
        let user: String?
        let password: String?
        let host: String
        let port: Int
        let path: String
        let query: String?
    }

    private static func parts(of url: URL) -> Parts? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), let host = components.percentEncodedHost?.lowercased(), !host.isEmpty
        else { return nil }
        let path = components.percentEncodedPath
        return Parts(
            scheme: scheme, user: components.percentEncodedUser, password: components.percentEncodedPassword, host: host,
            port: components.port ?? (scheme == "https" ? 443 : 80), path: path.isEmpty ? "/" : path,
            query: components.percentEncodedQuery)
    }
}

/// What decides how a saved picture is drawn, so the page draws the pictures again when this changes.
nonisolated struct SavedPictureState: Hashable, Sendable {
    let file: ItemID
    let address: String
    let trashed: Bool
    let version: ItemVersion
}

extension ItemLibrary {
    /// The files attached to `item` that were saved from `address`, in the order they are tried: those not in the bin,
    /// the oldest first. A file attached to another item is never one of them, whatever its address.
    func savedPictures(of item: ItemID, at address: URL) -> [ItemID] {
        attachments(of: item).compactMap { self.item($0) }
            .filter { $0.state != .trashed && Self.source(of: $0).map { SavedPictures.same($0, address) } == true }
            .sorted { ($0.created, $0.id.rawValue) < ($1.created, $1.id.rawValue) }
            .map(\.id)
    }

    /// Every attachment of `item` that has a `source_url`, in the bin or not, as the page's pictures depend on them.
    func savedPictureStates(of item: ItemID) -> [SavedPictureState] {
        attachments(of: item).compactMap { id -> SavedPictureState? in
            guard let file = self.item(id), let address = file.value(of: SavedPictures.sourceField)?.string, !address.isEmpty
            else { return nil }
            return SavedPictureState(file: id, address: address, trashed: file.state == .trashed, version: file.version)
        }
        .sorted { $0.file.rawValue < $1.file.rawValue }
    }

    private static func source(of file: Item) -> URL? {
        file.value(of: SavedPictures.sourceField)?.string.flatMap { URL(string: $0) }
    }
}
