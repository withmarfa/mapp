import Foundation
import Observation

/// What the host needs of a Marfa library beside reading and writing it, so its lifecycle is tested without a
/// server.
nonisolated protocol MarfaHostedSource: ItemSource, SyncReporting {
    var connectionState: MarfaConnectionState { get }
    func connectionStates() -> AsyncStream<MarfaConnectionState>
    /// Hydrates or catches up, then sends what waits; never waited on.
    func refresh()
    func useKey(_ key: String) async throws
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
        /// Writes still wait in the copy being left, so the person chooses what becomes of them. Nil where the
        /// copy could not be read and may hold some.
        case changesWaiting(Int?)
        /// The copy could not be opened or read.
        case unavailable(message: String)
        /// The key store would not take or give the key.
        case keyStore(message: String)
        case notConnected
        /// Another connect, disconnect or change of key is under way.
        case busy
    }

    private static let addressKey = "MarfaAddress"

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

    /// Writes in the copy that the server has not taken, problems included, which leaving it would lose; nil
    /// where no open copy can say.
    var waitingChanges: Int? {
        if source != nil, report.queueRead { return report.changesNotSent }
        guard let connection else { return 0 }
        return FileManager.default.fileExists(atPath: location.directory(for: connection).path) ? nil : 0
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

    /// Closes the copy and forgets the address and key. `choice` is needed while writes wait in the copy, and
    /// otherwise removes the copy unless it says to keep it, since a later connection pulls it again.
    func disconnect(_ choice: DisconnectChoice? = nil) async throws(Problem) {
        guard let connection else { return }
        if choice == nil, waitingChanges != 0 { throw .changesWaiting(waitingChanges) }
        try begin()
        defer { isBusy = false }
        await leave(connection, choice ?? .discardCopy)
        defaults.removeObject(forKey: Self.addressKey)
        self.connection = nil
        state = .disconnected
        report = SyncReport()
    }

    /// Takes a new key for the address connected to: for a key refused or replaced on the server. Writes the
    /// refused key held back go with the next drain, as the contract has them clear on their own.
    func replaceKey(_ key: String) async throws(Problem) {
        guard let connection else { throw .notConnected }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .noKey }
        try begin()
        defer { isBusy = false }
        try await save(key, for: connection)
        if let source {
            do {
                try await source.useKey(key)
                return
            } catch {
                // A copy that could not take the key is closed; it is opened again with the key just saved.
                detach()
                await source.close()
            }
        }
        try await open(connection)
    }

    /// Moves to another server's library. Another address is another copy, so writes waiting in this one need
    /// the person's `choice`; the copy for the new address is opened before this one is left, so a failure
    /// leaves things as they were.
    func changeAddress(to address: String, key: String, choice: DisconnectChoice? = nil) async throws(Problem) {
        let (connection, key) = try Self.validated(address, key)
        guard let old = self.connection else { return try await connect(address: address, key: key) }
        if connection == old { return try await replaceKey(key) }
        if choice == nil, waitingChanges != 0 { throw .changesWaiting(waitingChanges) }
        try begin()
        defer { isBusy = false }
        try await save(key, for: connection)
        let opened: any MarfaHostedSource
        do {
            opened = try await Self.open(connection, keys: keys, location: location, with: opener)
        } catch {
            try? await Self.offMain { [keys] in try keys.delete(for: connection) }
            throw error
        }
        await leave(old, choice ?? .discardCopy)
        remember(connection)
        attach(opened)
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

    private func save(_ key: String, for connection: MarfaConnection) async throws(Problem) {
        do {
            try await Self.offMain { [keys] in try keys.save(key, for: connection) }
        } catch {
            throw .keyStore(message: error.localizedDescription)
        }
    }

    /// Opens the copy and paints from it; the server is asked only after.
    private func open(_ connection: MarfaConnection) async throws(Problem) {
        state = .connecting
        do {
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
        watching = [
            Task { [weak self] in
                for await state in states { self?.state = Self.state(state) }
            },
            Task { [weak self] in
                for await report in reports { self?.report = report }
            }
        ]
        source.refresh()
    }

    private func detach() {
        for task in watching { task.cancel() }
        watching = []
        source = nil
    }

    private func leave(_ connection: MarfaConnection, _ choice: DisconnectChoice) async {
        let source = self.source
        detach()
        await source?.close()
        let directory = location.directory(for: connection)
        try? await Self.offMain { [keys] in
            try keys.delete(for: connection)
            if choice == .discardCopy, FileManager.default.fileExists(atPath: directory.path) {
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
    @concurrent private nonisolated static func offMain(_ work: @Sendable () throws -> Void) async throws {
        try work()
    }
}
