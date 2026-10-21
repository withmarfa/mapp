import Foundation
import Observation

/// How the connection reads in Settings, in the app's words.
nonisolated struct ConnectionStatus: Hashable, Sendable {
    var title: String
    var detail: String?
    var isProblem: Bool

    init(_ state: MarfaHost.State) {
        switch state {
        case .disconnected:
            title = String(localized: "Not connected")
            detail = nil
            isProblem = false
        case .connecting:
            title = String(localized: "Connecting…")
            detail = String(localized: "Showing what’s on this Mac while MAPP reaches the server.")
            isProblem = false
        case .online:
            title = String(localized: "Connected")
            detail = nil
            isProblem = false
        case .offline:
            title = String(localized: "Offline")
            detail = String(localized: "MAPP can’t reach the server. Your changes are kept on this Mac and sent when it can.")
            isProblem = false
        case .signedOut:
            title = String(localized: "Signed out")
            detail = String(localized: "Sign in again to approve MAPP. Your changes stay on this Mac and are sent once you do.")
            isProblem = true
        case .unavailable(let message):
            title = String(localized: "Library unavailable")
            let sentence = String(localized: "MAPP can’t open or follow the copy of your library on this Mac.")
            detail = message.isEmpty ? sentence : sentence + " " + message
            isProblem = true
        }
    }
}

/// What the Marfa section of Settings does: it holds the address the person types, takes each step through the
/// host, and turns what the host says into words. Each step that signs in takes the browser the view gives it.
/// Leaving a copy while changes wait is the person's to decide, so the model keeps the question, with the text of
/// what would be lost, until they answer it.
@Observable @MainActor final class MarfaSettingsModel {
    /// What went wrong and what to do, never the error itself.
    nonisolated struct Notice: Hashable, Sendable {
        var title: String
        var message: String
    }

    /// The question asked when a copy is left while changes wait in it.
    struct Departure: Identifiable {
        nonisolated enum Kind: Hashable, Sendable {
            case disconnect
            case switchServer
        }

        let id = UUID()
        var kind: Kind
        /// What the copy holds that the server has not taken, as last read; nil where it could not be read.
        var unsent: UnsentWrites?
        /// More changes arrived after the person was shown the others, so they are asked again.
        var isAskedAgain = false
    }

    nonisolated enum Choice: Hashable, Sendable {
        case keepCopy
        case discardCopy
    }

    let host: MarfaHost
    var address = ""
    var otherAddress = ""
    private(set) var notice: Notice?
    private(set) var isWorking = false
    private(set) var departure: Departure?
    /// Whether the person is asked to confirm a disconnect that has nothing waiting.
    var isConfirmingDisconnect = false

    init(host: MarfaHost) {
        self.host = host
    }

    var isConnected: Bool { host.configuredConnection != nil }
    var isSignedOut: Bool { host.state == .signedOut }
    var status: ConnectionStatus { ConnectionStatus(host.state) }

    var canSignIn: Bool { !isWorking && !Self.trimmed(address).isEmpty }
    var canSwitch: Bool { !isWorking && !Self.trimmed(otherAddress).isEmpty }

    // MARK: Steps

    /// Signs in to the server the person typed and connects to it.
    func signIn(with browser: @escaping MarfaBrowser) async {
        guard canSignIn else { return }
        let target = address
        await run(.reaching(target)) { () async throws(MarfaHost.Problem) in
            try await host.connect(address: target, with: browser)
            address = ""
        }
    }

    /// Signs in again to the server connected to, for a sign-in the server ended.
    func signInAgain(with browser: @escaping MarfaBrowser) async {
        await run(.signingInAgain) { () async throws(MarfaHost.Problem) in
            try await host.signInAgain(with: browser)
        }
    }

    /// Moves to another server, asking first what becomes of this one's copy if changes wait in it, then signing
    /// in to the other.
    func switchServer(with browser: @escaping MarfaBrowser, _ choice: Choice? = nil) async {
        guard choice != nil || canSwitch else { return }
        let target = otherAddress
        await run(.reaching(target)) { () async throws(MarfaHost.Problem) in
            do throws(MarfaHost.Problem) {
                try await host.changeAddress(to: target, with: browser, choice: hostChoice(choice))
            } catch {
                if isConnected(to: target) { otherAddress = "" }
                throw error
            }
            otherAddress = ""
            departure = nil
        } onWaiting: { [self] unsent in
            ask(.switchServer, unsent, askedAgain: choice != nil)
        }
    }

    private func isConnected(to address: String) -> Bool {
        guard let target = try? MarfaConnection(address: address) else { return false }
        return host.connection == target
    }

    /// A disconnect with nothing waiting is confirmed once, since it signs out. With changes waiting, the
    /// question about them is the confirmation, so it is not asked twice.
    func requestDisconnect() {
        if host.waitingChanges == 0 {
            isConfirmingDisconnect = true
        } else {
            Task { await disconnect() }
        }
    }

    func disconnect(_ choice: Choice? = nil) async {
        guard !isWorking else { return }
        await run(.leaving) { () async throws(MarfaHost.Problem) in
            try await host.disconnect(hostChoice(choice))
            departure = nil
        } onWaiting: { [self] unsent in
            ask(.disconnect, unsent, askedAgain: choice != nil)
        }
    }

    /// The person's answer to the question: the copy is kept, or discarded with the changes they were shown. A
    /// switch then signs in to the other server through `browser`.
    func answer(_ choice: Choice, with browser: @escaping MarfaBrowser) async {
        guard let kind = departure?.kind else { return }
        switch kind {
        case .disconnect: await disconnect(choice)
        case .switchServer: await switchServer(with: browser, choice)
        }
    }

    /// Nothing is left, nothing is discarded.
    func cancelDeparture() {
        departure = nil
    }

    // MARK: Words

    /// What a step that ran into a problem had done by then, which decides how some problems are told.
    nonisolated enum Reached: Hashable, Sendable {
        /// The server was left.
        case left
        /// The app now reads the other server.
        case switched
        /// No other server was opened.
        case notOpened
        /// The person signed in again to the server connected to.
        case signedInAgain
    }

    /// A problem in the app's words: what happened, and what to do. Nil for the question about changes that
    /// wait, which is asked rather than told, and for a sign-in the person canceled, which changed nothing.
    static func notice(for problem: MarfaHost.Problem, reached: Reached = .left) -> Notice? {
        switch problem {
        case .changesWaiting, .signInCanceled:
            nil
        case .notAServer:
            Notice(
                title: String(localized: "Check the Address"),
                message: String(localized: "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://."))
        case .notApproved:
            Notice(
                title: String(localized: "MAPP Wasn’t Approved"),
                message: String(localized: "To use your library in MAPP, sign in and approve MAPP."))
        case .signInFailed:
            Notice(
                title: String(localized: "Can’t Sign In"),
                message: String(localized: "MAPP couldn’t finish signing in to the server. Check the address and your connection, then try again."))
        case .signedOut:
            Notice(
                title: String(localized: "Signed Out"),
                message: String(localized: "Sign in again to approve MAPP."))
        case .unavailable(let message):
            switch reached {
            case .signedInAgain:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: sentences(
                        String(localized: "MAPP signed in again, but the copy of your library on this Mac can’t be opened."), message))
            default:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: sentences(String(localized: "The copy of your library on this Mac can’t be opened."), message))
            }
        case .keychain:
            Notice(
                title: String(localized: "Can’t Read Your Sign-In"),
                message: String(localized: "The Keychain wouldn’t give MAPP its sign-in. Check that MAPP can use the Keychain, then try again."))
        case .notRemoved(let signIn, let copy):
            switch reached {
            case .left:
                Notice(title: String(localized: "Disconnected, but Not Everything Was Removed"), message: removalMessage(signIn: signIn, copy: copy))
            case .switched:
                Notice(
                    title: String(localized: "Switched Servers, but Not Everything Was Removed"),
                    message: previousRemovalMessage(signIn: signIn, copy: copy))
            case .notOpened, .signedInAgain:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: String(localized: "A copy of this library that you discarded is still on this Mac and can’t be removed. Check that MAPP can change its own files, then try again."))
            }
        case .notConnected:
            Notice(title: String(localized: "Not connected"), message: String(localized: "Connect to a server first."))
        case .busy:
            Notice(title: String(localized: "Still Working"), message: String(localized: "Wait for the current step to finish, then try again."))
        }
    }

    private static func sentences(_ first: String, _ detail: String) -> String {
        detail.isEmpty ? first : first + " " + detail
    }

    private static func removalMessage(signIn: String?, copy: String?) -> String {
        switch (signIn != nil, copy != nil) {
        case (true, true):
            String(localized: "MAPP is still signed in, and the copy is still on this Mac. To remove MAPP’s access, revoke it on your Marfa server. MAPP removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "MAPP is still signed in. To remove MAPP’s access, revoke it on your Marfa server.")
        default:
            String(localized: "The copy is still on this Mac. MAPP removes it before it connects to that server again.")
        }
    }

    private static func previousRemovalMessage(signIn: String?, copy: String?) -> String {
        switch (signIn != nil, copy != nil) {
        case (true, true):
            String(localized: "MAPP is still signed in to the previous server, and its copy is still on this Mac. To remove MAPP’s access, revoke it on that server. MAPP removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "MAPP is still signed in to the previous server. To remove MAPP’s access, revoke it on that server.")
        default:
            String(localized: "The previous server’s copy is still on this Mac. MAPP removes it before it connects to that server again.")
        }
    }

    // MARK: Running a step

    /// What a step sets out to do, so a problem is told against what it did.
    private enum Step {
        case reaching(String)
        case signingInAgain
        case leaving
    }

    private func hostChoice(_ choice: Choice?) -> MarfaHost.DisconnectChoice? {
        switch choice {
        case nil: nil
        case .keepCopy: .keepCopy
        case .discardCopy: .discardCopy(departure?.unsent)
        }
    }

    private func ask(_ kind: Departure.Kind, _ unsent: UnsentWrites?, askedAgain: Bool) {
        departure = Departure(kind: kind, unsent: unsent, isAskedAgain: askedAgain)
    }

    private func run(
        _ step: Step,
        _ work: () async throws(MarfaHost.Problem) -> Void,
        onWaiting: ((UnsentWrites?) -> Void)? = nil
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            try await work()
        } catch {
            if case .changesWaiting(let unsent) = error, let onWaiting {
                onWaiting(unsent)
            } else {
                // A failure after the question was put to the person ends it, so it is not asked again.
                departure = nil
                notice = Self.notice(for: error, reached: reached(by: step))
            }
        }
    }

    private func reached(by step: Step) -> Reached {
        switch step {
        case .leaving: .left
        case .reaching(let address): isConnected(to: address) ? .switched : .notOpened
        case .signingInAgain: .signedInAgain
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
