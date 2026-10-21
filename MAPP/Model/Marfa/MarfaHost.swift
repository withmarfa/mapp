import Foundation
import Marfa
import Observation

/// A source read from a server: its items, what it has yet to send, and how the server stands.
nonisolated protocol ConnectedItemSource: ItemSource, SyncReporting {
    var connectionState: MarfaConnectionState { get }
    func connectionStates() -> AsyncStream<MarfaConnectionState>
}

/// What the host needs of a Marfa library beside reading and writing it, so its lifecycle is tested without a
/// server.
nonisolated protocol MarfaHostedSource: ConnectedItemSource {
    /// Hydrates or catches up, then sends what waits; never waited on.
    func refresh()
    /// The writes not sent once every write submitted before the call is in the queue; nil where the queue
    /// cannot be read.
    func unsentWrites() async -> UnsentWrites?
    /// Closes only if every write not sent, read in the same step, is one of `agreed` (nil agrees to whatever
    /// the copy holds); otherwise stays open and answers what is not sent.
    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome
}

extension MarfaSource: MarfaHostedSource {}

/// The Marfa library the app is connected to, from the address the person gives and the sign-in they approve in
/// the browser. The address is kept in defaults, the sign-in by `MarfaSignIn`, and the copy in its own directory,
/// so a launch paints from the copy before asking the server anything. The words for each state are the app's.
@Observable @MainActor final class MarfaHost {
    typealias Opener = @Sendable (MarfaConnection, Server, MarfaStoreLocation) async throws -> any MarfaHostedSource

    nonisolated enum State: Hashable, Sendable {
        case disconnected
        /// Showing the copy, not yet heard from the server.
        case connecting
        case online
        /// Writes wait in the copy and go when the server can be reached.
        case offline(reason: String?)
        /// The server ended the sign-in, or none is kept; the person signs in again in Settings, and writes wait
        /// in the copy until then.
        case signedOut
        /// The copy cannot be opened or followed; the message is the package's.
        case unavailable(message: String)
    }

    /// What becomes of the copy, and every write still in it, when it is left.
    nonisolated enum DisconnectChoice: Hashable, Sendable {
        /// Left on disk, so connecting the same address again goes on from it and sends what waits.
        case keepCopy
        /// Removed with the writes the person was shown in `changesWaiting`, which they agreed to lose. A write
        /// not among them, such as a late save, keeps the copy and the person is asked again. Nil agrees to
        /// whatever a copy that could not be read holds.
        case discardCopy(UnsentWrites?)
    }

    nonisolated enum Problem: Error, Hashable, Sendable {
        case notAServer
        /// The person closed the browser before deciding, so nothing changed.
        case signInCanceled
        /// The person declined to approve MAPP on the server.
        case notApproved
        /// The sign-in could not finish; the message is the package's.
        case signInFailed(message: String)
        /// No sign-in is kept for the server, or the server ended it.
        case signedOut
        /// Writes still wait in the copy being left, so the person chooses what becomes of them, and a choice
        /// to discard names these; asked again when others arrive after it. Nil where the copy could not be
        /// read and may hold some.
        case changesWaiting(UnsentWrites?)
        /// The copy could not be opened or read.
        case unavailable(message: String)
        /// The keychain would not give the sign-in.
        case keychain(message: String)
        /// The connection was left, but its sign-in is still kept, or the copy the person discarded is still on
        /// disk, or both; each message says why. A discarded copy is never opened as it is: connecting its
        /// address again removes it first, or fails with this.
        case notRemoved(signIn: String?, copy: String?)
        case notConnected
        /// Another connect, disconnect or sign-in is under way.
        case busy
    }

    private static let addressKey = "MarfaAddress"
    /// Addresses whose copy the person discarded but which could not be removed.
    private static let discardedKey = "MarfaDiscardedCopies"

    private let defaults: UserDefaults
    private let signIns: any MarfaSignIn
    private let location: MarfaStoreLocation
    private let opener: Opener

    /// The address connected to, kept while its copy cannot be opened, so Settings can sign in to it again.
    private(set) var connection: MarfaConnection?
    private(set) var state = State.disconnected
    /// The library to show, once its copy is open.
    private(set) var source: (any MarfaHostedSource)?
    private(set) var report = SyncReport()
    private(set) var isBusy = false
    private var watching: [Task<Void, Never>] = []
    /// Hands every open page's last edit to the library it came from. The host runs it before the windows change
    /// library and again right before it reads or closes a copy, so text typed while a step waited on the network
    /// is in the copy when it closes. Set by the app; tests may set none.
    @ObservationIgnored var handOverEdits: () async -> Bool = { true }

    init(
        defaults: UserDefaults, signIns: any MarfaSignIn, location: MarfaStoreLocation,
        opener: @escaping Opener = { try await MarfaSource.open($0, server: $1, location: $2) }
    ) {
        self.defaults = defaults
        self.signIns = signIns
        self.location = location
        self.opener = opener
    }

    /// The server the app is set to read from: the one connected to, or the one saved by an earlier launch before
    /// its copy is opened, so a window can say it is opening a library rather than show another.
    var configuredConnection: MarfaConnection? {
        connection ?? defaults.string(forKey: Self.addressKey).flatMap { try? MarfaConnection(address: $0) }
    }

    /// Writes in the copy that the server has not taken, problems included, as last reported, for showing; nil
    /// where no open copy can say. Leaving a copy asks the copy itself.
    var waitingChanges: Int? {
        if source != nil, report.queueRead { return report.changesNotSent }
        guard let connection else { return 0 }
        return hasCopy(connection) ? nil : 0
    }

    /// Opens the saved library's copy and paints from it, then asks the server.
    func launch() async {
        guard !isBusy, source == nil, let saved = defaults.string(forKey: Self.addressKey),
            let connection = try? MarfaConnection(address: saved)
        else { return }
        isBusy = true
        defer { isBusy = false }
        self.connection = connection
        _ = try? await open(connection)
    }

    /// Signs in to the server at `address` through `browser` and connects to it, keeping the address once the
    /// copy opens. Connecting while connected changes the address, or signs in again where it is the same.
    func connect(address: String, with browser: @escaping MarfaBrowser) async throws(Problem) {
        let connection = try Self.validated(address)
        if let current = self.connection {
            if current == connection { return try await signInAgain(with: browser) }
            return try await changeAddress(to: address, with: browser)
        }
        try begin()
        defer { isBusy = false }
        guard await handOverEdits() else { throw Self.editing }
        try await signIn(to: connection, with: browser)
        do {
            try await open(connection)
        } catch {
            await signOutQuietly(connection)
            state = .disconnected
            throw error
        }
        remember(connection)
    }

    /// Closes the copy, signs out and forgets the address. `choice` is needed while writes wait in the copy, and
    /// is asked for again when more arrive after it; with nothing waiting and no choice the copy is removed, since
    /// a later connection pulls it again.
    func disconnect(_ choice: DisconnectChoice? = nil) async throws(Problem) {
        guard let connection else { return }
        try begin()
        defer { isBusy = false }
        if let source {
            try await close(source, for: choice)
        } else if choice == nil, hasCopy(connection) {
            throw .changesWaiting(nil)
        }
        detach()
        // The address goes first, so a quit while the sign-in and the copy are removed never opens this server
        // again at the next launch, signed out.
        defaults.removeObject(forKey: Self.addressKey)
        self.connection = nil
        state = .disconnected
        report = SyncReport()
        if let problem = await finishLeaving(connection, discarding: choice != .keepCopy) { throw problem }
    }

    /// Signs in to the server connected to again, for a sign-in the server ended. The copy is opened again on
    /// the new sign-in and keeps every write waiting in it; the server takes the writes the old sign-in held
    /// back at the next drain. A sign-in that does not finish changes nothing.
    func signInAgain(with browser: @escaping MarfaBrowser) async throws(Problem) {
        guard let connection else { throw .notConnected }
        try begin()
        defer { isBusy = false }
        try await signIn(to: connection, with: browser)
        if let source {
            guard await handOverEdits() else { throw Self.editing }
            detach()
            state = .connecting
            await source.close()
        }
        try await open(connection)
    }

    /// Moves to another server's library, signing in to it through `browser` first. Another address is another
    /// copy, so writes waiting in this one need the person's `choice`, asked for again when more arrive while the
    /// new copy opens. The new copy is opened before this one is left, so a failure leaves things as they were.
    func changeAddress(
        to address: String, with browser: @escaping MarfaBrowser, choice: DisconnectChoice? = nil
    ) async throws(Problem) {
        let connection = try Self.validated(address)
        guard let old = self.connection else { return try await connect(address: address, with: browser) }
        if connection == old { return try await signInAgain(with: browser) }
        try begin()
        defer { isBusy = false }
        let current = source
        if current != nil { guard await handOverEdits() else { throw Self.editing } }
        if let current, choice == nil {
            let unsent = await current.unsentWrites()
            if unsent?.ids.isEmpty != true { throw .changesWaiting(unsent) }
        } else if current == nil, choice == nil, hasCopy(old) {
            throw .changesWaiting(nil)
        }
        let fresh = !hasCopy(connection)
        try await signIn(to: connection, with: browser)
        let opened: any MarfaHostedSource
        do {
            try await clearDiscarded(connection)
            opened = try await Self.open(connection, signIns: signIns, location: location, with: opener)
        } catch {
            await signOutQuietly(connection)
            throw error
        }
        if let current {
            do {
                try await close(current, for: choice)
            } catch {
                // The move is abandoned, so the sign-in and the copy made for it go too.
                await opened.close()
                await signOutQuietly(connection)
                if fresh { try? await removeCopy(connection) }
                throw error
            }
        }
        // The new copy is shown before the old one's sign-in and copy are removed, so the windows go from one
        // library to the other and never show the notes folder between them.
        remember(connection)
        attach(opened)
        if let problem = await finishLeaving(old, discarding: choice != .keepCopy) { throw problem }
    }

    // MARK: Lifecycle

    private func begin() throws(Problem) {
        guard !isBusy else { throw .busy }
        isBusy = true
    }

    private static var editing: Problem {
        .unavailable(message: String(localized: "Finish editing the current note before changing libraries."))
    }

    private static func validated(_ address: String) throws(Problem) -> MarfaConnection {
        do {
            return try MarfaConnection(address: address)
        } catch {
            throw .notAServer
        }
    }

    private func remember(_ connection: MarfaConnection) {
        self.connection = connection
        defaults.set(connection.address.absoluteString, forKey: Self.addressKey)
    }

    private func hasCopy(_ connection: MarfaConnection) -> Bool {
        FileManager.default.fileExists(atPath: location.directory(for: connection).path)
    }

    /// Shows the server's sign-in through `browser` and keeps what the person approves, in place of any sign-in
    /// kept before. Nothing else changes until it has finished.
    private func signIn(to connection: MarfaConnection, with browser: MarfaBrowser) async throws(Problem) {
        do {
            try await signIns.signIn(to: connection, with: browser)
        } catch let error as SignInError {
            throw Self.problem(error)
        } catch {
            throw .signInFailed(message: Self.message(error))
        }
    }

    nonisolated static func problem(_ error: SignInError) -> Problem {
        switch error {
        case .canceled: .signInCanceled
        case .denied: .notApproved
        case .notAServer: .notAServer
        case .notSignedIn: .signedOut
        case .unavailable(let message), .unreadable(let message): .signInFailed(message: message)
        default: .signInFailed(message: error.description)
        }
    }

    /// For a sign-in made for a step that did not finish. The keychain no longer holds it either way.
    private func signOutQuietly(_ connection: MarfaConnection) async {
        try? await signIns.signOut(of: connection)
    }

    /// Closes `source` as `choice` allows. A kept copy loses nothing, so it closes whatever waits. Otherwise the
    /// copy reads its own queue, once the writes submitted before now are in it, and closes in the same step
    /// only if every write not sent is one the person agreed to lose: none, without a choice.
    private func close(_ source: any MarfaHostedSource, for choice: DisconnectChoice?) async throws(Problem) {
        guard await handOverEdits() else { throw Self.editing }
        let agreed: UnsentWrites?
        switch choice {
        case .keepCopy:
            await source.close()
            return
        case .discardCopy(let shown): agreed = shown
        case nil: agreed = UnsentWrites(ids: [])
        }
        if case .waiting(let unsent) = await source.close(agreeing: agreed) { throw .changesWaiting(unsent) }
    }

    /// Opens the copy and paints from it; the server is asked only after.
    private func open(_ connection: MarfaConnection) async throws(Problem) {
        state = .connecting
        do {
            try await clearDiscarded(connection)
            attach(try await Self.open(connection, signIns: signIns, location: location, with: opener))
        } catch {
            switch error {
            case .signedOut: state = .signedOut
            case .unavailable(let message): state = .unavailable(message: message)
            default: state = .disconnected
            }
            throw error
        }
    }

    /// Reads the sign-in off the main actor, since the keychain can take a while, and opens the copy with it.
    private static func open(
        _ connection: MarfaConnection, signIns: any MarfaSignIn, location: MarfaStoreLocation, with opener: Opener
    ) async throws(Problem) -> any MarfaHostedSource {
        let server: Server
        do {
            guard let kept = try await offMain({ try signIns.server(for: connection) }) else { throw Problem.signedOut }
            server = kept
        } catch let problem as Problem {
            throw problem
        } catch let error as SignInError {
            throw problem(error)
        } catch {
            throw .keychain(message: Self.message(error))
        }
        do {
            return try await opener(connection, server, location)
        } catch let failure as SourceFailure {
            // A source refuses to open only for a sign-in gone since it was read.
            if failure.kind == .denied { throw .signedOut }
            throw .unavailable(message: failure.message)
        } catch {
            throw .unavailable(message: Self.message(error))
        }
    }

    private func attach(_ source: any MarfaHostedSource) {
        detach()
        self.source = source
        state = Self.state(source.connectionState)
        report = source.syncReport
        let states = source.connectionStates()
        let reports = source.syncReports()
        // A value already on its way from a source that has since been left is dropped.
        watching = [
            Task { [weak self] in
                for await state in states where self?.source === source { self?.state = Self.state(state) }
            },
            Task { [weak self] in
                for await report in reports where self?.source === source { self?.report = report }
            }
        ]
        source.refresh()
    }

    private func detach() {
        for task in watching { task.cancel() }
        watching = []
        source = nil
    }

    /// Signs out, and removes the copy where it was discarded, once the copy is closed. A discarded copy is marked
    /// before anything is removed and unmarked only once it is gone, so neither a removal that fails nor a quit
    /// part way lets it be opened again as it was.
    private func finishLeaving(_ connection: MarfaConnection, discarding: Bool) async -> Problem? {
        if discarding { markDiscarded(connection, true) }
        var signIn: String?
        var copy: String?
        do {
            try await signIns.signOut(of: connection)
        } catch {
            signIn = Self.message(error)
        }
        if discarding {
            do {
                try await removeCopy(connection)
                markDiscarded(connection, false)
            } catch {
                copy = Self.message(error)
            }
        }
        return signIn == nil && copy == nil ? nil : .notRemoved(signIn: signIn, copy: copy)
    }

    private func markDiscarded(_ connection: MarfaConnection, _ marked: Bool) {
        let address = connection.address.absoluteString
        var discarded = defaults.stringArray(forKey: Self.discardedKey) ?? []
        discarded.removeAll { $0 == address }
        if marked { discarded.append(address) }
        defaults.set(discarded, forKey: Self.discardedKey)
    }

    /// A copy the person discarded is removed before its address is opened again, or not opened at all.
    private func clearDiscarded(_ connection: MarfaConnection) async throws(Problem) {
        guard (defaults.stringArray(forKey: Self.discardedKey) ?? []).contains(connection.address.absoluteString)
        else { return }
        do {
            try await removeCopy(connection)
        } catch {
            throw .notRemoved(signIn: nil, copy: Self.message(error))
        }
        markDiscarded(connection, false)
    }

    private func removeCopy(_ connection: MarfaConnection) async throws {
        let directory = location.directory(for: connection)
        try await Self.offMain {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private static func message(_ error: any Error) -> String {
        error.localizedDescription
    }

    static func state(_ state: MarfaConnectionState) -> State {
        switch state {
        case .connecting: .connecting
        case .online: .online
        case .offline(let reason): .offline(reason: reason)
        case .signedOut: .signedOut
        case .stopped(_, let message): .unavailable(message: message)
        }
    }

    /// The keychain and the disk can each take a while, which the main actor never waits on.
    @concurrent private nonisolated static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
