import AppKit
import AuthenticationServices
import Foundation
import Marfa
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
    /// window in front. The sign-in is kept before this returns, in place of any kept before.
    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws -> SignedIn

    /// Starts a device sign-in, for a Mac that cannot use the browser: the person types the code on any device.
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
    /// MAPP could not confirm that the server ended the approval this sign-in replaced, which only its owner can end
    /// there.
    var replacedApprovalStands = false

    init(replacedApprovalStands: Bool = false) {
        self.replacedApprovalStands = replacedApprovalStands
    }

    /// What `grant` says of the approval it replaced. Both of `SystemSignIns`' sign-ins make theirs here.
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
    /// The person declined to approve MAPP on the server.
    case denied
    /// The code stopped working before the person approved it.
    case expired
    /// The server refused the sign-in.
    case refused
    /// The server could not be reached.
    case unreachable
    /// The sign-in did not finish and the package could not say why: the server or the browser did not answer.
    case couldNotFinish
    /// The address answered, but not as a Marfa server MAPP can sign in to.
    case notMarfa
    /// The approval that came back was not for this sign-in or not from this server, so it was not used.
    case notVerified
    /// Another process sharing the Keychain held the sign-in too long for the approval to be kept, and the approval
    /// was revoked.
    case inUse
    /// The Keychain would not keep or give the sign-in.
    case keychain
    /// MAPP had no window to show the server's page over.
    case noWindow
    /// Anything else that stopped the sign-in.
    case failed

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
            case .heldElsewhere: self = .inUse
            case .refused: self = .refused
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

    /// Why reading the server's root, before any sign-in began, did not show a Marfa server: it could not be reached,
    /// or something else answered.
    init(probe error: any Error) {
        let detail = String(describing: error)
        if error is CancellationError {
            self = .canceled
        } else if let error = error as? MarfaError {
            switch error {
            case .unnamed(let status, _, _): self = status >= 500 ? .unreachable : .notMarfa
            default: self = error.isTransient ? .unreachable : .notMarfa
            }
        } else if error is URLError {
            self = .unreachable
        } else {
            self = .notMarfa
        }
        let outcome = self
        if outcome != .canceled { Telemetry.logger(.library).error("The address did not answer as a Marfa server (\(String(describing: outcome))): \(detail)") }
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
    /// What the app asks the owner to approve: every item to read and write, and every edge (relationships, links
    /// and attachments), which the server grants apart from items (`edge.*`). With them the three permissions its
    /// features use: Delete Permanently (`items.purge`), This Marfa (`config.manage`) and a type's icon
    /// (`schema.write`). The owner may approve less, and what is missing is told where it is needed.
    static let scopes = ["*:read", "*:write", "edge.*:read", "edge.*:write", "items.purge", "config.manage", "schema.write"]

    /// The service the sign-ins are kept under: the bundle identifier followed by `.marfa-sign-in`.
    let service: String
    /// The scheme the browser returns the approval to: the bundle identifier, which the app claims in its
    /// `Info.plist` and which differs between Debug and Release.
    let scheme: String
    /// The window the browser's pages are shown over.
    let anchor: @MainActor @Sendable () -> NSWindow?

    /// A device sign-in as the package gives it, so a test can stand in for the server.
    struct DeviceGrant: Sendable {
        let code: String
        let address: URL
        let completeAddress: URL?
        let expiresAt: Date
        let credential: @Sendable () async throws -> any ReplacedGrant
    }

    /// Stand-ins for the two package calls that talk to a server; nil uses the package's. A test gives them to reach
    /// the mapping from what the package returns to what MAPP tells.
    private let browserGrant: (@MainActor @Sendable (MarfaConnection, NSWindow) async throws -> any ReplacedGrant)?
    private let deviceGrant: (@Sendable (MarfaConnection) async throws -> DeviceGrant)?

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp",
        anchor: @escaping @MainActor @Sendable () -> NSWindow? = {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        },
        browserGrant: (@MainActor @Sendable (MarfaConnection, NSWindow) async throws -> any ReplacedGrant)? = nil,
        deviceGrant: (@Sendable (MarfaConnection) async throws -> DeviceGrant)? = nil
    ) {
        service = bundleIdentifier + ".marfa-sign-in"
        scheme = bundleIdentifier
        self.anchor = anchor
        self.browserGrant = browserGrant
        self.deviceGrant = deviceGrant
    }

    func authorization(for connection: MarfaConnection) throws -> Authorization {
        let client = Authorization.Client(
            name: "MAPP", redirect: URL(string: scheme + ":/signed-in"), scopes: Self.scopes)
        return try Authorization(server: connection.address, client: client, service: service)
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
        if let browserGrant { return SignedIn(try await browserGrant(connection, window)) }
        return SignedIn(try await authorization(for: connection).signIn(presentingFrom: window))
    }

    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn {
        let device: DeviceGrant
        if let deviceGrant {
            device = try await deviceGrant(connection)
        } else {
            let started = try await authorization(for: connection).startDeviceSignIn()
            device = DeviceGrant(
                code: started.userCode, address: started.verificationURL, completeAddress: started.verificationURLComplete,
                expiresAt: started.expiresAt, credential: { try await started.credential() })
        }
        return CodeSignIn(
            code: device.code, address: device.address, completeAddress: device.completeAddress, expiresAt: device.expiresAt,
            finish: { SignedIn(try await device.credential()) })
    }

    func signOut(of connection: MarfaConnection) async throws -> SignOutOutcome {
        try await authorization(for: connection).signOut()
    }
}
