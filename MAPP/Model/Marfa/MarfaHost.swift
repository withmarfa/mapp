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
    /// Removes the copy at a store, agreed to hold this many unsent changes. Tests stand in for the package's
    /// answers that a real copy can't be made to give.
    typealias Remover = @Sendable (URL, UInt64) async throws -> Void
    /// Makes the reader of item histories for a connection, or nil where there is no server to ask, as in the sample.
    typealias Historian = @Sendable (MarfaConnection, any KeyStore) -> (any ItemHistorySource)?
    /// Makes the keeper of the owner's type icons for a connection, or nil where there is no server to ask, as in the
    /// sample.
    typealias IconKeeper = @Sendable (MarfaConnection, any KeyStore) -> (any TypeIconSource)?
    /// Makes the reader and writer of the server's own settings for a connection, or nil where there is no server to
    /// ask, as in the sample.
    typealias Configurer = @Sendable (MarfaConnection, any KeyStore) -> (any InstanceConfigSource)?

    /// What becomes of the copy, and every write still in it, when it is left.
    nonisolated enum DisconnectChoice: Hashable, Sendable {
        /// Left on disk, so connecting the same address again goes on from it and sends what waits.
        case keepCopy
        /// Removed with the writes the person was shown in `changesWaiting`, which they agreed to lose. A write
        /// not among them, such as a late save, keeps the copy and the person is asked again. Nil is only for a
        /// copy another version made, and agrees to the count it reported; with none, the choice is refused.
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
        /// The copy was made by a different version of the app; see `MarfaConnectionState.otherVersion`.
        case otherVersion(unsent: UInt64?)
        /// Another copy of the app holds the copy; see `MarfaConnectionState.inUse`.
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
        /// The copy was not removed, and is no longer marked to go: the package would not remove it. `key` is why
        /// the key is still in the key store, where it is.
        case copyKept(CopyKept, key: String?)
        /// The person chose to discard a copy whose changes were not counted for them, which the package never
        /// removes. Nothing was left; `folder` is where the copy is, for the person to remove.
        case cannotDiscard(folder: String)
        case notConnected
        /// Another connect, disconnect or change of key is under way.
        case busy
    }

    /// Why the package left a copy the person chose to discard. The copy keeps every change in it.
    nonisolated enum CopyKept: Hashable, Sendable {
        /// It holds `now` changes the server has not taken, not the number the person was shown and agreed to
        /// lose. Connecting to the address again opens it and sends them.
        case changed(now: UInt64)
        /// Its changes can't be counted, and the package never removes a copy it can't count. `folder` is where it
        /// is, for the person to remove.
        case unreadable(folder: String)
        /// It is a folder's store, which is not MAPP's to remove.
        case notMapps(folder: String)
    }

    private static let addressKey = "MarfaAddress"
    /// The address of each copy the person discarded but which could not be removed, with the number of changes
    /// they agreed to lose with it.
    static let discardedKey = "MarfaDiscardedCopies"
    /// The last name each server gave itself, by address, so a launch and an offline window show it.
    private static let namesKey = "MarfaInstanceNames"
    /// When each server's copy last finished a sync without an error, by address, so a launch says how old what it
    /// paints is before the server has been asked.
    private static let syncedKey = "MarfaLastSynced"

    let defaults: UserDefaults
    let keys: any KeyStore
    let location: MarfaStoreLocation
    private let opener: Opener
    private let describer: Describer
    let remover: Remover
    private let historian: Historian
    private let configurer: Configurer
    private let iconKeeper: IconKeeper

    /// The address connected to, kept while its copy cannot be opened, so Settings can offer a key for it.
    private(set) var connection: MarfaConnection?
    /// The library to show, once its copy is open. It holds how its server stands and what its copy last
    /// reported, and tells the host when the server comes back, so the host keeps neither and follows neither
    /// while a copy is open.
    private(set) var library: MarfaLibrary?
    /// How the server stands while no copy is open: connecting to it, or why its copy could not be opened.
    private var standing = MarfaConnectionState.disconnected
    /// What the person is told, from this host and from every library it opens.
    let notices = Notices()
    private(set) var isBusy = false
    private var reading: Task<Void, Never>?
    private var instanceNames: [String: String]
    private var syncedDates: [String: Date]
    /// Hands every open page's last edit to the library it came from. The host runs it before the windows change
    /// library and again right before it reads or closes a copy, so text typed while a step waited on the network
    /// is in the copy when it closes. Set by the app; tests may set none.
    @ObservationIgnored var handOverEdits: () async -> Bool = { true }

    var source: (any ItemSource)? { library?.source }
    var state: MarfaConnectionState { library?.connection ?? standing }
    var report: SyncReport { library?.syncReport ?? SyncReport() }

    init(
        defaults: UserDefaults, keys: any KeyStore, location: MarfaStoreLocation,
        opener: @escaping Opener = { try await MarfaSource.open($0, keys: $1, location: $2) },
        describer: @escaping Describer = { try await $0.server(key: "").instanceDescription().name },
        remover: @escaping Remover = { try await WorkingCopy.remove(store: $0, unsent: $1) },
        historian: @escaping Historian = { MarfaServerVersions(connection: $0, keys: $1) },
        configurer: @escaping Configurer = { MarfaServerConfig(connection: $0, keys: $1) },
        iconKeeper: @escaping IconKeeper = { MarfaServerTypeIcons(connection: $0, keys: $1) }
    ) {
        self.defaults = defaults
        self.keys = keys
        self.location = location
        self.opener = opener
        self.describer = describer
        self.remover = remover
        self.historian = historian
        self.configurer = configurer
        self.iconKeeper = iconKeeper
        instanceNames = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        syncedDates = defaults.dictionary(forKey: Self.syncedKey) as? [String: Date] ?? [:]
    }

    /// The name the server at `connection` last gave itself, nil until one has been read.
    func instanceName(for connection: MarfaConnection) -> String? {
        instanceNames[connection.address.absoluteString]
    }

    /// The last time the copy of the server connected to finished a sync with it without an error, which is more than
    /// hearing from it: the copy was brought up to date, or a change the server made reached it. This launch's is
    /// the copy's own report; until a sync finishes, the one kept by the launch before, for that address.
    var lastSynced: Date? {
        report.lastSynced ?? connection.flatMap { syncedDates[$0.address.absoluteString] }
    }

    /// Whether the connection is to a server, as against the sample library, which has none to sync with. Only a
    /// debug build holds the sample, so a release build's connection is always a server.
    var hasServer: Bool {
        guard let connection else { return false }
        #if DEBUG
        return connection != SampleLibrary.connection
        #else
        return true
        #endif
    }

    /// Whether Refresh has anything to do: an open copy of a server's library, not already syncing, and a key the
    /// server has not refused. A server that cannot be reached still counts, so the person can try again at once
    /// rather than wait for the copy's next try.
    var canRefresh: Bool {
        guard hasServer, source != nil, report.phase == .current else { return false }
        switch state {
        case .online, .connecting, .offline: return true
        case .disconnected, .keyRefused, .unavailable, .otherVersion, .inUse: return false
        }
    }

    /// Pulls what the server has changed since the copy last looked, then sends the changes waiting in the copy and
    /// reads the bin again: the sync a launch and a return of the server run.
    func refresh() {
        guard canRefresh else { return }
        source?.refresh()
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
        let agreed = try agreedLoss(choice, of: connection)
        if let source {
            try await close(source, for: choice)
        } else if choice == nil, hasCopy(connection) {
            throw .changesWaiting(nil)
        }
        detach()
        forgetName(of: connection)
        forgetSync(of: connection)
        await MarfaSource.removeKeptCopies()
        await PictureCache.removeAll()
        // The address goes first, so a quit while the key and the copy are removed never opens this server again
        // at the next launch, with a key already gone.
        defaults.removeObject(forKey: Self.addressKey)
        self.connection = nil
        standing = .disconnected
        if let problem = await finishLeaving(connection, agreed: agreed) { throw problem }
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
        let agreed = try agreedLoss(choice, of: old)
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
                if fresh { _ = await removeCopy(connection, agreed: 0) }
                throw error
            }
        }
        // The new copy is shown before the old one's key and copy are removed, so the windows go from one library
        // to the other and never show the connect page between them.
        remember(connection)
        attach(opened, for: connection)
        forgetName(of: old)
        forgetSync(of: old)
        if let problem = await finishLeaving(old, agreed: agreed) { throw problem }
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
            case .missing, .failed:
                Telemetry.libraryNotOpened(nil)
                throw .unavailable(message: failure.message)
            }
        } catch {
            // An open given up because the person moved on, as when switching servers quickly, is no fault.
            if !(error is CancellationError) { Telemetry.libraryNotOpened(error as? MarfaError) }
            throw .unavailable(message: Self.message(error))
        }
    }

    private func attach(_ source: any ItemSource, for connection: MarfaConnection) {
        detach()
        let library = MarfaLibrary(
            source: source, notices: notices, history: historian(connection, keys), typeIcons: iconKeeper(connection, keys),
            didSync: { [weak self] date in self?.recordSync(date, for: connection) },
            // Each return to the server may find it renamed. A library the host has left may still be told once more.
            cameOnline: { [weak self] in
                guard let self, self.connection == connection else { return }
                readName(of: connection)
            })
        self.library = library
        if let notice = connection.server(key: "").takePlainHTTPNotice() {
            notices.tell(Words.plainHTTPTitle, Words.plainHTTP(origin: notice.origin))
        }
        source.refresh()
        readName(of: connection)
    }

    /// The server's own settings to ask about, for the server the app is set to, with a name for it. Nil where none is set.
    func instanceConfigTarget() -> InstanceSettingsModel.Target? {
        guard let connection = configuredConnection, let source = configurer(connection, keys) else { return nil }
        return InstanceSettingsModel.Target(id: connection.address.absoluteString, source: source)
    }

    /// Reads the server's name again, as after the person renamed it in This Marfa.
    func refreshName() {
        guard let connection else { return }
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

    private func recordSync(_ date: Date, for connection: MarfaConnection) {
        // A library that has been left may still be told once more.
        guard self.connection == connection else { return }
        syncedDates[connection.address.absoluteString] = date
        defaults.set(syncedDates, forKey: Self.syncedKey)
    }

    private func forgetSync(of connection: MarfaConnection) {
        guard syncedDates.removeValue(forKey: connection.address.absoluteString) != nil else { return }
        defaults.set(syncedDates, forKey: Self.syncedKey)
    }

    private func forgetName(of connection: MarfaConnection) {
        instanceNames.removeValue(forKey: connection.address.absoluteString)
        defaults.set(instanceNames, forKey: Self.namesKey)
    }

    private func detach() {
        reading?.cancel()
        reading = nil
        library = nil
    }

    static func message(_ error: any Error) -> String {
        error.localizedDescription
    }

    /// The keychain and the disk can each take a while, which the main actor never waits on.
    @concurrent nonisolated static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
