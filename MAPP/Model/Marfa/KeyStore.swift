import Foundation
import Marfa
import Synchronization

/// Where the key for each Marfa server is kept between launches. The working copy holds it in memory only.
nonisolated protocol KeyStore: Sendable {
    func save(_ key: String, for connection: MarfaConnection) throws
    func key(for connection: MarfaConnection) throws -> String?
    func delete(for connection: MarfaConnection) throws
}

/// The person's keys, in their default keychain.
nonisolated struct KeychainKeyStore: KeyStore {
    /// Named for the bundle identifier, so a Debug build, which has its own, never reads or replaces the keys of the
    /// installed app. The installed app's is `com.withmarfa.mapp.marfa-key`.
    static var service: String { "\(Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp").marfa-key" }

    private let keychain: Keychain

    init(keychain: Keychain = .system) {
        self.keychain = keychain
    }

    /// One server is one account, so a key saved for one address is never read for another.
    static func account(for connection: MarfaConnection) -> String {
        connection.address.absoluteString
    }

    func save(_ key: String, for connection: MarfaConnection) throws {
        try keychain.save(key: key, service: Self.service, account: Self.account(for: connection))
    }

    func key(for connection: MarfaConnection) throws -> String? {
        try keychain.key(service: Self.service, account: Self.account(for: connection))
    }

    func delete(for connection: MarfaConnection) throws {
        try keychain.delete(service: Self.service, account: Self.account(for: connection))
    }
}

/// Keys held for the life of the process, for tests, which must never reach the person's keychain.
nonisolated final class MemoryKeyStore: KeyStore {
    private let keys: Mutex<[MarfaConnection: String]>

    init(_ keys: [MarfaConnection: String] = [:]) {
        self.keys = Mutex(keys)
    }

    func save(_ key: String, for connection: MarfaConnection) {
        keys.withLock { $0[connection] = key }
    }

    func key(for connection: MarfaConnection) -> String? {
        keys.withLock { $0[connection] }
    }

    func delete(for connection: MarfaConnection) {
        _ = keys.withLock { $0.removeValue(forKey: connection) }
    }
}
