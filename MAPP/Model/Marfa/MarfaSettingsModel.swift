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
        case .keyRefused:
            title = String(localized: "Key refused")
            detail = String(localized: "The server doesn’t accept the key. Enter a new one below.")
            isProblem = true
        case .unavailable(let message):
            title = String(localized: "Library unavailable")
            let sentence = String(localized: "MAPP can’t open or follow the copy of your library on this Mac.")
            detail = message.isEmpty ? sentence : sentence + " " + message
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
    var key = ""
    var newKey = ""
    var otherAddress = ""
    var otherKey = ""
    private(set) var notice: Notice?
    private(set) var isWorking = false
    private(set) var departure: Departure?
    /// Whether the person is asked to confirm a disconnect that has nothing waiting.
    var isConfirmingDisconnect = false

    /// Run before the host changes what the windows read, so every open page has handed over its last edit to
    /// the library it came from. Set by the app; tests set none.
    @ObservationIgnored var beforeChange: () async -> Void

    init(host: MarfaHost, beforeChange: @escaping () async -> Void = {}) {
        self.host = host
        self.beforeChange = beforeChange
    }

    var isConnected: Bool { host.configuredConnection != nil }
    var status: ConnectionStatus { ConnectionStatus(host.state) }

    var canConnect: Bool { !isWorking && !Self.trimmed(address).isEmpty && !Self.trimmed(key).isEmpty }
    var canReplaceKey: Bool { !isWorking && !Self.trimmed(newKey).isEmpty }
    var canSwitch: Bool { !isWorking && !Self.trimmed(otherAddress).isEmpty && !Self.trimmed(otherKey).isEmpty }

    // MARK: Steps

    func connect() async {
        guard canConnect else { return }
        await run { () async throws(MarfaHost.Problem) in
            await beforeChange()
            try await host.connect(address: address, key: key)
            address = ""
            key = ""
        }
    }

    func replaceKey() async {
        guard canReplaceKey else { return }
        await run { () async throws(MarfaHost.Problem) in
            try await host.replaceKey(newKey)
            newKey = ""
        }
    }

    /// Moves to another server, asking first what becomes of this one's copy if changes wait in it.
    func switchServer(_ choice: Choice? = nil) async {
        guard choice != nil || canSwitch else { return }
        await run { () async throws(MarfaHost.Problem) in
            await beforeChange()
            try await host.changeAddress(to: otherAddress, key: otherKey, choice: hostChoice(choice))
            otherAddress = ""
            otherKey = ""
            departure = nil
        } onWaiting: { [self] unsent in
            ask(.switchServer, unsent, askedAgain: choice != nil)
        }
    }

    /// A disconnect with nothing waiting is confirmed once, since it forgets the key. With changes waiting, the
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
        await run { () async throws(MarfaHost.Problem) in
            await beforeChange()
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
        case .switchServer: await switchServer(choice)
        }
    }

    /// Nothing is left, nothing is discarded.
    func cancelDeparture() {
        departure = nil
    }

    // MARK: Words

    /// A problem in the app's words: what happened, and what to do. Nil for the question about changes that
    /// wait, which is asked rather than told.
    static func notice(for problem: MarfaHost.Problem) -> Notice? {
        switch problem {
        case .changesWaiting:
            nil
        case .notAServer:
            Notice(
                title: String(localized: "Check the Address"),
                message: String(localized: "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://."))
        case .noKey:
            Notice(title: String(localized: "Enter a Key"), message: String(localized: "Paste the key for this server."))
        case .unavailable(let message):
            Notice(
                title: String(localized: "Can’t Open the Library"),
                message: message.isEmpty
                    ? String(localized: "The copy of your library on this Mac can’t be opened.")
                    : String(localized: "The copy of your library on this Mac can’t be opened. \(message)"))
        case .keyStore:
            Notice(
                title: String(localized: "Can’t Keep the Key"),
                message: String(localized: "The Keychain wouldn’t take the key. Check that MAPP can use the Keychain, then try again."))
        case .keyRefused:
            Notice(
                title: String(localized: "Key refused"),
                message: String(localized: "The server doesn’t accept that key. Check it and try again. The key you had is kept."))
        case .serverUnreachable:
            Notice(
                title: String(localized: "Can’t Reach the Server"),
                message: String(localized: "MAPP couldn’t ask the server about the key. Check the address and your connection, then try again. The key you had is kept."))
        case .notRemoved(let key, let copy):
            Notice(title: String(localized: "Disconnected, but Not Everything Was Removed"), message: removalMessage(key: key, copy: copy))
        case .notConnected:
            Notice(title: String(localized: "Not connected"), message: String(localized: "Connect to a server first."))
        case .busy:
            Notice(title: String(localized: "Still Working"), message: String(localized: "Wait for the current step to finish, then try again."))
        }
    }

    private static func removalMessage(key: String?, copy: String?) -> String {
        switch (key != nil, copy != nil) {
        case (true, true):
            String(localized: "The key is still in your Keychain, and the copy is still on this Mac. Remove the key in Keychain Access. MAPP removes the copy before it connects to that server again.")
        case (true, false):
            String(localized: "The key is still in your Keychain. Remove it in Keychain Access.")
        default:
            String(localized: "The copy is still on this Mac. MAPP removes it before it connects to that server again.")
        }
    }

    // MARK: Running a step

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
                notice = Self.notice(for: error)
            }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
