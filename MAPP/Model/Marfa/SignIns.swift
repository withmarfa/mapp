import AppKit
import AuthenticationServices
import Foundation
import Marfa
import os

/// The sign-ins the app keeps, one for each server, and the steps that make and end one. The package's
/// `Authorization` is the only implementation that ships (`SystemSignIns`); tests and the sample use
/// `MemorySignIns`, since the package offers no stand-in for its sign-in or its Keychain.
nonisolated protocol SignIns: Sendable {
    /// The server to make calls to with the sign-in kept for `connection`: nil where none is kept or it has ended,
    /// and a throw where one is kept and cannot be read, which is neither of those.
    func server(for connection: MarfaConnection) throws -> Server?

    /// Signs in through the system's web authentication session, which shows the server's own pages over the
    /// window in front. The sign-in is kept before this returns, in place of any kept before.
    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws

    /// Starts a device sign-in, for a Mac that cannot use the browser: the person types the code on any device.
    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn

    /// Forgets the sign-in on this Mac and revokes it at the server. True where the server confirmed it; where it
    /// did not, the approval stands there until the owner ends it.
    func signOut(of connection: MarfaConnection) async throws -> Bool
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
    let finish: @Sendable () async throws -> Void
}

/// Why a sign-in did not finish, in the terms the app words, whichever sign-in it was.
nonisolated enum SignInOutcome: Hashable, Sendable {
    /// The person closed the browser or stopped waiting for the code.
    case canceled
    /// The person declined to approve MAPP on the server.
    case denied
    /// The code stopped working before the person approved it.
    case expired
    /// The server refused, or answered what MAPP can't use; the words are the package's.
    case refused(String)
    /// The server could not be reached, or the sign-in could not be finished; the words are the package's.
    case unreachable(String)
    /// Another process sharing the Keychain held the sign-in too long for the approval to be kept, and the approval
    /// was revoked.
    case inUse
    /// The Keychain would not keep or give the sign-in; the words are the system's, logged and never shown.
    case keychain(String)

    init(_ error: any Error) {
        if error is CancellationError {
            self = .canceled
        } else if let error = error as? SignInError {
            switch error {
            case .canceled: self = .canceled
            case .denied: self = .denied
            case .expired: self = .expired
            case .unavailable(let message): self = .unreachable(message)
            case .heldElsewhere: self = .inUse
            case .stateMismatch, .notSignedIn, .notAServer, .otherServer, .noRedirect, .refused, .unreadable:
                self = .refused(error.description)
            }
        } else if error is any KeychainRefusal {
            let message = String(describing: error)
            // A string logged without a privacy level is private, so the system's words stay out of the log.
            Telemetry.logger(.library).error("The Keychain refused a sign-in: \(message)")
            self = .keychain(message)
        } else {
            self = .unreachable(error.localizedDescription)
        }
    }
}

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

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp",
        anchor: @escaping @MainActor @Sendable () -> NSWindow? = {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        }
    ) {
        service = bundleIdentifier + ".marfa-sign-in"
        scheme = bundleIdentifier
        self.anchor = anchor
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

    @MainActor func signInWithBrowser(to connection: MarfaConnection) async throws {
        guard let window = anchor() else {
            throw SignInError.unavailable(message: "MAPP has no window to show the sign-in over.")
        }
        _ = try await authorization(for: connection).signIn(presentingFrom: window)
    }

    func startCodeSignIn(to connection: MarfaConnection) async throws -> CodeSignIn {
        let device = try await authorization(for: connection).startDeviceSignIn()
        return CodeSignIn(
            code: device.userCode, address: device.verificationURL, completeAddress: device.verificationURLComplete,
            expiresAt: device.expiresAt, finish: { _ = try await device.credential() })
    }

    func signOut(of connection: MarfaConnection) async throws -> Bool {
        try await authorization(for: connection).signOut()
    }
}
