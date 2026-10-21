import Foundation
import Marfa

/// Shows the server's sign-in and approval pages and answers the sign-in the person approved. The app passes one
/// that uses SwiftUI's web authentication session, so the model never names SwiftUI.
typealias MarfaBrowser = @MainActor @Sendable (Authorization) async throws -> Credential

/// How the app signs in to a Marfa server and keeps the sign-in between launches, so the host is tested without a
/// browser or the Keychain.
nonisolated protocol MarfaSignIn: Sendable {
    /// Signs in to `connection` through `browser`, and keeps the sign-in in place of any kept before.
    @MainActor func signIn(to connection: MarfaConnection, with browser: MarfaBrowser) async throws
    /// The server to open a copy on with the sign-in kept for `connection`; nil when none is kept.
    func server(for connection: MarfaConnection) throws -> Server?
    /// Removes the sign-in kept for `connection` and revokes it at the server. Throws only when it is still kept.
    func signOut(of connection: MarfaConnection) async throws
}

/// The person's sign-ins, made through the package's `Authorization` and kept in their default keychain.
nonisolated struct KeychainSignIn: MarfaSignIn {
    /// What MAPP asks the owner to approve, from what it reads and writes: every item a person keeps (`content`
    /// leaves out the server's `system` types, as the library does), every relationship, since the library links
    /// items of any type, and Delete Permanently. The owner may approve less.
    static let scopes = ["content:write", "edge.*:write", "items.purge"]

    private static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp" }

    /// Named for the bundle identifier, so a Debug build, which has its own, never reads or replaces the sign-ins of
    /// the installed app. The installed app's is `com.withmarfa.mapp.marfa-sign-in`.
    static var service: String { "\(bundleIdentifier).marfa-sign-in" }

    /// A private-use redirect whose scheme is the bundle identifier, which the app claims in `CFBundleURLTypes`.
    static var redirect: URL? { URL(string: "\(bundleIdentifier):/signed-in") }

    static func authorization(for connection: MarfaConnection) throws(SignInError) -> Authorization {
        try Authorization(
            server: connection.address,
            client: Authorization.Client(name: "MAPP", redirect: redirect, scopes: scopes),
            keychain: .system, service: service)
    }

    @MainActor func signIn(to connection: MarfaConnection, with browser: MarfaBrowser) async throws {
        _ = try await browser(try Self.authorization(for: connection))
    }

    func server(for connection: MarfaConnection) throws -> Server? {
        guard let credential = try Self.authorization(for: connection).credential() else { return nil }
        do {
            return try Server(url: connection.address, credential: credential)
        } catch SignInError.notSignedIn {
            // Signed out since the credential was read.
            return nil
        }
    }

    func signOut(of connection: MarfaConnection) async throws {
        try await Self.authorization(for: connection).signOut()
    }
}

#if DEBUG
/// For the sample folder and the unit tests hosted in the app, which must never reach the person's Keychain or
/// server: nothing is kept, and signing in is refused.
nonisolated struct NoSignIn: MarfaSignIn {
    @MainActor func signIn(to connection: MarfaConnection, with browser: MarfaBrowser) async throws {
        throw SignInError.unavailable(message: String(localized: "Signing in isn’t available in this test build."))
    }

    func server(for connection: MarfaConnection) -> Server? { nil }

    func signOut(of connection: MarfaConnection) {}
}
#endif
