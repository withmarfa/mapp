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
        guard explicit || completing else { throw .notAServer }

        let candidate = explicit ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: candidate),
            let host = components.host?.lowercased(), !host.isEmpty,
            let scheme = components.scheme?.lowercased(), components.user == nil, components.password == nil
        else { throw .notAServer }

        if completing {
            let authority = candidate.dropFirst(scheme == "http" ? 7 : 8).prefix { !"/?#".contains($0) }
            guard !trimmed.contains("\\"), trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
                explicit || (host != "http" && host != "https"),
                Self.isValidAuthority(authority, host: host, port: components.port, explicit: explicit)
            else { throw .notAServer }
        } else {
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

    private static func isValidAuthority(_ authority: Substring, host: String, port: Int?, explicit: Bool) -> Bool {
        guard let match = authority.wholeMatch(of: #/(?:\[[0-9A-Fa-f:.]+\]|[\p{L}\p{M}\p{N}._-]+)(?::([0-9]+))?/#)
        else { return false }
        if let digits = match.output.1 {
            guard let number = Int(digits), (1...65535).contains(number), port == number else { return false }
        }
        if host.hasPrefix("[") { return IPAddress(literal: host)?.bytes.count == 16 }

        let name = host.hasSuffix(".") ? host.dropLast() : host[...]
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !name.isEmpty, labels.allSatisfy({ !$0.isEmpty && $0.first != "-" && $0.last != "-" }) else { return false }
        guard !explicit, IPAddress(literal: host) != nil else { return true }

        // A resolver can read shortened, octal and hexadecimal IPv4 spellings as a different host.
        return labels.count == 4 && labels.allSatisfy { label in UInt8(label).map { String($0) == label } == true }
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
