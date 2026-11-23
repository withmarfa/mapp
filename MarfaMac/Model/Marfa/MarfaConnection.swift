import CryptoKit
import Foundation
import Marfa

/// The Marfa server a library reads from, by its address.
nonisolated struct MarfaConnection: Hashable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        /// Not an http or https address with a host, or one carrying a user or password.
        case notAServer
    }

    /// Scheme and host in lower case and no trailing slash, otherwise the address as it was entered: the copy and the
    /// discard marks are named by this exact text, so `https://host` and `https://host:443` are two copies. Compare
    /// connections with `sameServer(as:)`, never `==`, where the question is whether two addresses are one server.
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

    /// Whether `other` names the same server: the same address once a port the scheme already means is left out. The
    /// package keys the sign-in by this origin, so two spellings share one sign-in but keep two copies.
    func sameServer(as other: MarfaConnection) -> Bool {
        Self.origin(address) == Self.origin(other.address)
    }

    private static func origin(_ address: URL) -> URL {
        guard var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else { return address }
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.url ?? address
    }

    /// Throws only for an address holding a user or password, which `init(address:)` already refuses.
    func server(key: String) throws -> Server {
        try Server(url: address, key: key)
    }
}

/// Where a Marfa library's working copy lives: in the app's own storage, one directory for each server address.
nonisolated struct MarfaStoreLocation: Hashable, Sendable {
    /// This copy's working copies. Named for the bundle identifier, never `Marfa`, which is the command line's folder.
    static let applicationSupport = AppPaths.applicationSupport

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
