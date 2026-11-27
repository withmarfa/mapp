import AppKit
import AuthenticationServices
import Foundation
import Marfa
import SystemConfiguration
import os

/// The sign-ins the app keeps, one for each server, and the steps that make and end one. The package's
/// `Authorization` is the only implementation that ships (`SystemSignIns`); tests and the sample use
/// `ScriptedSignIns`, which keeps the sign-in in the package's `MemoryKeychain` and scripts only the browser and
/// code answers, which the package has no stand-in for.
nonisolated protocol SignIns: Sendable {
    /// The server to make calls to with the sign-in kept for `connection`: nil where none is kept or it has ended,
    /// and a throw where one is kept and cannot be read, which is neither of those.
    func server(for connection: MarfaConnection) throws -> Server?

    /// Signs in through the system's web authentication session, which shows the server's own pages over the
    /// window in front. The sign-in is kept before this returns, in place of any kept before. It asks for
    /// `SystemSignIns.scopes`, every owner permission among them; the owner may approve fewer.
    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws -> SignedIn

    /// The permissions the sign-in kept for `connection` holds: nil where none is kept or it has ended, and a throw
    /// where one is kept and cannot be read.
    func grants(for connection: MarfaConnection) throws -> Set<InstancePermission>?

    /// Whether the sign-in kept for `connection` may read the owner's name (`SystemSignIns.profileScopes`): nil where none
    /// is kept or it has ended, and a throw where one is kept and cannot be read. A sign-in made before the app asked for it
    /// does not, until the owner allows more or signs in again.
    func readsProfile(for connection: MarfaConnection) throws -> Bool?

    /// The scopes the sign-in kept for `connection` holds, as the owner approved them: nil where none is kept or it has
    /// ended, and a throw where one is kept and cannot be read.
    func scopes(for connection: MarfaConnection) throws -> [String]?

    /// Starts a device sign-in, for a Mac that cannot use the browser: the person types the code on any device.
    /// It asks for what `signInWithBrowser` asks for.
    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn

    /// Forgets the sign-in on this Mac and revokes it at the server. Only `.notConfirmed` leaves an approval that may
    /// stand there until the owner ends it. Sign-out can wait for a renewal before asking the server to end the
    /// approval.
    func signOut(of connection: MarfaConnection) async throws -> SignOutOutcome
}

/// A device sign-in waiting for the person to approve it on another device.
nonisolated struct CodeSignIn: Sendable {
    /// What the person types on the approval page.
    let code: String
    /// The approval page, where the person signs in and types `code`.
    let address: URL
    /// The approval page with the code filled in, where the server gives one.
    let completeAddress: URL?
    /// When the code stops working.
    let expiresAt: Date
    /// Waits until the person decides, then keeps the sign-in. Cancel the task to stop waiting.
    let finish: @Sendable () async throws -> SignedIn
}

/// What a finished sign-in left behind that the person may need to act on.
nonisolated struct SignedIn: Hashable, Sendable {
    /// the app could not confirm that the server ended the approval this sign-in replaced, which only its owner can end
    /// there.
    var replacedApprovalStands = false

    init(replacedApprovalStands: Bool = false) {
        self.replacedApprovalStands = replacedApprovalStands
    }

    /// What `grant` says of the approval it replaced. Both of `SystemSignIns`' sign-ins make theirs here, each in one
    /// line handing on the package's `Credential`.
    init(_ grant: some ReplacedGrant) {
        replacedApprovalStands = grant.replacedGrantStands
    }
}

/// What a finished sign-in says of the approval it replaced: the package's `Credential`, or a stand-in for one.
nonisolated protocol ReplacedGrant: Sendable {
    var replacedGrantStands: Bool { get }
}

extension Credential: ReplacedGrant {}

/// Why a sign-in did not finish, in the terms the app words, whichever sign-in it was. No case carries a word the
/// package, the system or the server said: those are logged and never shown.
nonisolated enum SignInOutcome: Hashable, Sendable {
    /// The person closed the browser or stopped waiting for the code.
    case canceled
    /// The person declined to approve the app on the server.
    case denied
    /// The code stopped working before the person approved it.
    case expired
    /// The server refused the sign-in.
    case refused
    /// The server could not be reached.
    case unreachable
    case discoveryTransport(SignInError.DiscoveryTransportReason)
    /// The sign-in did not finish and the package could not say why: the server or the browser did not answer.
    case couldNotFinish
    /// The address answered, but not as a Marfa server the app can sign in to: not Marfa's answer, or a plain HTTP status.
    case notMarfa
    /// The approval that came back was not for this sign-in or not from this server, so it was not used.
    case notVerified
    /// Another process sharing the Keychain held the sign-in too long for the approval to be kept, and the approval
    /// was revoked.
    case inUse
    /// The Keychain would not keep or give the sign-in.
    case keychain
    /// the app had no window to show the server's page over.
    case noWindow
    /// Anything else that stopped the sign-in.
    case failed

    /// The package words a reply that was no OAuth error, such as a page or a proxy's answer, as `http_<status>`: the
    /// address is not a Marfa server the app can sign in to. A code the server's own OAuth error gave is a refusal.
    private static func isHTTPStatus(_ code: String) -> Bool {
        guard code.hasPrefix("http_") else { return false }
        let status = code.dropFirst("http_".count)
        return !status.isEmpty && status.allSatisfy(\.isASCII) && status.allSatisfy(\.isNumber)
    }

    init(_ error: any Error) {
        // A string logged without a privacy level is private, so what the system or server said stays out of the log.
        let detail = String(describing: error)
        if error is CancellationError {
            self = .canceled
        } else if let error = error as? SignInError {
            switch error {
            case .canceled: self = .canceled
            case .denied: self = .denied
            case .expired: self = .expired
            case .unavailable: self = .couldNotFinish
            case .discoveryTransport(let reason): self = .discoveryTransport(reason)
            case .heldElsewhere: self = .inUse
            case .refused(let code, _): self = Self.isHTTPStatus(code) ? .notMarfa : .refused
            case .stateMismatch, .issuerMismatch: self = .notVerified
            case .notAServer, .unreadable: self = .notMarfa
            case .notSignedIn, .otherServer, .noRedirect: self = .failed
            }
        } else if let error = error as? ASWebAuthenticationSessionError {
            switch error.code {
            case .canceledLogin: self = .canceled
            case .presentationContextNotProvided, .presentationContextInvalid: self = .noWindow
            @unknown default: self = .failed
            }
        } else if error is NoSignInWindow {
            self = .noWindow
        } else if error is any KeychainRefusal {
            self = .keychain
        } else if error is URLError {
            self = .unreachable
        } else {
            self = .failed
        }
        let outcome = self
        if outcome != .canceled { Telemetry.logger(.library).error("A sign-in did not finish (\(String(describing: outcome))): \(detail)") }
    }
}

/// There was no window to show the browser's sign-in over.
nonisolated struct NoSignInWindow: Error {}

/// An error that says the Keychain, not the server, would not keep or give a sign-in.
nonisolated protocol KeychainRefusal: Error {}

extension Keychain.Failure: KeychainRefusal {}

/// The package's sign-in, kept in the Keychain under a service of the app's own, so a Debug build never reads or
/// replaces the installed app's sign-ins.
nonisolated struct SystemSignIns: SignIns {
    private static let clientName = "Marfa for Mac"

    /// What the app asks the owner to approve: every item to read and write, and every edge (relationships, links
    /// and attachments), which the server grants apart from items (`edge.*`). Full Access grants every owner permission
    /// the app can hold (`askedAtSignIn`). Signed In As reads the owner's name from `GET /profile` with its own scope,
    /// and Account reads and edits the profile (`accountScopes`).
    /// The app's own settings (`PreferencesType`) need a scope that reaches the type, which `*:write`
    /// never does, and registering the type where the Marfa holds none (`metadata.types:write`). The app asks for
    /// `app.*:write`: the vendor scope is unavailable before its first type exists (`keys-and-oauth/app-vendor-not-named`),
    /// and discovery never lists it afterward. This reaches every app's types; withmarfa/marfa#3522 would let the app ask
    /// for its vendor alone. Settings > Types > Links registers the owner's link types (`metadata.edge_types:write`). The
    /// owner may approve less, and what is missing is told where it is needed.
    static let scopes = ["*:read", "*:write", "edge.*:read", "edge.*:write"]
        + askedAtSignIn.map(\.rawValue).sorted() + profileScopes + accountScopes
        + [PreferencesType.rootScope, PreferencesType.registeringScope, ClientOwnerCalls.registeringLinkTypes]

    /// What Signed In As needs: the owner's name (`instance-claim/profile-read`).
    static let profileScopes = ["profile.name:read"]

    /// Changing the username requires its own scope, even when a sign-in can write the rest of the profile.
    static let accountScopes = ["profile.username:read", "profile.username:write", "profile.email:read", "profile.email:write", "profile.name:write", "profile.avatar:read", "profile.avatar:write"]

    /// Whether `scopes`, as a sign-in holds them, let it read the owner's name.
    static func readsProfile(_ scopes: [String]) -> Bool { profileScopes.allSatisfy(scopes.contains) }

    /// Whether `held`, as a sign-in holds them, lacks any of `scopes`: an owner permission the owner left out, or a scope the
    /// app began to ask for after the sign-in was made. Allow More… asks for them all again.
    static func lacksAsked(_ held: [String]) -> Bool { !Set(held).isSuperset(of: scopes) }

    /// Every owner permission, which every sign-in asks for and a sign-in holds unless the owner approved fewer. The
    /// package's list is the contract's but `connectors.host`, which only a connector host's own key holds.
    static let askedAtSignIn = Set(InstancePermission.allCases)

    /// The service the sign-ins are kept under: the bundle identifier followed by `.marfa-sign-in`.
    let service: String
    /// The scheme the browser returns the approval to: the bundle identifier, which the app claims in its
    /// `Info.plist` and which differs between Debug and Release.
    let scheme: String
    private let computerName: @Sendable () -> String?
    /// The window the browser's pages are shown over.
    let anchor: @MainActor @Sendable () -> NSWindow?

    init(
        bundleIdentifier: String = AppPaths.bundleIdentifier,
        computerName: @escaping @Sendable () -> String? = { SCDynamicStoreCopyComputerName(nil, nil) as String? },
        anchor: @escaping @MainActor @Sendable () -> NSWindow? = {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        }
    ) {
        service = bundleIdentifier + ".marfa-sign-in"
        scheme = bundleIdentifier
        self.computerName = computerName
        self.anchor = anchor
    }

    /// The address the server sends the browser back to once an approval ends, which the app registers as its redirect. A
    /// connector's vendor sign-in is sent back to it too, so the system's sheet ends there.
    var redirectAddress: String { scheme + ":/signed-in" }

    func authorization(for connection: MarfaConnection) throws -> Authorization {
        let client = Authorization.Client(name: registrationName, redirect: URL(string: redirectAddress), scopes: Self.scopes)
        return try Authorization(server: connection.address, client: client, service: service)
    }

    private var registrationName: String {
        guard let name = computerName()?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return Self.clientName
        }
        let prefix = Self.clientName + " on "
        // The server counts Unicode scalars. Keep any character we include whole.
        var remaining = 100 - prefix.unicodeScalars.count
        let fitting = name.prefix { character in
            remaining -= character.unicodeScalars.count
            return remaining >= 0
        }
        let suffix = fitting.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? Self.clientName : prefix + suffix
    }

    func grants(for connection: MarfaConnection) throws -> Set<InstancePermission>? {
        guard let credential = try authorization(for: connection).credential() else { return nil }
        return Set(InstancePermission.allCases.filter(credential.grants))
    }

    func readsProfile(for connection: MarfaConnection) throws -> Bool? {
        guard let credential = try authorization(for: connection).credential() else { return nil }
        return Self.readsProfile(credential.scopes)
    }

    func scopes(for connection: MarfaConnection) throws -> [String]? {
        try authorization(for: connection).credential()?.scopes
    }

    func server(for connection: MarfaConnection) throws -> Server? {
        guard let credential = try authorization(for: connection).credential() else { return nil }
        do {
            return try Server(url: connection.address, credential: credential)
        } catch SignInError.notSignedIn {
            return nil
        }
    }

    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws -> SignedIn {
        guard let window = anchor() else { throw NoSignInWindow() }
        return SignedIn(try await authorization(for: connection).signIn(presentingFrom: window))
    }

    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn {
        let started = try await authorization(for: connection).startDeviceSignIn()
        return CodeSignIn(
            code: started.userCode, address: started.verificationURL, completeAddress: started.verificationURLComplete,
            expiresAt: started.expiresAt, finish: { SignedIn(try await started.credential()) })
    }

    func signOut(of connection: MarfaConnection) async throws -> SignOutOutcome {
        try await authorization(for: connection).signOut()
    }
}
