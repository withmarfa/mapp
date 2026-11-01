#if DEBUG
import Foundation
import Marfa
import Synchronization

/// Sign-ins held in memory, for the unit tests, previews, the sample library and a debug build pointed at a test
/// server by hand. It never reaches the Keychain or a server. A held entry is an API key, since a test server
/// takes one; the sign-in steps answer from what the test scripted.
nonisolated final class MemorySignIns: SignIns {
    private struct State {
        var held: [URL: String]
        var unreadable: Set<URL> = []
        /// What each browser sign-in does, first to last; the last is repeated. Empty signs in with `signedInKey`.
        var browser: [Result<String, any Error>] = []
        var code: [Result<CodeSignIn, any Error>] = []
        var signOutAnswer: Result<Bool, any Error> = .success(true)
        var calls: [String] = []
    }

    private let state: Mutex<State>
    /// The key a scripted sign-in that succeeds leaves held.
    let signedInKey = "signed-in"

    init(_ held: [URL: String] = [:]) {
        state = Mutex(State(held: held))
    }

    /// What the steps were asked, in order, as `browser <address>`, `code <address>` and `signOut <address>`.
    var calls: [String] { state.withLock { $0.calls } }

    func hold(_ key: String, for connection: MarfaConnection) {
        save(key, for: connection.address)
    }

    func save(_ key: String, for address: URL) {
        state.withLock { $0.held[address] = key }
    }

    /// The key held for `address`; throws where it was made unreadable.
    func key(for address: URL) throws -> String? {
        let (key, unreadable) = state.withLock { ($0.held[address], $0.unreadable.contains(address)) }
        if unreadable { throw Unreadable() }
        return key
    }

    /// Run as each sign-out begins, before it forgets anything.
    let onSignOut = Mutex<(@Sendable () -> Void)?>(nil)

    /// Run as each browser sign-in begins, before it answers, to stand for the minutes a person takes; it may wait,
    /// and a cancel reaches it as a thrown `CancellationError`.
    let onBrowser = Mutex<(@MainActor @Sendable () async throws -> Void)?>(nil)

    func isHolding(_ connection: MarfaConnection) -> Bool {
        state.withLock { $0.held[connection.address] != nil }
    }

    /// Makes the sign-in held for `connection` one that cannot be read.
    func makeUnreadable(_ address: URL) {
        state.withLock { _ = $0.unreadable.insert(address) }
    }

    func makeUnreadable(_ connection: MarfaConnection) {
        state.withLock { _ = $0.unreadable.insert(connection.address) }
    }

    func script(browser: [Result<String, any Error>]) {
        state.withLock { $0.browser = browser }
    }

    func script(code: [Result<CodeSignIn, any Error>]) {
        state.withLock { $0.code = code }
    }

    func script(signOut: Result<Bool, any Error>) {
        state.withLock { $0.signOutAnswer = signOut }
    }

    struct Unreadable: KeychainRefusal {}

    func server(for connection: MarfaConnection) throws -> Server? {
        let key = try key(for: connection.address)
        return key.map { Server(url: connection.address, key: $0) }
    }

    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws {
        let next: Result<String, any Error> = state.withLock { state in
            state.calls.append("browser \(connection.address.absoluteString)")
            return state.browser.count > 1 ? state.browser.removeFirst() : (state.browser.first ?? .success(signedInKey))
        }
        try await onBrowser.withLock { $0 }?()
        let key = try next.get()
        state.withLock { $0.held[connection.address] = key; $0.unreadable.remove(connection.address) }
    }

    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn {
        let next: Result<CodeSignIn, any Error>? = state.withLock { state in
            state.calls.append("code \(connection.address.absoluteString)")
            return state.code.count > 1 ? state.code.removeFirst() : state.code.first
        }
        guard let next else { throw SignInError.unavailable(message: "No code was scripted.") }
        return try next.get()
    }

    func signOut(of connection: MarfaConnection) async throws -> Bool {
        onSignOut.withLock { $0 }?()
        let answer = state.withLock { state in
            state.calls.append("signOut \(connection.address.absoluteString)")
            // A sign-out that throws leaves the sign-in where it was, as a Keychain that would not delete it does.
            if case .success = state.signOutAnswer { state.held[connection.address] = nil }
            return state.signOutAnswer
        }
        return try answer.get()
    }
}
#endif
