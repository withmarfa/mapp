import Foundation
import Marfa
import Observation

/// The Marfa library the app is connected to, from the address and key the person gives to the copy it opens.
/// The address is kept in defaults, the key in the key store, and the copy in its own directory, so a launch
/// paints from the copy before asking the server anything. The words for each state are the app's.
@Observable @MainActor final class MarfaHost {
    typealias Opener = @Sendable (MarfaConnection, any KeyStore, MarfaStoreLocation) async throws -> any ItemSource
    /// Reads the name the server at an address gives itself. It sends no key.
    typealias Describer = @Sendable (MarfaConnection) async throws -> String

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
        /// A different version of the app made the copy, so this one can't open it, and leaves it as it is. The
        /// changes in it that the server has not taken (`unsent`, never 0, and nil where that can't be read) can
        /// only be sent by that version.
        case otherVersion(unsent: UInt64?)
        /// Another copy of the app on this Mac holds the copy, so this one can't open it.
        case inUse
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
        /// None was given, or the key store holds none for the address.
        case noKey
        /// Writes still wait in the copy being left, so the person chooses what becomes of them, and a choice
        /// to discard names these; asked again when others arrive after it. Nil where the copy could not be
        /// read and may hold some.
        case changesWaiting(UnsentWrites?)
        /// The copy could not be opened or read.
        case unavailable(message: String)
        /// The copy was made by a different version of the app; see `State.otherVersion`.
        case otherVersion(unsent: UInt64?)
        /// Another copy of the app holds the copy; see `State.inUse`.
        case inUse
        /// The key store would not take or give the key.
        case keyStore(message: String)
        /// The server refused the key given; the key that was there is kept.
        case keyRefused
        /// The server could not be asked whether it takes the key given, so the key that was there is kept.
        case serverUnreachable(reason: String?)
        /// The connection was left, but its key is still in the key store, or the copy the person discarded is
        /// still on disk, or both; each message says why. A discarded copy is never opened as it is:
        /// connecting its address again removes it first, or fails with this.
        case notRemoved(key: String?, copy: String?)
        case notConnected
        /// Another connect, disconnect or change of key is under way.
        case busy
    }

    private static let addressKey = "MarfaAddress"
    /// Addresses whose copy the person discarded but which could not be removed.
    private static let discardedKey = "MarfaDiscardedCopies"
    /// The last name each server gave itself, by address, so a launch and an offline window show it.
    private static let namesKey = "MarfaInstanceNames"

    private let defaults: UserDefaults
    let keys: any KeyStore
    let location: MarfaStoreLocation
    private let opener: Opener
    private let describer: Describer

    /// The address connected to, kept while its copy cannot be opened, so Settings can offer a key for it.
    private(set) var connection: MarfaConnection?
    /// The library to show, once its copy is open. It holds how its server stands and what its copy last
    /// reported, so the host keeps neither while a copy is open.
    private(set) var library: MarfaLibrary?
    /// How the server stands while no copy is open: connecting to it, or why its copy could not be opened.
    private var standing = State.disconnected
    /// What the person is told, from this host and from every library it opens.
    let notices = Notices()
    private(set) var isBusy = false
    private var watching: [Task<Void, Never>] = []
    private var reading: Task<Void, Never>?
    private var instanceNames: [String: String]
    /// Hands every open page's last edit to the library it came from. The host runs it before the windows change
    /// library and again right before it reads or closes a copy, so text typed while a step waited on the network
    /// is in the copy when it closes. Set by the app; tests may set none.
    @ObservationIgnored var handOverEdits: () async -> Bool = { true }

    var source: (any ItemSource)? { library?.source }
    var state: State { library?.connection ?? standing }
    var report: SyncReport { library?.syncReport ?? SyncReport() }

    init(
        defaults: UserDefaults, keys: any KeyStore, location: MarfaStoreLocation,
        opener: @escaping Opener = { try await MarfaSource.open($0, keys: $1, location: $2) },
        describer: @escaping Describer = { try await $0.server(key: "").instanceDescription().name }
    ) {
        self.defaults = defaults
        self.keys = keys
        self.location = location
        self.opener = opener
        self.describer = describer
        instanceNames = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    /// The name the server at `connection` last gave itself, nil until one has been read.
    func instanceName(for connection: MarfaConnection) -> String? {
        instanceNames[connection.address.absoluteString]
    }

    /// The server the app is set to read from: the one connected to, or the one saved by an earlier launch before
    /// its copy is opened, so a window can say it is opening a library rather than show another.
    var configuredConnection: MarfaConnection? {
        connection ?? defaults.string(forKey: Self.addressKey).flatMap { try? MarfaConnection(address: $0) }
    }

    /// Writes in the copy that the server has not taken, problems included, as last reported, for showing; nil
    /// where no open copy can say. A copy made by a different version says how many it held when it was refused.
    /// Leaving a copy asks the copy itself.
    var waitingChanges: Int? {
        if source != nil, report.queueRead { return report.changesNotSent }
        if case .otherVersion(let unsent?) = state { return Int(clamping: unsent) }
        guard let connection else { return 0 }
        return hasCopy(connection) ? nil : 0
    }

    /// Whether the key kept for `connection` is `key`, so Settings forgets what was typed once the host holds it,
    /// whatever became of the step that gave it.
    func holds(_ key: String, for connection: MarfaConnection) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let kept = try? await Self.offMain({ [keys] in try keys.key(for: connection) }) else { return false }
        return kept == key
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
        guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current note before changing libraries.")) }
        try await save(key, for: connection)
        do {
            try await open(connection)
        } catch {
            try? await Self.offMain { [keys] in try keys.delete(for: connection) }
            standing = .disconnected
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
        forgetName(of: connection)
        // The address goes first, so a quit while the key and the copy are removed never opens this server again
        // at the next launch, with a key already gone.
        defaults.removeObject(forKey: Self.addressKey)
        self.connection = nil
        standing = .disconnected
        if let problem = await finishLeaving(connection, discarding: choice != .keepCopy) { throw problem }
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
            if oldRefused { try await save(key, for: connection) }
            try await reopen(source, connection, after: error)
        }
        switch check {
        case .accepted:
            try await save(key, for: connection)
        case .refused:
            try await giveBack(old, to: source, connection)
            throw .keyRefused
        case .unanswered(let reason):
            if oldRefused { return try await save(key, for: connection) }
            try await giveBack(old, to: source, connection)
            throw .serverUnreachable(reason: reason)
        }
    }

    /// Whatever the server makes of the old key, the copy goes on with it; a copy that closes on it is opened
    /// again, as one that closed on the new key is.
    private func giveBack(_ old: String?, to source: any ItemSource, _ connection: MarfaConnection) async throws(Problem) {
        guard let old else { return }
        do {
            _ = try await source.tryKey(old)
        } catch {
            try await reopen(source, connection, after: error)
        }
    }

    /// Once pending edits are saved, a copy that could not take a key reopens with the stored key.
    /// Recovery is deferred while an editor cannot hand over its changes.
    private func reopen(_ source: any ItemSource, _ connection: MarfaConnection, after error: any Error) async throws(Problem) -> Never {
        guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current note before changing libraries.")) }
        detach()
        standing = .connecting
        await source.close()
        try await open(connection)
        throw .unavailable(message: Self.message(error))
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
        if current != nil { guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current note before changing libraries.")) } }
        if let current, choice == nil {
            let unsent = await current.unsentWrites()
            if unsent?.ids.isEmpty != true { throw .changesWaiting(unsent) }
        } else if current == nil, choice == nil, hasCopy(old) {
            throw .changesWaiting(nil)
        }
        let fresh = !hasCopy(connection)
        try await save(key, for: connection)
        let opened: any ItemSource
        do {
            try await clearDiscarded(connection)
            opened = try await Self.open(connection, keys: keys, location: location, with: opener)
        } catch {
            try? await Self.offMain { [keys] in try keys.delete(for: connection) }
            throw error
        }
        if let current {
            do {
                try await close(current, for: choice)
            } catch {
                // The move is abandoned, so the copy made for it goes too.
                await opened.close()
                try? await Self.offMain { [keys] in try keys.delete(for: connection) }
                if fresh { try? await removeCopy(connection) }
                throw error
            }
        }
        // The new copy is shown before the old one's key and copy are removed, so the windows go from one library
        // to the other and never show the connect page between them.
        remember(connection)
        attach(opened, for: connection)
        forgetName(of: old)
        if let problem = await finishLeaving(old, discarding: choice != .keepCopy) { throw problem }
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

    #if DEBUG
    /// Sets the server a launch opens, for a debug build run against a test server. The key is the key store's.
    func presetTestServer(_ connection: MarfaConnection) {
        defaults.set(connection.address.absoluteString, forKey: Self.addressKey)
    }
    #endif

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
            throw .keyStore(message: Self.message(error))
        }
    }

    /// Closes `source` as `choice` allows. A kept copy loses nothing, so it closes whatever waits. Otherwise the
    /// copy reads its own queue, once the writes submitted before now are in it, and closes in the same step
    /// only if every write not sent is one the person agreed to lose: none, without a choice.
    private func close(_ source: any ItemSource, for choice: DisconnectChoice?) async throws(Problem) {
        guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current note before changing libraries.")) }
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
        standing = .connecting
        do {
            try await clearDiscarded(connection)
            attach(try await Self.open(connection, keys: keys, location: location, with: opener), for: connection)
        } catch {
            switch error {
            case .noKey: standing = .keyRefused
            case .unavailable(let message): standing = .unavailable(message: message)
            case .otherVersion(let unsent): standing = .otherVersion(unsent: unsent)
            case .inUse: standing = .inUse
            default: standing = .disconnected
            }
            throw error
        }
    }

    private static func open(
        _ connection: MarfaConnection, keys: any KeyStore, location: MarfaStoreLocation, with opener: Opener
    ) async throws(Problem) -> any ItemSource {
        do {
            return try await opener(connection, keys, location)
        } catch let failure as SourceFailure {
            // A source refuses to open only for want of a key.
            switch failure.kind {
            case .denied: throw .noKey
            case .otherVersion(let unsent): throw .otherVersion(unsent: unsent)
            case .inUse: throw .inUse
            case .missing, .failed: throw .unavailable(message: failure.message)
            }
        } catch {
            throw .unavailable(message: Self.message(error))
        }
    }

    private func attach(_ source: any ItemSource, for connection: MarfaConnection) {
        detach()
        let library = MarfaLibrary(source: source, notices: notices)
        self.library = library
        if let notice = connection.server(key: "").takePlainHTTPNotice() {
            notices.tell(Words.plainHTTPTitle, Words.plainHTTP(origin: notice.origin))
        }
        let states = source.connectionStates()
        var wasOnline = source.connectionState == .online
        // A value already on its way from a source that has since been left is dropped.
        watching = [
            Task { [weak self] in
                for await state in states where self?.source === source {
                    // Each return to the server may find it renamed.
                    if state == .online, !wasOnline { self?.readName(of: connection) }
                    wasOnline = state == .online
                }
            }
        ]
        source.refresh()
        readName(of: connection)
    }

    /// Asks the server for its name and keeps it; a failed read changes nothing.
    private func readName(of connection: MarfaConnection) {
        reading?.cancel()
        reading = Task { [weak self, describer] in
            // Leaving the copy cancels the read, so a late answer never names another server's library.
            guard let name = try? await describer(connection), !Task.isCancelled, let self else { return }
            self.instanceNames[connection.address.absoluteString] = name
            self.defaults.set(self.instanceNames, forKey: Self.namesKey)
        }
    }

    private func forgetName(of connection: MarfaConnection) {
        instanceNames.removeValue(forKey: connection.address.absoluteString)
        defaults.set(instanceNames, forKey: Self.namesKey)
    }

    private func detach() {
        for task in watching { task.cancel() }
        watching = []
        reading?.cancel()
        reading = nil
        library = nil
    }

    /// Removes the key, and the copy where it was discarded, once the copy is closed. A discarded copy is marked
    /// before anything is removed and unmarked only once it is gone, so neither a removal that fails nor a quit
    /// part way lets it be opened again as it was.
    private func finishLeaving(_ connection: MarfaConnection, discarding: Bool) async -> Problem? {
        if discarding { markDiscarded(connection, true) }
        var key: String?
        var copy: String?
        do {
            try await Self.offMain { [keys] in try keys.delete(for: connection) }
        } catch {
            key = Self.message(error)
        }
        if discarding {
            do {
                try await removeCopy(connection)
                markDiscarded(connection, false)
            } catch {
                copy = Self.message(error)
            }
        }
        return key == nil && copy == nil ? nil : .notRemoved(key: key, copy: copy)
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
            throw .notRemoved(key: nil, copy: Self.message(error))
        }
        markDiscarded(connection, false)
    }

    /// Removes the copy while holding its writer lock, so another copy of the app still writing it never has it
    /// taken away underneath. The package offers no removal of its own that does this.
    private func removeCopy(_ connection: MarfaConnection) async throws {
        let directory = location.directory(for: connection)
        let held = try await Self.holdWriterLock(of: location.store(for: connection))
        do {
            try await Self.offMain {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            }
        } catch {
            await held?.close()
            throw error
        }
        await held?.close()
    }

    /// Opens the store as its writer, or nil where there is no store to hold. A store another version of the app
    /// made is refused by `open`, which releases the lock as it does: with nothing unsent, the package replaces it
    /// with an empty one held as its writer, and refuses while another process writes it. One holding changes
    /// the server has not taken, which the person was shown and chose to discard, cannot be held, so it is removed
    /// without the lock, as is a store that cannot be opened at all. A store another process writes is refused.
    @concurrent private nonisolated static func holdWriterLock(of store: URL) async throws -> WorkingCopy? {
        guard FileManager.default.fileExists(atPath: store.path) else { return nil }
        let copy: WorkingCopy
        do {
            copy = try await WorkingCopy.open(store: store)
        } catch MarfaError.wrongSchema(_, _, 0?, _) {
            do {
                copy = try await WorkingCopy.replaceRefused(store: store)
            } catch MarfaError.readingHandle {
                throw SourceFailure(kind: .inUse, message: Words.inUse)
            }
        } catch MarfaError.wrongSchema {
            return nil
        } catch MarfaError.readingHandle {
            throw SourceFailure(kind: .inUse, message: Words.inUse)
        } catch {
            // No process can open it either, and the person chose to discard it, so keeping it would refuse its
            // address for good.
            return nil
        }
        guard copy.handle == .writer else {
            await copy.close()
            throw SourceFailure(kind: .inUse, message: Words.inUse)
        }
        return copy
    }

    private static func message(_ error: any Error) -> String {
        error.localizedDescription
    }

    static func state(_ state: MarfaConnectionState) -> State {
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
