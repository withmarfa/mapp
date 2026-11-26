import Foundation
import Marfa
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
            detail = String(localized: "Showing what’s on this Mac while the app reaches the server.")
            isProblem = false
        case .online:
            title = String(localized: "Connected")
            detail = nil
            isProblem = false
        case .offline:
            title = String(localized: "Offline")
            detail = String(localized: "The app can’t reach the server. Your changes are kept on this Mac and sent when it can.")
            isProblem = false
        case .keyRefused:
            title = String(localized: "Signed out")
            detail = String(localized: "The server has ended the app’s sign-in. Sign in again below.")
            isProblem = true
        case .unavailable(let message):
            title = String(localized: "Library unavailable")
            let sentence = String(localized: "The app can’t open or follow the copy of your library on this Mac.")
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
        var unsent: UnsentChanges?
        /// More changes arrived after the person was shown the others, so they are asked again.
        var isAskedAgain = false
        /// One of the changes is the removal of this app's settings from the Marfa, which has no text to show.
        var holdsSettingsRemoval = false
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

    /// How the last step ended, for a caller that needs to tell a sign-in the person stopped from one that finished.
    nonisolated enum Ending: Hashable, Sendable { case completed, canceled, failed }
    private(set) var lastEnding: Ending?
    private(set) var departure: Departure?
    /// The code the person is to type on another device, while a sign-in with a code waits for it.
    private(set) var code: CodeSignIn?
    /// The sign-in step under way, which Cancel stops while the host is still signing in.
    @ObservationIgnored private var signingIn: Task<Void, Never>?
    /// Whether the person is asked to confirm a disconnect that has nothing waiting.
    var isConfirmingDisconnect = false

    /// The app's own settings in the Marfa, as a disconnect can remove them first.
    struct SettingsKept {
        /// Whether the settings are kept in the connected Marfa now, which decides whether Disconnect offers to remove them.
        var isKept: @MainActor () -> Bool
        /// Moves them to the bin and returns once the server has taken that; throws a `PreferencesSync.RemovalError`
        /// where it could not. With `sendsOtherChanges` false, a copy that holds other changes is left as it was, since
        /// sending the removal sends them.
        var remove: @MainActor (_ sendsOtherChanges: Bool) async throws -> Void
        /// Whether one of the writes a copy has not sent, by id, is the removal of the settings.
        var isRemovalWaiting: @MainActor (Set<String>) async -> Bool = { _ in false }

        /// The settings kept by `sync`.
        static func over(_ sync: PreferencesSync) -> SettingsKept {
            SettingsKept(
                isKept: { sync.syncs },
                remove: { try await sync.remove(confirmed: true, sendsOtherChanges: $0) },
                isRemovalWaiting: { await sync.isRemovalWaiting(among: $0) })
        }
    }

    /// Set where the settings sync is known (`Libraries`); a model without it never offers the choice.
    @ObservationIgnored var settingsKept: SettingsKept?
    /// Whether Disconnect offers to remove the settings, decided when the person asks to disconnect.
    private(set) var offersSettingsRemoval = false
    /// The person's choice to remove them with the disconnect; off each time they ask to disconnect.
    var alsoRemovesSettings = false
    /// A removal that did not finish, which the person decides what to do about: nothing was left.
    private(set) var settingsRemovalFailure: SettingsRemovalFailure?

    struct SettingsRemovalFailure: Equatable {
        enum Reason: Equatable {
            /// The server did not take it.
            case notDone
            /// It would have sent the changes the person chose to discard.
            case discardedChangesWait
        }

        var reason = Reason.notDone
        /// What they chose about the copy where changes waited, to carry on with if they disconnect anyway.
        var choice: Choice?
    }

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
            await ask(.switchServer(usingCode: usingCode), unsent, askedAgain: choice != nil)
        }
        // A switch that finished but for removing the old server's leftovers has still switched.
        if isConnected(to: target) { otherAddress = "" }
    }

    private func isConnected(to address: String) -> Bool {
        guard let target = try? MarfaConnection(address: address), let current = host.connection else { return false }
        return current.sameServer(as: target)
    }

    /// A disconnect with nothing waiting is confirmed once, since it ends the sign-in. With changes waiting, the
    /// question about them is the confirmation, so it is not asked twice.
    func requestDisconnect() {
        offersSettingsRemoval = settingsKept?.isKept() ?? false
        alsoRemovesSettings = false
        settingsRemovalFailure = nil
        if host.waitingChanges == 0 {
            isConfirmingDisconnect = true
        } else {
            Task { await disconnect() }
        }
    }

    func disconnect(_ choice: Choice? = nil) async {
        guard !isWorking else { return }
        // The removal comes before the sign-out, since after it nothing can be removed. With changes still waiting and no
        // answer yet the question comes first, so a person who cancels it has removed nothing.
        if offersSettingsRemoval, alsoRemovesSettings, choice != nil || host.waitingChanges == 0 {
            guard await removeSettingsBeforeLeaving(choice) else { return }
        }
        await run(.leaving) { () async throws(MarfaHost.Problem) in
            try await host.disconnect(hostChoice(choice))
            departure = nil
        } onWaiting: { [self] unsent in
            await ask(.disconnect, unsent, askedAgain: choice != nil)
        }
    }

    /// Removes the settings from the Marfa for a disconnect. False where it did not finish: the person is told, and
    /// nothing is signed out unless they say so (`disconnectAnyway`).
    private func removeSettingsBeforeLeaving(_ choice: Choice?) async -> Bool {
        guard let settingsKept else { return true }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            // Sending the removal sends the whole queue, so it is never made while the person is discarding what waits in it.
            try await settingsKept.remove(choice != .discardCopy)
        } catch {
            let blocked = (error as? PreferencesSync.RemovalError) == .otherChangesWait
            settingsRemovalFailure = SettingsRemovalFailure(reason: blocked ? .discardedChangesWait : .notDone, choice: choice)
            // A removal that was queued and not taken is no longer something to offer; one that never started still is.
            offersSettingsRemoval = settingsKept.isKept()
            alsoRemovesSettings = false
            return false
        }
        alsoRemovesSettings = false
        offersSettingsRemoval = false
        return true
    }

    /// The person agrees to disconnect although the settings stay in the Marfa.
    func disconnectAnyway() async {
        guard let failure = settingsRemovalFailure else { return }
        settingsRemovalFailure = nil
        alsoRemovesSettings = false
        await disconnect(failure.choice)
    }

    /// The person stays connected after a removal that did not finish. A question about changes that wait stays open.
    func stayConnected() {
        settingsRemovalFailure = nil
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
        alsoRemovesSettings = false
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
                message: String(localized: "Enter a Marfa server address, such as marfa.example."))
        case .notSignedIn:
            Notice(title: String(localized: "Sign In First"), message: String(localized: "The app isn’t signed in to this server. Sign in below."))
        case .unavailable(let message):
            switch reached {
            case .signedInAgain:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: sentences(
                        String(localized: "The app kept the new sign-in, but the copy of your library on this Mac can’t be opened."), message))
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
        case .notRevoked(let address):
            // Only a disconnect signs out: a switch keeps the Marfa left signed in.
            approvalNotice(.left, address: address)
        case .notRemoved(let signIn, let copy, let approvalAt):
            switch reached {
            case .left:
                Notice(
                    title: String(localized: "Disconnected, but Not Everything Was Removed"),
                    message: withApproval(removalMessage(signIn: signIn, copy: copy), approvalAt, .left))
            case .switched:
                Notice(
                    title: String(localized: "Switched Servers, but Not Everything Was Removed"),
                    message: String(localized: "The previous server’s copy is still on this Mac. The app removes it before it connects to that server again."))
            case .notOpened, .signedInAgain:
                Notice(
                    title: String(localized: "Can’t Open the Library"),
                    message: String(localized: "A copy of this library that you discarded is still on this Mac and can’t be removed. Check that the app can change its own files, then try again."))
            }
        case .copyKept(let kept, let signIn, let approvalAt):
            keptNotice(kept, signIn: signIn, approvalAt: approvalAt, reached: reached)
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
                title: String(localized: "This App Wasn’t Approved"),
                message: String(localized: "The server was told not to approve the app, so nothing changed. Sign in again to try again."))
        case .expired:
            Notice(
                title: String(localized: "The Code Expired"),
                message: String(localized: "The code stopped working before it was approved. Ask for a new code and approve it sooner."))
        case .refused:
            Notice(
                title: String(localized: "The Server Refused the Sign-In"),
                message: String(localized: "The server wouldn’t approve the app, so nothing changed. Check that you are signing in to the right server and account, then try again."))
        case .unreachable:
            Notice(
                title: String(localized: "Can’t Reach the Server"),
                message: String(localized: "The app couldn’t reach that address, so nothing changed. Check the address and your connection, then try again."))
        case .discoveryTransport(.dnsFailure):
            Notice(
                title: String(localized: "Can’t Find the Server"),
                message: String(localized: "The app couldn’t find the server by name. Check the address and your connection, then try again."))
        case .discoveryTransport(.connectionFailed):
            Notice(
                title: String(localized: "Can’t Connect to the Server"),
                message: String(localized: "The app couldn’t connect to the server. Check the address and make sure the server is running and reachable from this Mac, then try again."))
        case .discoveryTransport(.untrustedCertificate):
            Notice(
                title: String(localized: "Can’t Verify the Server’s Certificate"),
                message: String(localized: "This Mac couldn’t verify the server’s certificate. Check the address and ask whoever manages the server to check its certificate."))
        case .couldNotFinish:
            Notice(
                title: String(localized: "Couldn’t Finish Signing In"),
                message: String(localized: "The app couldn’t finish signing in. Check your connection and try again, or sign in with a code."))
        case .notMarfa:
            Notice(
                title: String(localized: "Check the Address"),
                message: String(localized: "That address isn’t a Marfa server the app can sign in to. Check the address, then try again."))
        case .notVerified:
            Notice(
                title: String(localized: "Couldn’t Confirm the Sign-In"),
                message: String(localized: "The app couldn’t verify the approval. Try signing in again."))
        case .inUse:
            Notice(
                title: String(localized: "The Sign-In Is in Use"),
                message: String(localized: "Another copy of this app or another app is using the sign-in on this Mac, so nothing changed. Wait a moment, then try again."))
        case .keychain:
            Notice(
                title: String(localized: "Can’t Keep the Sign-In"),
                message: String(localized: "The Keychain wouldn’t keep or give the sign-in. Check that the app can use the Keychain, then try again."))
        case .noWindow:
            Notice(
                title: String(localized: "No Window to Sign In From"),
                message: String(localized: "The app needs a window to show the server’s sign-in page over. Open one of its windows, then try again, or use a code instead."))
        case .failed:
            Notice(
                title: String(localized: "Couldn’t Sign In"),
                message: String(localized: "Something went wrong while signing in, so nothing changed. Try again, or use a code if the browser won’t open."))
        }
    }

    /// A copy the person discarded that the package would not remove, which still holds every change in it.
    private static func approvalNotice(_ which: Words.ForgottenApproval, address: String) -> Notice {
        Notice(title: Words.approvalMayStandTitle(which), message: Words.approvalMayStand(which, address: address))
    }

    private static func keptNotice(_ kept: MarfaHost.CopyKept, signIn: String?, approvalAt: String?, reached: Reached) -> Notice {
        let previous = reached == .switched
        let body: String
        switch kept {
        case .changed(let now):
            body = sentences(
                previous
                    ? String(localized: "The app kept the previous server’s copy, because it now holds a different number of changes than you saw.")
                    : String(localized: "The app kept the copy, because it now holds a different number of changes than you saw."),
                Words.notSent(Int(clamping: now)) + " " + (previous
                    ? String(localized: "Sign in to the previous server again to see them.")
                    : String(localized: "Sign in to this server again to see them.")))
        case .unreadable(let folder):
            body = Words.cannotDiscard(folder: folder)
        case .notMadeByApp(let folder):
            body = String(localized: "The copy in the folder “\(folder)” isn’t one the app made, so the app left it. Move the folder to the Trash if you don’t need it.")
        }
        let note = signIn == nil ? nil : String(localized: "The sign-in is still in your Keychain. Remove it in Keychain Access.")
        let told = note.map { sentences(body, $0) } ?? body
        let message = withApproval(told, approvalAt, .left)
        switch reached {
        case .left:
            return Notice(title: String(localized: "Disconnected, but the Copy Was Kept"), message: message)
        case .switched:
            return Notice(title: String(localized: "Switched Servers, but the Copy Was Kept"), message: message)
        case .notOpened, .signedInAgain:
            return Notice(title: String(localized: "Can’t Open the Library"), message: message)
        }
    }

    /// `message`, with how to end the approval where the sign-out could not confirm the server did.
    private static func withApproval(_ message: String, _ address: String?, _ which: Words.ForgottenApproval) -> String {
        address.map { sentences(message, Words.approvalMayStand(which, address: $0)) } ?? message
    }

    private static func sentences(_ first: String, _ detail: String) -> String {
        detail.isEmpty ? first : first + " " + detail
    }

    private static func removalMessage(signIn: String?, copy: String?) -> String {
        switch (signIn != nil, copy != nil) {
        case (true, true):
            String(localized: "The sign-in is still in your Keychain, and the copy is still on this Mac. Remove the sign-in in Keychain Access. The app removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "The sign-in is still in your Keychain. Remove it in Keychain Access.")
        default:
            String(localized: "The copy is still on this Mac. The app removes it before it connects to that server again.")
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

    private func ask(_ kind: Departure.Kind, _ unsent: UnsentChanges?, askedAgain: Bool) async {
        var departure = Departure(kind: kind, unsent: unsent, isAskedAgain: askedAgain)
        if let unsent, let settingsKept { departure.holdsSettingsRemoval = await settingsKept.isRemovalWaiting(unsent.ids) }
        self.departure = departure
    }

    private func run(
        _ step: Step,
        _ work: () async throws(MarfaHost.Problem) -> Void,
        onWaiting: ((UnsentChanges?) async -> Void)? = nil
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            code = nil
        }
        notice = nil
        lastEnding = nil
        do {
            try await work()
            lastEnding = .completed
        } catch {
            if case .signIn(.canceled) = error { lastEnding = .canceled } else { lastEnding = .failed }
            if case .changesWaiting(let unsent) = error, let onWaiting {
                await onWaiting(unsent)
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
