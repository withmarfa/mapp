import CryptoKit
import Foundation
import Marfa

/// The Marfa server a library reads from, by its address.
nonisolated struct MarfaConnection: Hashable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        /// Not an http or https address with a host, or one carrying a user or password.
        case notAServer
    }

    /// Scheme and host in lower case and no trailing slash. An address read as it was saved keeps a port the scheme
    /// already means, since the copy and the discard marks are named by that exact text; one the person types drops
    /// it (`init(typed:)`). Compare connections with `sameServer(as:)`, never `==`, where the question is whether two
    /// addresses are one server.
    let address: URL

    /// An address as it was saved, which names its copy by the text it was kept as.
    init(address text: String) throws(Problem) {
        try self.init(text, dropsDefaultPort: false)
    }

    /// An address the person typed: it leaves out a port the scheme already means (443 for https, 80 for http), so
    /// one server is one address however it was typed, and the package, which names a server by its origin the same
    /// way, keeps one sign-in for it.
    init(typed text: String) throws(Problem) {
        try self.init(text, dropsDefaultPort: true)
    }

    /// Whether `other` names the same server: the same address once a port the scheme already means is left out.
    func sameServer(as other: MarfaConnection) -> Bool {
        Self.origin(address) == Self.origin(other.address)
    }

    private static func origin(_ address: URL) -> URL {
        guard var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else { return address }
        dropDefaultPort(&components)
        return components.url ?? address
    }

    private static func dropDefaultPort(_ components: inout URLComponents) {
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
    }

    private init(_ text: String, dropsDefaultPort: Bool) throws(Problem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { throw .notAServer }
        components.scheme = scheme
        components.host = host.lowercased()
        if dropsDefaultPort { Self.dropDefaultPort(&components) }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let address = components.url else { throw .notAServer }
        self.address = address
    }

    /// Throws only for an address holding a user or password, which `init(address:)` already refuses.
    func server(key: String) throws -> Server {
        try Server(url: address, key: key)
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
