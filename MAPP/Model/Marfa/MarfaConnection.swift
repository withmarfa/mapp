import CryptoKit
import Foundation
import Marfa

/// The Marfa server a library reads from, by its address.
nonisolated struct MarfaConnection: Hashable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        /// Not an http or https address with a host, or one carrying a user or password.
        case notAServer
    }

    /// Scheme and host in lower case and no trailing slash, so one server is one address however it was typed.
    let address: URL

    init(address text: String) throws(Problem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { throw .notAServer }
        components.scheme = scheme
        components.host = host.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let address = components.url else { throw .notAServer }
        self.address = address
    }

    func server(key: String) -> Server {
        Server(url: address, key: key)
    }
}

/// Where a Marfa library's working copy lives: in the app's own storage, one directory for each server address.
nonisolated struct MarfaStoreLocation: Hashable, Sendable {
    static let applicationSupport = URL.applicationSupportDirectory.appending(path: "Marfa", directoryHint: .isDirectory)

    let root: URL

    init(root: URL = Self.applicationSupport) {
        self.root = root
    }

    /// A store refuses a server other than the one it was hydrated from, so each address keeps its own.
    func directory(for connection: MarfaConnection) -> URL {
        let digest = SHA256.hash(data: Data(connection.address.absoluteString.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return root.appending(path: name, directoryHint: .isDirectory)
    }

    func store(for connection: MarfaConnection) -> URL {
        directory(for: connection).appending(path: "copy.sqlite", directoryHint: .notDirectory)
    }
}
