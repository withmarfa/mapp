import CryptoKit
import Foundation
import Marfa

/// The Marfa server a library reads from, by its address.
nonisolated struct MarfaConnection: Hashable, Sendable {
    enum Problem: Error, Hashable, Sendable {
        case notAServer
        /// A stored address with a suffix may have a copy of its own.
        case hasMore
    }

    /// The completed server address. An explicit default port still names its own copy and discard marks.
    let address: URL

    init(address text: String, completing: Bool = true) throws(Problem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let explicit = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
        guard explicit || (completing && !lowercased.hasPrefix("http:") && !lowercased.hasPrefix("https:")),
            !trimmed.contains("\\"), trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw .notAServer }

        let candidate = explicit ? trimmed : "https://" + trimmed
        let authority = candidate.dropFirst(lowercased.hasPrefix("http://") ? 7 : 8)
            .prefix { !"/?#".contains($0) }
        guard let match = authority.wholeMatch(of: #/(?:\[[0-9A-Fa-f:.]+\]|[\p{L}\p{M}\p{N}._-]+)(?::([0-9]+))?/#),
            var components = URLComponents(string: candidate),
            let host = components.host?.lowercased(), let scheme = components.scheme?.lowercased()
        else { throw .notAServer }
        if let port = match.output.1 {
            guard let number = Int(port), (1...65535).contains(number), components.port == number else { throw .notAServer }
        }

        if host.hasPrefix("[") {
            guard IPAddress(literal: host)?.bytes.count == 16 else { throw .notAServer }
        } else {
            let name = host.hasSuffix(".") ? host.dropLast() : host[...]
            guard !name.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.isEmpty }) else { throw .notAServer }
            if !explicit, IPAddress(literal: host) != nil {
                let octets = host.split(separator: ".", omittingEmptySubsequences: false)
                guard octets.count == 4,
                    octets.allSatisfy({ octet in UInt8(octet).map { String($0) == octet } == true })
                else { throw .notAServer }
            }
        }

        if !completing {
            guard ["", "/"].contains(components.percentEncodedPath), components.query == nil, components.fragment == nil
            else { throw .hasMore }
        }
        components.scheme = !explicit && Self.isLoopback(host) ? "http" : scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
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

    /// Whether the server runs on this Mac: an address that names the loopback, as `localhost`, an IPv4 address in `127.0.0.0/8` and `::1` do.
    var isOnThisMac: Bool {
        guard let host = address.host(percentEncoded: false)?.lowercased() else { return false }
        return Self.isLoopback(host)
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host == "[::1]" || Self.isLoopbackIPv4(host)
    }

    private static func isLoopbackIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0] == "127" && parts.allSatisfy { !$0.isEmpty && $0.count <= 3 && UInt8($0) != nil }
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
