#if DEBUG
import Foundation
import Marfa
import MarfaTesting
import Synchronization

/// Sign-ins for the unit tests, previews, the sample library and a debug build pointed at a test server by hand.
/// What it holds is the package's own: a `Credential` kept in a `MemoryKeychain`, read back through `Authorization`
/// as `SystemSignIns` reads the Keychain, so it never reaches the Keychain or a server and a `Server` made from it
/// takes the same path as the shipping one. A held entry's token is what a test server takes as its key. Only the
/// browser and code sign-in answers are scripted, since the package has no stand-in for the web authentication session.
nonisolated final class ScriptedSignIns: SignIns {
    private struct State {
        /// What each browser sign-in does, first to last; the last is repeated. Empty signs in with `signedInKey`.
        var browser: [Result<String, any Error>] = []
        var code: [Result<CodeSignIn, any Error>] = []
        var signOutAnswer: Result<Bool, any Error> = .success(true)
        var calls: [String] = []
    }

    private static let service = "com.withmarfa.mapp.scripted-sign-ins"

    private let keychain = MemoryKeychain()
    private let state = Mutex(State())
    /// The token a scripted sign-in that succeeds leaves held.
    let signedInKey = "signed-in"

    init(_ held: [URL: String] = [:]) {
        for (address, token) in held { save(token, for: address) }
    }

    /// What the steps were asked, in order, as `browser <address>`, `code <address>` and `signOut <address>`.
    var calls: [String] { state.withLock { $0.calls } }

    func hold(_ key: String, for connection: MarfaConnection) {
        save(key, for: connection.address)
    }

    func save(_ key: String, for address: URL) {
        _ = try? keychain.signIn(to: address, service: Self.service, accessToken: key)
    }

    /// The token held for `address`; throws where it was made unreadable.
    func key(for address: URL) throws -> String? {
        try held(address)?.key
    }

    /// Run as each sign-out begins, before it forgets anything.
    let onSignOut = Mutex<(@Sendable () -> Void)?>(nil)

    /// Run as each browser sign-in begins, before it answers, to stand for the minutes a person takes; it may wait,
    /// and a cancel reaches it as a thrown `CancellationError`.
    let onBrowser = Mutex<(@MainActor @Sendable () async throws -> Void)?>(nil)

    func isHolding(_ connection: MarfaConnection) -> Bool {
        ((try? held(connection.address)) ?? nil) != nil
    }

    /// Makes the Keychain refuse every read, as a locked one does, until the next sign-in is kept.
    func makeUnreadable(_ connection: MarfaConnection) {
        keychain.failReads(with: errSecInteractionNotAllowed)
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

    private func authorization(for address: URL) throws -> Authorization {
        try Authorization(
            server: address, client: Authorization.Client(name: "MAPP", redirect: nil, scopes: []), keychain: keychain.keychain,
            service: Self.service)
    }

    private func held(_ address: URL) throws -> Server? {
        guard let credential = try authorization(for: address).credential() else { return nil }
        return try Server(url: address, credential: credential)
    }

    func server(for connection: MarfaConnection) throws -> Server? {
        try held(connection.address)
    }

    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws {
        let next: Result<String, any Error> = state.withLock { state in
            state.calls.append("browser \(connection.address.absoluteString)")
            return state.browser.count > 1 ? state.browser.removeFirst() : (state.browser.first ?? .success(signedInKey))
        }
        try await onBrowser.withLock { $0 }?()
        let token = try next.get()
        keychain.succeed()
        save(token, for: connection.address)
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
            return state.signOutAnswer
        }
        // A sign-out that throws leaves the sign-in where it was, as a Keychain that would not delete it does.
        let confirmed = try answer.get()
        _ = try await authorization(for: connection.address).signOut()
        return confirmed
    }
}
#endif
