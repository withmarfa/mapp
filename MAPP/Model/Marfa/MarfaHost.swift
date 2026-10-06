import Foundation
import Observation

/// What the host needs of a Marfa library beside reading and writing it, so its lifecycle is tested without a
/// server.
nonisolated protocol MarfaHostedSource: ItemSource, SyncReporting {
    var connectionState: MarfaConnectionState { get }
    func connectionStates() -> AsyncStream<MarfaConnectionState>
    /// Hydrates or catches up, then sends what waits; never waited on.
    func refresh()
    /// Goes on with `key` whatever the server answers, so a caller that keeps another key gives that one back.
    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck
    /// The report once every write submitted before the call is in the queue.
    func settledReport() async -> SyncReport
    /// Closes only if no more than `limit` writes are not sent once every write submitted before the call is in
    /// the queue, deciding and closing in one step; otherwise answers the report that kept it open.
    func close(unlessUnsentExceeds limit: Int) async -> SyncReport?
}

extension MarfaSource: MarfaHostedSource {}

/// The Marfa library the app is connected to, from the address and key the person gives to the copy it opens.
/// The address is kept in defaults, the key in the key store, and the copy in its own directory, so a launch
/// paints from the copy before asking the server anything. The words for each state are the app's.
@Observable @MainActor final class MarfaHost {
    typealias Opener = @Sendable (MarfaConnection, any KeyStore, MarfaStoreLocation) async throws -> any MarfaHostedSource

    nonisolated enum State: Hashable, Sendable {
        case disconnected
        /// Showing the copy, not yet heard from the server.
        case connecting
        case online
        /// Writes wait in the copy and go when the server can be reached.
        case offline(reason: String?)
        /// Settings takes another key.
        case keyRefused
        /// The copy cannot be opened or followed; the message is the package's.
        case unavailable(message: String)
    }

    /// What becomes of the copy, and every write still in it, when it is left.
    nonisolated enum DisconnectChoice: Hashable, Sendable {
        /// Left on disk, so connecting the same address again goes on from it and sends what waits.
        case keepCopy
        /// Removed with every write it holds.
        case discardCopy
    }

    nonisolated enum Problem: Error, Hashable, Sendable {
        case notAServer
        /// None was given, or the key store holds none for the address.
        case noKey
        /// Writes still wait in the copy being left, so the person chooses what becomes of them; asked again when
        /// more arrive after the choice. Nil where the copy could not be read and may hold some.
        case changesWaiting(Int?)
        /// The copy could not be opened or read.
        case unavailable(message: String)
        /// The key store would not take or give the key.
        case keyStore(message: String)
        /// The server refused the key given; the key that was there is kept.
        case keyRefused
        /// The server could not be asked whether it takes the key given, so the key that was there is kept.
        case serverUnreachable(reason: String?)
        /// The connection was left, but its key is still in the key store.
        case keyNotRemoved(message: String)
        /// The copy the person discarded is still on disk. It is never opened as it is: connecting its address
        /// again removes it first, or fails with this.
        case copyNotRemoved(message: String)
        case notConnected
        /// Another connect, disconnect or change of key is under way.
        case busy
    }

    private static let addressKey = "MarfaAddress"
    /// Addresses whose copy the person discarded but which could not be removed.
    private static let discardedKey = "MarfaDiscardedCopies"

    private let defaults: UserDefaults
    private let keys: any KeyStore
    private let location: MarfaStoreLocation
    private let opener: Opener

    /// The address connected to, kept while its copy cannot be opened, so Settings can offer a key for it.
    private(set) var connection: MarfaConnection?
    private(set) var state = State.disconnected
    /// The library to show, once its copy is open.
    private(set) var source: (any MarfaHostedSource)?
    private(set) var report = SyncReport()
    private(set) var isBusy = false
    private var watching: [Task<Void, Never>] = []

    init(
        defaults: UserDefaults, keys: any KeyStore, location: MarfaStoreLocation,
        opener: @escaping Opener = { try await MarfaSource.open($0, keys: $1, location: $2) }
    ) {
        self.defaults = defaults
        self.keys = keys
        self.location = location
        self.opener = opener
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

    /// Connects to `address` with `key`, keeping both once the copy opens. Connecting while connected changes
    /// the address, or only the key where the address is the same.
    func connect(address: String, key: String) async throws(Problem) {
        let (connection, key) = try Self.validated(address, key)
        if let current = self.connection {
            if current == connection { return try await replaceKey(key) }
            return try await changeAddress(to: address, key: key)
        }
        try begin()
        defer { isBusy = false }
        try await save(key, for: connection)
        do {
            try await open(connection)
        } catch {
            try? await Self.offMain { [keys] in try keys.delete(for: connection) }
            state = .disconnected
            throw error
        }
        remember(connection)
    }

    /// Closes the copy and forgets the address and key. `choice` is needed while writes wait in the copy, and is
    /// asked for again when more arrive after it; with nothing waiting and no choice the copy is removed, since a
    /// later connection pulls it again.
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
        let problem = await finishLeaving(connection, choice ?? .discardCopy)
        defaults.removeObject(forKey: Self.addressKey)
        self.connection = nil
        state = .disconnected
        report = SyncReport()
        if let problem { throw problem }
    }

    /// Takes a new key for the address connected to, for a key refused or replaced on the server. A key that
    /// works is kept until the server has taken the new one: a key the server refuses, or cannot be asked
    /// about, is not stored and the copy goes back to the old one. Where the old key was already refused there
    /// is nothing to keep, so a new key the server cannot be asked about is kept to try later. Writes the
    /// refused key held back go with the next drain, as the contract has them clear on their own.
    func replaceKey(_ key: String) async throws(Problem) {
        guard let connection else { throw .notConnected }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .noKey }
        try begin()
        defer { isBusy = false }
        let old = try? await Self.offMain { [keys] in try keys.key(for: connection) }
        guard let source else {
            // With no copy open there is no server to ask first; the copy opens with the new key or not at all.
            try await save(key, for: connection)
            do {
                try await open(connection)
            } catch {
                if let old { try? await save(old, for: connection) }
                throw error
            }
            return
        }
        let oldRefused = old == nil || source.connectionState == .keyRefused
        let check: MarfaSync.KeyCheck
        do {
            check = try await source.tryKey(key)
        } catch {
            // A copy that could not take the key closed; it opens again with the key that is stored.
            detach()
            await source.close()
            if oldRefused { try await save(key, for: connection) }
            try await open(connection)
            throw .unavailable(message: (error as? SourceFailure)?.message ?? error.localizedDescription)
        }
        switch check {
        case .accepted:
            try await save(key, for: connection)
        case .refused:
            if let old { _ = try? await source.tryKey(old) }
            throw .keyRefused
        case .unanswered(let reason):
            if oldRefused { return try await save(key, for: connection) }
            if let old { _ = try? await source.tryKey(old) }
            throw .serverUnreachable(reason: reason)
        }
    }

    /// Moves to another server's library. Another address is another copy, so writes waiting in this one need
    /// the person's `choice`, asked for again when more arrive while the new copy opens. The new copy is opened
    /// before this one is left, so a failure leaves things as they were.
    func changeAddress(to address: String, key: String, choice: DisconnectChoice? = nil) async throws(Problem) {
        let (connection, key) = try Self.validated(address, key)
        guard let old = self.connection else { return try await connect(address: address, key: key) }
        if connection == old { return try await replaceKey(key) }
        try begin()
        defer { isBusy = false }
        let current = source
        var allowed = Int.max
        if let current, choice != .keepCopy {
            let seen = await current.settledReport()
            let unsent = seen.queueRead ? seen.changesNotSent : nil
            if choice == nil, unsent != 0 { throw .changesWaiting(unsent) }
            allowed = choice == nil ? 0 : unsent ?? .max
        } else if current == nil, choice == nil, hasCopy(old) {
            throw .changesWaiting(nil)
        }
        try await save(key, for: connection)
        let opened: any MarfaHostedSource
        do {
            try await clearDiscarded(connection)
            opened = try await Self.open(connection, keys: keys, location: location, with: opener)
        } catch {
            try? await Self.offMain { [keys] in try keys.delete(for: connection) }
            throw error
        }
        if let current {
            do {
                try await close(current, for: choice, allowing: allowed)
            } catch {
                await opened.close()
                try? await Self.offMain { [keys] in try keys.delete(for: connection) }
                throw error
            }
        }
        detach()
        let problem = await finishLeaving(old, choice ?? .discardCopy)
        remember(connection)
        attach(opened)
        if let problem { throw problem }
    }

    // MARK: Lifecycle

    private func begin() throws(Problem) {
        guard !isBusy else { throw .busy }
        isBusy = true
    }

    private static func validated(_ address: String, _ key: String) throws(Problem) -> (MarfaConnection, String) {
        let connection: MarfaConnection
        do {
            connection = try MarfaConnection(address: address)
        } catch {
            throw .notAServer
        }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .noKey }
        return (connection, key)
    }

    private func remember(_ connection: MarfaConnection) {
        self.connection = connection
        defaults.set(connection.address.absoluteString, forKey: Self.addressKey)
    }

    private func hasCopy(_ connection: MarfaConnection) -> Bool {
        FileManager.default.fileExists(atPath: location.directory(for: connection).path)
    }

    private func save(_ key: String, for connection: MarfaConnection) async throws(Problem) {
        do {
            try await Self.offMain { [keys] in try keys.save(key, for: connection) }
        } catch {
            throw .keyStore(message: error.localizedDescription)
        }
    }

    /// Closes `source` as `choice` allows: a kept copy loses nothing, so it closes whatever waits; otherwise it
    /// closes only if no more than `allowing` writes are not sent, counted by the copy once the writes submitted
    /// before now are queued, so a write made a moment ago is never discarded unasked.
    private func close(
        _ source: any MarfaHostedSource, for choice: DisconnectChoice?, allowing limit: Int? = nil
    ) async throws(Problem) {
        if choice == .keepCopy {
            await source.close()
            return
        }
        var allowed = limit ?? 0
        if limit == nil, choice == .discardCopy {
            let seen = await source.settledReport()
            allowed = seen.queueRead ? seen.changesNotSent : .max
        }
        if let kept = await source.close(unlessUnsentExceeds: allowed) {
            report = kept
            throw .changesWaiting(kept.queueRead ? kept.changesNotSent : nil)
        }
    }

    /// Opens the copy and paints from it; the server is asked only after.
    private func open(_ connection: MarfaConnection) async throws(Problem) {
        state = .connecting
        do {
            try await clearDiscarded(connection)
            attach(try await Self.open(connection, keys: keys, location: location, with: opener))
        } catch {
            switch error {
            case .noKey: state = .keyRefused
            case .unavailable(let message): state = .unavailable(message: message)
            default: state = .disconnected
            }
            throw error
        }
    }

    private static func open(
        _ connection: MarfaConnection, keys: any KeyStore, location: MarfaStoreLocation, with opener: Opener
    ) async throws(Problem) -> any MarfaHostedSource {
        do {
            return try await opener(connection, keys, location)
        } catch let failure as SourceFailure {
            // A source refuses to open only for want of a key.
            if failure.kind == .denied { throw .noKey }
            throw .unavailable(message: failure.message)
        } catch {
            throw .unavailable(message: error.localizedDescription)
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

    /// Removes the key, and the copy where it was discarded, once the copy is closed. A copy that cannot be
    /// removed is remembered, so it is never opened again as it was.
    private func finishLeaving(_ connection: MarfaConnection, _ choice: DisconnectChoice) async -> Problem? {
        var problem: Problem?
        do {
            try await Self.offMain { [keys] in try keys.delete(for: connection) }
        } catch {
            problem = .keyNotRemoved(message: error.localizedDescription)
        }
        guard choice == .discardCopy else { return problem }
        do {
            try await removeCopy(connection)
        } catch {
            var discarded = defaults.stringArray(forKey: Self.discardedKey) ?? []
            if !discarded.contains(connection.address.absoluteString) {
                discarded.append(connection.address.absoluteString)
            }
            defaults.set(discarded, forKey: Self.discardedKey)
            return .copyNotRemoved(message: error.localizedDescription)
        }
        return problem
    }

    /// A copy the person discarded is removed before its address is opened again, or not opened at all.
    private func clearDiscarded(_ connection: MarfaConnection) async throws(Problem) {
        var discarded = defaults.stringArray(forKey: Self.discardedKey) ?? []
        guard discarded.contains(connection.address.absoluteString) else { return }
        do {
            try await removeCopy(connection)
        } catch {
            throw .copyNotRemoved(message: error.localizedDescription)
        }
        discarded.removeAll { $0 == connection.address.absoluteString }
        defaults.set(discarded, forKey: Self.discardedKey)
    }

    private func removeCopy(_ connection: MarfaConnection) async throws {
        let directory = location.directory(for: connection)
        try await Self.offMain {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private static func state(_ state: MarfaConnectionState) -> State {
        switch state {
        case .connecting: .connecting
        case .online: .online
        case .offline(let reason): .offline(reason: reason)
        case .keyRefused: .keyRefused
        case .stopped(_, let message): .unavailable(message: message)
        }
    }

    /// The keychain and the disk can each take a while, which the main actor never waits on.
    @concurrent private nonisolated static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
