import Foundation
import Observation

/// How the connection reads in Settings, in the app's words.
nonisolated struct ConnectionStatus: Hashable, Sendable {
    var title: String
    var detail: String?
    var isProblem: Bool

    init(_ state: MarfaConnectionState) {
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
        case .keyRefused:
            title = String(localized: "Signed out")
            detail = String(localized: "The server has ended MAPP’s sign-in. Sign in again below.")
            isProblem = true
        case .unavailable(let message):
            title = String(localized: "Library unavailable")
            let sentence = String(localized: "MAPP can’t open or follow the copy of your library on this Mac.")
            detail = message.isEmpty ? sentence : sentence + " " + message
            isProblem = true
        case .otherVersion(let unsent):
            title = String(localized: "Library unavailable")
            detail = Words.otherVersion(unsent: unsent)
            isProblem = true
        case .inUse:
            title = String(localized: "Library unavailable")
            detail = Words.inUse
            isProblem = true
        }
    }
}

/// What the Marfa section of Settings does: it holds what the person types, takes each step through the host,
/// and turns what the host says into words. Leaving a copy while changes wait is the person's to decide, so the
/// model keeps the question, with the text of what would be lost, until they answer it.
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
            /// Switching, signing in to the other server in the way the person chose.
            case switchServer(usingCode: Bool)
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
    /// The code the person is to type on another device, while a sign-in with a code waits for it.
    private(set) var code: CodeSignIn?
    /// The sign-in step under way, which Cancel stops while the host is still signing in.
    @ObservationIgnored private var signingIn: Task<Void, Never>?
    /// Whether the person is asked to confirm a disconnect that has nothing waiting.
    var isConfirmingDisconnect = false

    init(host: MarfaHost) {
        self.host = host
    }

    var isConnected: Bool { host.configuredConnection != nil }
    var status: ConnectionStatus { ConnectionStatus(host.state) }

    var canConnect: Bool { !isWorking && !Self.trimmed(address).isEmpty }
    var canSwitch: Bool { !isWorking && !Self.trimmed(otherAddress).isEmpty }

    // MARK: Steps

    /// A sign-in step the Cancel button can stop: the browser's page, or the wait for a code.
    enum SignInStep: Hashable, Sendable {
        case connect(usingCode: Bool)
        case signInAgain(usingCode: Bool)
        /// `choice` is the person's answer to the question about changes that wait, where they have given it.
        case switchServer(usingCode: Bool, choice: Choice? = nil)
    }

    /// Starts a sign-in step as a task of its own, so Cancel can stop it. A step started while another is under
    /// way is not run.
    @discardableResult
    func start(_ step: SignInStep) -> Task<Void, Never> {
        if let signingIn { return signingIn }
        let task = Task { [self] in
            switch step {
            case .connect(let usingCode): await connect(usingCode: usingCode)
            case .signInAgain(let usingCode): await signInAgain(usingCode: usingCode)
            case .switchServer(let usingCode, let choice): await switchServer(choice, usingCode: usingCode)
            }
            signingIn = nil
        }
        signingIn = task
        return task
    }

    /// Whether Cancel can stop something: only while the host waits on the person's sign-in. After the approval
    /// the sign-in is used to open the copy, and stopping then would end it, so Cancel is not offered.
    var canCancelSignIn: Bool { signingIn != nil && host.isSigningIn }

    /// Stops the sign-in under way. Nothing is kept, and the person is told nothing: they asked for it.
    func cancelSignIn() {
        guard canCancelSignIn else { return }
        signingIn?.cancel()
    }

    private func method(usingCode: Bool) -> MarfaHost.SignInMethod {
        usingCode ? .code(shown: { [weak self] in self?.code = $0 }) : .browser
    }

    func connect(usingCode: Bool = false) async {
        guard canConnect else { return }
        let target = address
        let method = method(usingCode: usingCode)
        await run(.reaching(target)) { () async throws(MarfaHost.Problem) in
            try await host.connect(address: target, via: method)
        }
        if isConnected(to: target) { address = "" }
    }

    func signInAgain(usingCode: Bool = false) async {
        guard !isWorking, host.connection != nil else { return }
        let method = method(usingCode: usingCode)
        await run(.signingInAgain) { () async throws(MarfaHost.Problem) in
            try await host.signInAgain(via: method)
        }
    }

    /// Moves to another server, asking first what becomes of this one's copy if changes wait in it.
    func switchServer(_ choice: Choice? = nil, usingCode: Bool = false) async {
        guard choice != nil || canSwitch else { return }
        let target = otherAddress
        let method = method(usingCode: usingCode)
        let hostChoice = hostChoice(choice)
        // The question is closed before the sign-in starts, so it is not over the code the person has to type.
        departure = nil
        await run(.reaching(target)) { () async throws(MarfaHost.Problem) in
            try await host.changeAddress(to: target, via: method, choice: hostChoice)
        } onWaiting: { [self] unsent in
            ask(.switchServer(usingCode: usingCode), unsent, askedAgain: choice != nil)
        }
        // A switch that finished but for removing the old server's leftovers has still switched.
        if isConnected(to: target) { otherAddress = "" }
    }

    private func isConnected(to address: String) -> Bool {
        guard let target = try? MarfaConnection(address: address) else { return false }
        return host.connection == target
    }

    /// A disconnect with nothing waiting is confirmed once, since it ends the sign-in. With changes waiting, the
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

    /// The person's answer to the question: the copy is kept, or discarded with the changes they were shown.
    func answer(_ choice: Choice) async {
        guard let kind = departure?.kind else { return }
        switch kind {
        case .disconnect: await disconnect(choice)
        case .switchServer(let usingCode): await start(.switchServer(usingCode: usingCode, choice: choice)).value
        }
    }

    /// Nothing is left, nothing is discarded. A sign-in kept for a switch the person now drops is ended.
    func cancelDeparture() {
        guard let kind = departure?.kind else { return }
        departure = nil
        if case .switchServer = kind { Task { [host] in await host.abandonPendingSignIn() } }
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
        /// The person signed in again to the server connected to, and the library could not be opened on it.
        case signedInAgain
    }

    /// A problem in the app's words: what happened, and what to do. Nil for the question about changes that
    /// wait, which is asked rather than told.
    static func notice(for problem: MarfaHost.Problem, reached: Reached = .left) -> Notice? {
        switch problem {
        case .changesWaiting:
            nil
        case .notAServer:
            Notice(
                title: String(localized: "Check the Address"),
                message: String(localized: "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://."))
        case .notSignedIn:
            Notice(title: String(localized: "Sign In First"), message: String(localized: "MAPP isn’t signed in to this server. Sign in below."))
        case .unavailable(let message):
            switch reached {
            case .signedInAgain:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: sentences(
                        String(localized: "You are signed in again, but the copy of your library on this Mac can’t be opened."), message))
            default:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: sentences(String(localized: "The copy of your library on this Mac can’t be opened."), message))
            }
        case .otherVersion(let unsent):
            Notice(title: String(localized: "Can’t Open the Library"), message: Words.otherVersion(unsent: unsent))
        case .inUse:
            Notice(title: String(localized: "Can’t Open the Library"), message: Words.inUse)
        case .signIn(let outcome):
            signInNotice(outcome)
        case .notRevoked:
            Notice(
                title: String(localized: "Disconnected, but MAPP Is Still Approved"),
                message: String(localized: "MAPP forgot its sign-in on this Mac, but couldn’t reach the server to end it there. To end it, open Connected apps from Home on the server, choose MAPP and select Disconnect."))
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
        case .copyKept(let kept, let signIn):
            keptNotice(kept, signIn: signIn, reached: reached)
        case .cannotDiscard(let folder):
            Notice(title: String(localized: "Can’t Discard This Copy"), message: Words.cannotDiscard(folder: folder))
        case .notConnected:
            Notice(title: String(localized: "Not connected"), message: String(localized: "Connect to a server first."))
        case .busy:
            Notice(title: String(localized: "Still Working"), message: String(localized: "Wait for the current step to finish, then try again."))
        }
    }

    /// A sign-in that did not finish. Nil where the person stopped it themselves, who needs no telling.
    private static func signInNotice(_ outcome: SignInOutcome) -> Notice? {
        switch outcome {
        case .canceled:
            nil
        case .denied:
            Notice(
                title: String(localized: "MAPP Wasn’t Approved"),
                message: String(localized: "The server was told not to approve MAPP, so nothing changed. Sign in again to try again."))
        case .expired:
            Notice(
                title: String(localized: "The Code Expired"),
                message: String(localized: "The code stopped working before it was approved. Ask for a new code and approve it sooner."))
        case .refused(let message):
            Notice(
                title: String(localized: "The Server Refused the Sign-In"),
                message: sentences(String(localized: "Nothing changed."), message))
        case .unreachable(let message):
            Notice(
                title: String(localized: "Can’t Reach the Server"),
                message: sentences(
                    String(localized: "MAPP couldn’t finish signing in. Check the address and your connection, then try again, or use a code if the browser won’t open."),
                    message))
        case .inUse:
            Notice(
                title: String(localized: "The Sign-In Is in Use"),
                message: String(localized: "Another copy of MAPP or another app is using the sign-in on this Mac, so nothing changed. Wait a moment, then try again."))
        case .keychain:
            Notice(
                title: String(localized: "Can’t Keep the Sign-In"),
                message: String(localized: "The Keychain wouldn’t keep or give the sign-in. Check that MAPP can use the Keychain, then try again."))
        }
    }

    /// A copy the person discarded that the package would not remove, which still holds every change in it.
    private static func keptNotice(_ kept: MarfaHost.CopyKept, signIn: String?, reached: Reached) -> Notice {
        let previous = reached == .switched
        let body: String
        switch kept {
        case .changed(let now):
            body = sentences(
                previous
                    ? String(localized: "MAPP kept the previous server’s copy, because it now holds a different number of changes than you saw.")
                    : String(localized: "MAPP kept the copy, because it now holds a different number of changes than you saw."),
                Words.notSent(Int(clamping: now)) + " " + String(localized: "Sign in to this server again to see them."))
        case .unreadable(let folder):
            body = Words.cannotDiscard(folder: folder)
        case .notMapps(let folder):
            body = String(localized: "The copy in the folder “\(folder)” isn’t one MAPP made, so MAPP left it. Move the folder to the Trash if you don’t need it.")
        }
        let note = signIn == nil ? nil : String(localized: "The sign-in is still in your Keychain. Remove it in Keychain Access.")
        let message = note.map { sentences(body, $0) } ?? body
        switch reached {
        case .left:
            return Notice(title: String(localized: "Disconnected, but the Copy Was Kept"), message: message)
        case .switched:
            return Notice(title: String(localized: "Switched Servers, but the Copy Was Kept"), message: message)
        case .notOpened, .signedInAgain:
            return Notice(title: String(localized: "Can’t Open the Library"), message: message)
        }
    }

    private static func sentences(_ first: String, _ detail: String) -> String {
        detail.isEmpty ? first : first + " " + detail
    }

    private static func removalMessage(signIn: String?, copy: String?) -> String {
        switch (signIn != nil, copy != nil) {
        case (true, true):
            String(localized: "The sign-in is still in your Keychain, and the copy is still on this Mac. Remove the sign-in in Keychain Access. MAPP removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "The sign-in is still in your Keychain. Remove it in Keychain Access.")
        default:
            String(localized: "The copy is still on this Mac. MAPP removes it before it connects to that server again.")
        }
    }

    private static func previousRemovalMessage(signIn: String?, copy: String?) -> String {
        switch (signIn != nil, copy != nil) {
        case (true, true):
            String(localized: "The previous server’s sign-in is still in your Keychain, and its copy is still on this Mac. Remove the sign-in in Keychain Access. MAPP removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "The previous server’s sign-in is still in your Keychain. Remove it in Keychain Access.")
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
        defer {
            isWorking = false
            code = nil
        }
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
        case .signingInAgain: host.source == nil ? .signedInAgain : .left
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
