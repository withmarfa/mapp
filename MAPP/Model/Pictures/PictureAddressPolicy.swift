import Darwin
import Foundation
import Synchronization

/// An address on the internet, as four or sixteen bytes.
nonisolated struct IPAddress: Hashable, Sendable {
    let bytes: [UInt8]

    /// Reads a numeric address: dotted decimal, the old forms with fewer parts or hexadecimal and octal parts that a
    /// system resolver also takes (`2130706433`, `0x7f.1`), or colons for the sixteen-byte kind. Nil for a name.
    init?(literal text: String) {
        var text = text
        if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()) }
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        var six = in6_addr()
        if inet_pton(AF_INET6, text, &six) == 1 {
            bytes = withUnsafeBytes(of: &six) { Array($0) }
            return
        }
        guard !text.isEmpty, text.allSatisfy({ $0.isHexDigit || $0 == "x" || $0 == "X" || $0 == "." }) else { return nil }
        var four = in_addr()
        guard inet_aton(text, &four) != 0 else { return nil }
        bytes = withUnsafeBytes(of: &four) { Array($0) }
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Whether a page on the internet could be at this address. Everything a home or office network, the machine
    /// itself or the address space's reserved ranges use is not: those are where a request made on a note's behalf
    /// would reach something the note's writer could not.
    var isPublic: Bool {
        switch bytes.count {
        case 4: return Self.isPublic(four: bytes)
        case 16: return Self.isPublic(sixteen: bytes)
        default: return false
        }
    }

    private static func isPublic(four b: [UInt8]) -> Bool {
        switch (b[0], b[1], b[2]) {
        case (0, _, _), (10, _, _), (127, _, _): return false
        case (100, 64...127, _): return false          // shared address space
        case (169, 254, _): return false               // link-local
        case (172, 16...31, _): return false
        case (192, 0, 0), (192, 0, 2): return false    // protocol assignments, documentation
        case (192, 88, 99): return false               // 6to4 relay anycast
        case (192, 168, _): return false
        case (198, 18...19, _): return false           // benchmarking
        case (198, 51, 100), (203, 0, 113): return false
        case (224..., _, _): return false              // multicast, reserved, broadcast
        default: return true
        }
    }

    private static func isPublic(sixteen b: [UInt8]) -> Bool {
        let leadingZeros = b.prefix(10).allSatisfy { $0 == 0 }
        // Unspecified, loopback, and the old IPv4-compatible form.
        if leadingZeros, b[10] == 0, b[11] == 0 { return false }
        // IPv4-mapped: the four bytes at the end decide.
        if leadingZeros, b[10] == 0xFF, b[11] == 0xFF { return isPublic(four: Array(b[12..<16])) }
        // IPv4-translated (`::ffff:0:a.b.c.d`, RFC 2765), the same: the four bytes at the end decide.
        if b.prefix(8).allSatisfy({ $0 == 0 }), b[8] == 0xFF, b[9] == 0xFF, b[10] == 0, b[11] == 0 {
            return isPublic(four: Array(b[12..<16]))
        }
        // NAT64: the address a name server makes for an IPv4 one.
        if Array(b[0..<12]) == [0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0] { return isPublic(four: Array(b[12..<16])) }
        if b[0] == 0x00, b[1] == 0x64, b[2] == 0xFF, b[3] == 0x9B, b[4] == 0x00, b[5] == 0x01 { return false }
        // 6to4 carries an IPv4 address after the prefix.
        if b[0] == 0x20, b[1] == 0x02 { return isPublic(four: Array(b[2..<6])) }
        // Teredo.
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0, b[3] == 0 { return false }
        // Documentation.
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x0D, b[3] == 0xB8 { return false }
        if b[0] & 0xFE == 0xFC { return false }                       // unique local
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 || b[1] & 0xC0 == 0xC0 { return false } // link-local, site-local
        if b[0] == 0xFF { return false }                              // multicast
        return true
    }
}

/// Which web addresses a picture may be fetched from, checked before the first request and again at every redirect.
nonisolated enum PictureAddressPolicy {
    /// The addresses a name answers with.
    typealias Resolver = @Sendable (String) async throws -> [IPAddress]

    /// Asks the system's resolver.
    static let system: Resolver = { name in
        try await PictureAddressPolicy.lookup(name)
    }

    /// `getaddrinfo` blocks until the system's resolver answers, which can be many seconds, so it runs on queues of
    /// its own and never holds a thread of Swift's cooperative pool.
    private static let lookups = DispatchQueue(label: "com.withmarfa.mapp.picture-lookup", qos: .utility, attributes: .concurrent)

    private static func lookup(_ name: String) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            lookups.async {
                continuation.resume(with: Result { try addresses(of: name) })
            }
        }
    }

    private static func addresses(of name: String) throws -> [IPAddress] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &found) == 0, let first = found else { throw PictureFailure.unresolved }
        defer { freeaddrinfo(first) }
        var addresses: [IPAddress] = []
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let entry = next {
            if let socket = entry.pointee.ai_addr {
                switch Int32(entry.pointee.ai_family) {
                case AF_INET:
                    let bytes = socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                        withUnsafeBytes(of: pointer.pointee.sin_addr) { Array($0) }
                    }
                    addresses.append(IPAddress(bytes: bytes))
                case AF_INET6:
                    let bytes = socket.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                        withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
                    }
                    addresses.append(IPAddress(bytes: bytes))
                default: break
                }
            }
            next = entry.pointee.ai_next
        }
        return addresses
    }

    /// Answers what `resolver` says for `name`, or `PictureFailure.tooSlow` once `timeout` has passed. A lookup that
    /// cannot be stopped (`getaddrinfo`) is left to finish on its own, and its answer is dropped.
    private static func resolve(_ name: String, using resolver: @escaping Resolver, within timeout: Duration) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            let race = Race()
            let lookup = Task {
                let result = await Result { try await resolver(name) }
                if race.claim() { continuation.resume(with: result) }
            }
            let timer = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                if race.claim() {
                    lookup.cancel()
                    continuation.resume(throwing: PictureFailure.tooSlow)
                }
            }
            race.timer = timer
            if race.isDecided { timer.cancel() }
        }
    }

    /// Lets the lookup and the timer settle which of them answers.
    private final class Race: Sendable {
        private let state = Mutex<(decided: Bool, timer: Task<Void, Never>?)>((false, nil))

        /// True for the first to ask only.
        func claim() -> Bool {
            state.withLock { state in
                defer { state.decided = true }
                if !state.decided { state.timer?.cancel() }
                return !state.decided
            }
        }

        var isDecided: Bool { state.withLock { $0.decided } }

        var timer: Task<Void, Never>? {
            get { state.withLock { $0.timer } }
            set { state.withLock { $0.timer = newValue } }
        }
    }

    /// Throws why a request to `url` must not be made. Names are resolved here, and every address they have must be
    /// a public one: a name with one private address among public ones is refused too.
    ///
    /// This cannot close DNS rebinding. `URLSession` looks the name up itself when it connects, so a server that
    /// answers this question with a public address and the connection with a private one is not stopped by it.
    /// Closing that gap means connecting to the address checked, which needs Network.framework, and its own TLS
    /// handling and redirects, which this does not take on. What remains is a request that reads no more than a
    /// picture's first bytes into a file that is shown only if it is a picture of a kind the system decodes.
    ///
    /// A name that has not been answered within `timeout` is refused as too slow.
    static func check(_ url: URL, resolver: @escaping Resolver = system, timeout: Duration = .seconds(10)) async throws(PictureFailure) {
        guard url.scheme?.lowercased() == "https" else { throw .notSecure }
        guard url.user == nil, url.password == nil else { throw .hasCredentials }
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { throw .unresolved }
        while host.hasSuffix(".") { host.removeLast() }
        if let literal = IPAddress(literal: host) {
            guard literal.isPublic else { throw .privateNetwork }
            return
        }
        // A name with no dot is a machine on a local network, and `.local` and `.localhost` are names for one.
        guard host.contains("."), host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else {
            throw .privateNetwork
        }
        let addresses: [IPAddress]
        do {
            addresses = try await resolve(host, using: resolver, within: timeout)
        } catch let failure as PictureFailure where failure == .tooSlow {
            throw .tooSlow
        } catch {
            throw .unresolved
        }
        guard !addresses.isEmpty else { throw .unresolved }
        guard addresses.allSatisfy(\.isPublic) else { throw .privateNetwork }
    }
}
