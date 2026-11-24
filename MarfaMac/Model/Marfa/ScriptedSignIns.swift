#if DEBUG
import Foundation
import Marfa
import MarfaAPI
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
        /// The token a code sign-in leaves held when none is scripted in `code`; nil leaves no code scripted.
        var codeKey: String?
        var signOutAnswer: Result<SignOutOutcome, any Error> = .success(.endedAtServer)
        /// Whether the sign-ins that succeed leave a replaced approval standing at the server.
        var replacedStands = false
        var calls: [String] = []
        /// The permissions the next browser or code sign-in grants of those asked, first to last; the last is repeated.
        /// Empty grants everything asked.
        var approving: [Set<InstancePermission>] = []
        /// Whether the sign-ins that succeed are approved the read of the owner's name they ask for.
        var approvesProfile = true
        /// The scopes each browser or code sign-in asked for, as `SystemSignIns` asks them, in order.
        var askedScopes: [[String]] = []
    }

    private static let service = "\(AppPaths.bundleIdentifier).scripted-sign-ins"

    private let keychain = MemoryKeychain()
    private let state = Mutex(State())
    /// The token a scripted sign-in that succeeds leaves held.
    let signedInKey = "signed-in"

    /// Keeps each of `held`, with `scopes` beside the owner's permissions and the read of the name. The sample passes
    /// `approvedBeyondPermissions`, as a sign-in approved in full; a key for a test server holds only what it was given.
    init(_ held: [URL: String] = [:], scopes: [String] = []) {
        for (address, token) in held { save(token, for: address, scopes: scopes) }
    }

    /// What a sign-in approved in full holds beyond the owner's permissions and the read of the name, as
    /// `SystemSignIns.scopes` asks for it; a browser or code sign-in here is approved them.
    static let approvedBeyondPermissions = SystemSignIns.scopes.filter {
        InstancePermission(rawValue: $0) == nil && !SystemSignIns.profileScopes.contains($0)
    }

    /// What the steps were asked, in order, as `browser <address>`, `code <address>` and `signOut <address>`.
    var calls: [String] { state.withLock { $0.calls } }

    func hold(_ key: String, for connection: MarfaConnection) {
        save(key, for: connection.address)
    }

    /// Keeps `key` as a sign-in holding `permissions` and, with `profile`, the read of the owner's name; a sign-in made
    /// before the app asked for it is kept with `profile` false.
    /// `scopes` are kept beside them, as a sign-in the owner approved for the app's own settings holds `app.marfa-mac.*:write`.
    func save(
        _ key: String, for address: URL, permissions: Set<InstancePermission> = SystemSignIns.askedAtSignIn, profile: Bool = true,
        scopes: [String] = []
    ) {
        _ = try? keychain.signIn(
            to: address, service: Self.service, accessToken: key,
            scopes: permissions.map(\.rawValue).sorted() + (profile ? SystemSignIns.profileScopes : []) + scopes)
    }

    /// Keeps what the key held for `connection` really holds, as the server it is held for says (`GET /keys/current`), in
    /// place of the permissions a sign-in asks for. A test server's key then shows a page its permission lacks as
    /// Needs a Permission, as the shipping app does. A server that does not answer leaves what was held. A key states no
    /// OAuth scopes, so `scopes` are kept beside them for what the person running the test knows it may do.
    func adoptScopes(for connection: MarfaConnection, adding scopes: [String] = []) async {
        guard let server = try? held(connection.address), let token = try? key(for: connection.address) else { return }
        guard let key = try? await Client(server).getCurrentKey().ok.body.json else { return }
        save(
            token, for: connection.address, permissions: Set(key.permissions.compactMap { InstancePermission(rawValue: $0.rawValue) }),
            profile: (try? readsProfile(for: connection)) ?? false, scopes: scopes)
    }

    /// The permissions each browser or code sign-in asked for, read from the scopes it asked for, in order.
    var asked: [Set<InstancePermission>] { askedScopes.map { scopes in Set(scopes.compactMap(InstancePermission.init(rawValue:))) } }

    /// What the next browser or code sign-ins grant of the permissions they ask for.
    func script(approving: [Set<InstancePermission>]) {
        state.withLock { $0.approving = approving }
    }

    /// Whether the sign-ins that follow are approved the read of the owner's name; the owner may leave it out.
    func script(approvingProfile: Bool) {
        state.withLock { $0.approvesProfile = approvingProfile }
    }

    /// The scopes every browser or code sign-in asked for, as `SystemSignIns` asks them, in order.
    var askedScopes: [[String]] { state.withLock { $0.askedScopes } }

    func readsProfile(for connection: MarfaConnection) throws -> Bool? {
        guard let credential = try authorization(for: connection.address).credential() else { return nil }
        return SystemSignIns.readsProfile(credential.scopes)
    }

    func scopes(for connection: MarfaConnection) throws -> [String]? {
        try authorization(for: connection.address).credential()?.scopes
    }

    func grants(for connection: MarfaConnection) throws -> Set<InstancePermission>? {
        guard let credential = try authorization(for: connection.address).credential() else { return nil }
        return Set(InstancePermission.allCases.filter(credential.grants))
    }

    /// The token held for `address`; throws where it was made unreadable.
    func key(for address: URL) throws -> String? {
        try held(address)?.key
    }

    /// Run as each sign-out begins, before it forgets anything.
    let onSignOut = Mutex<(@Sendable () -> Void)?>(nil)

    /// Waited on as each sign-out begins, after `onSignOut`, to stand for a server that does not answer.
    let signOutGate = Mutex<(@Sendable () async -> Void)?>(nil)

    /// Run as each browser sign-in begins, before it answers, to stand for the minutes a person takes; it may wait,
    /// and a cancel reaches it as a thrown `CancellationError`.
    let onBrowser = Mutex<(@MainActor @Sendable () async throws -> Void)?>(nil)

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

    /// Makes each code sign-in that is not scripted by `script(code:)` keep `key`, approving what the browser's
    /// `script(approving:)` does of the permissions asked.
    func script(codeKey: String) {
        state.withLock { $0.codeKey = codeKey }
    }

    func script(signOut: Result<SignOutOutcome, any Error>) {
        state.withLock { $0.signOutAnswer = signOut }
    }

    func script(replacedApprovalStands: Bool) {
        state.withLock { $0.replacedStands = replacedApprovalStands }
    }

    /// What a code sign-in's `finish` answers.
    var signedIn: SignedIn { SignedIn(replacedApprovalStands: state.withLock { $0.replacedStands }) }

    private func authorization(for address: URL) throws -> Authorization {
        try Authorization(
            server: address, client: Authorization.Client(name: "Marfa for Mac", redirect: nil, scopes: []), keychain: keychain.keychain,
            service: Self.service)
    }

    private func held(_ address: URL) throws -> Server? {
        guard let credential = try authorization(for: address).credential() else { return nil }
        return try Server(url: address, credential: credential)
    }

    func server(for connection: MarfaConnection) throws -> Server? {
        try held(connection.address)
    }

    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws -> SignedIn {
        let (next, granted, profile): (Result<String, any Error>, Set<InstancePermission>, Bool) = state.withLock { state in
            state.calls.append("browser \(connection.address.absoluteString)")
            let granted = Self.take(in: &state)
            return (
                state.browser.count > 1 ? state.browser.removeFirst() : (state.browser.first ?? .success(signedInKey)), granted,
                state.approvesProfile)
        }
        try await onBrowser.withLock { $0 }?()
        let token = try next.get()
        keychain.succeed()
        save(token, for: connection.address, permissions: granted, profile: profile, scopes: Self.approvedBeyondPermissions)
        return signedIn
    }

    /// Records what a sign-in asked for and answers which of it the owner approves.
    private static func take(in state: inout State) -> Set<InstancePermission> {
        state.askedScopes.append(SystemSignIns.scopes)
        let approving = state.approving.count > 1 ? state.approving.removeFirst() : state.approving.first
        let asked = SystemSignIns.askedAtSignIn
        return approving.map { asked.intersection($0) } ?? asked
    }

    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn {
        let (next, granted, key, profile): (Result<CodeSignIn, any Error>?, Set<InstancePermission>, String?, Bool) = state.withLock { state in
            state.calls.append("code \(connection.address.absoluteString)")
            let granted = Self.take(in: &state)
            return (state.code.count > 1 ? state.code.removeFirst() : state.code.first, granted, state.codeKey, state.approvesProfile)
        }
        if let next { return try next.get() }
        guard let key else { throw SignInError.unavailable(message: "No code was scripted.") }
        let address = connection.address
        return CodeSignIn(
            code: "SCRIPTED", address: address, completeAddress: nil, expiresAt: .distantFuture,
            finish: { [self] in
                save(key, for: address, permissions: granted, profile: profile, scopes: Self.approvedBeyondPermissions)
                return signedIn
            })
    }

    func signOut(of connection: MarfaConnection) async throws -> SignOutOutcome {
        onSignOut.withLock { $0 }?()
        let answer = state.withLock { state in
            state.calls.append("signOut \(connection.address.absoluteString)")
            return state.signOutAnswer
        }
        await signOutGate.withLock { $0 }?()
        // A sign-out that throws leaves the sign-in where it was, as a Keychain that would not delete it does.
        let outcome = try answer.get()
        _ = try await authorization(for: connection.address).signOut()
        return outcome
    }
}
#endif
