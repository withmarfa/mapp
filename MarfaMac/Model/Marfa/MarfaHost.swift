import Foundation
import Marfa
import Observation
import Synchronization
import os

/// The Marfa library the app is connected to, from the address the person gives and the sign-in they make to it.
/// The address is kept in defaults, the sign-in by the package in the Keychain, and the copy in its own directory, so a launch
/// paints from the copy before asking the server anything. The words for each state are the app's.
/// Sign-in, switching, and disconnecting share one lifecycle so they can hand over writes before leaving a copy.
@Observable @MainActor final class MarfaHost {
    typealias Opener = @Sendable (MarfaConnection, any SignIns, MarfaStoreLocation) async throws -> any ItemSource
    /// Reads the name the server at an address gives itself. It sends no sign-in.
    typealias Describer = @Sendable (MarfaConnection) async throws -> String
    /// Removes the copy at a store, provided every change it holds that the server has not taken is one of the ids
    /// the person agreed to lose. Tests stand in for the package's answers that a real copy can't be made to give.
    typealias Remover = @Sendable (URL, Agreed) async throws -> Void
    /// Removes what the library fetched to this Mac besides its copy: the files it kept and its cached pictures.
    typealias Cleaner = @Sendable () async -> Void
    /// Makes the reader of item histories for a connection, or nil where there is no server to ask, as in the sample.
    typealias Historian = @Sendable (MarfaConnection, any SignIns) -> (any ItemHistorySource)?
    /// Makes the keeper of the owner's type icons for a connection, or nil where there is no server to ask, as in the
    /// sample.
    typealias IconKeeper = @Sendable (MarfaConnection, any SignIns) -> (any TypeIconSource)?
    /// Makes the keeper of changes to a type's fields for a connection, or nil where there is no server to ask.
    typealias SchemaKeeper = @Sendable (MarfaConnection, any SignIns) -> (any TypeSchemaSource)?
    typealias SourceNamer = @Sendable (MarfaConnection, any SignIns) -> (any SourceNameSource)?
    /// Makes the reader of items' `https` links for a connection, or nil where there is no server to ask.
    typealias LinkReader = @Sendable (MarfaConnection, any SignIns) -> (any ItemLinkSource)?
    /// Makes the reader and writer of the server's own settings for a connection, or nil where there is no server to
    /// ask, as in the sample.
    typealias Configurer = @Sendable (MarfaConnection, any SignIns) -> (any InstanceConfigSource)?

    /// What becomes of the copy, and every write still in it, when it is left.
    nonisolated enum DisconnectChoice: Hashable, Sendable {
        /// Left on disk, so connecting the same address again goes on from it and sends what waits.
        case keepCopy
        /// Removed with the writes the person was shown in `changesWaiting`, which they agreed to lose. A write
        /// not among them, such as a late save, keeps the copy and the person is asked again. Nil, where they
        /// were shown none, is refused.
        case discardCopy(UnsentChanges?)
    }

    nonisolated enum Problem: Error, Hashable, Sendable {
        case notAServer
        /// The address names a server and more: a path, a query or a fragment.
        case addressHasMore
        /// The app is not signed in to the address: it never was, or the sign-in ended.
        case notSignedIn
        /// Writes still wait in the copy being left, so the person chooses what becomes of them, and a choice
        /// to discard names these; asked again when others arrive after it. Nil where the copy could not be
        /// read and may hold some.
        case changesWaiting(UnsentChanges?)
        /// The copy could not be opened or read.
        case unavailable(message: String)
        /// The copy was made by a different version of the app; see `MarfaConnectionState.otherVersion`.
        case otherVersion(unsent: UInt64?)
        /// Another copy of the app holds the copy; see `MarfaConnectionState.inUse`.
        case inUse
        /// The sign-in did not finish; nothing was changed.
        case signIn(SignInOutcome)
        /// The connection was left, but its sign-in is still in the Keychain, or the copy the person discarded is
        /// still on disk, or both; each message says why. A discarded copy is never opened as it is:
        /// connecting its address again removes it first, or fails with this. `approvalAt` is the address of the
        /// server left where the sign-out also could not confirm it ended the approval.
        case notRemoved(signIn: String?, copy: String?, approvalAt: String? = nil)
        /// The connection to the server at `address` was left and the sign-in forgotten on this Mac, but the app could not
        /// confirm that the server ended the approval, which may stand there until the owner ends it.
        case notRevoked(address: String)
        /// The copy was not removed, and is no longer marked to go: the package would not remove it. `signIn` is why
        /// the sign-in is still in the Keychain, where it is. `approvalAt` is as for `notRemoved`.
        case copyKept(CopyKept, signIn: String?, approvalAt: String? = nil)
        /// The person chose to discard a copy whose changes were not counted for them, which the package never
        /// removes. Nothing was left; `folder` is where the copy is, for the person to remove.
        case cannotDiscard(folder: String)
        case notConnected
        /// Another connect, disconnect or sign-in is under way.
        case busy
    }

    /// Why the package left a copy the person chose to discard. The copy keeps every change in it.
    nonisolated enum CopyKept: Hashable, Sendable {
        /// It holds `now` changes the server has not taken, not only the ones the person was shown and agreed to
        /// lose. Connecting to the address again opens it and sends them.
        case changed(now: UInt64)
        /// Its changes can't be read, and the package never removes a copy whose changes it can't read. `folder` is
        /// where it is, for the person to remove.
        case unreadable(folder: String)
        /// It is a folder's store, which is not the app's to remove.
        case notMadeByApp(folder: String)
    }

    /// What the person agreed to lose with a copy they discard: the writes they were shown, by queue id. A count
    /// confirms nothing, since another write can take the place of one that was sent.
    nonisolated struct Agreed: Hashable, Sendable {
        var ids: Set<String>

        init(ids: Set<String>) {
            self.ids = ids
        }

        /// A mark that is not a list of ids agrees to lose nothing, so a copy holding any change is kept.
        init(stored: Any) {
            ids = Set(stored as? [String] ?? [])
        }

        /// Whether a copy holding `held` loses nothing beyond what was agreed: a write sent meanwhile is no loss.
        func covers(_ held: [String]) -> Bool {
            Set(held).isSubset(of: ids)
        }

        /// As it is kept in the defaults, so a removal that stops part way is finished at the next launch.
        var stored: [String] { ids.sorted() }
    }

    static let addressKey = "MarfaAddress"
    /// The address of the sign-in kept for a question, so a launch ends one the app quit with.
    private static let pendingSignInKey = "MarfaPendingSignIn"
    /// The address of each copy the person discarded but which could not be removed, with the ids of the changes
    /// they agreed to lose with it.
    static let discardedKey = "MarfaDiscardedCopies"
    /// The last name each server gave itself, by address, so a launch and an offline window show it.
    private static let namesKey = "MarfaInstanceNames"

    let defaults: UserDefaults
    let signIns: any SignIns
    let location: MarfaStoreLocation
    private let opener: Opener
    private let describer: Describer
    let remover: Remover
    private let cleaner: Cleaner
    /// Removes what a library kept outside its copy: the files it fetched and the pictures it cached.
    static let standardCleaner: Cleaner = { await MarfaSource.removeKeptCopies(); await PictureCache.removeAll() }
    private let historian: Historian
    private let configurer: Configurer
    private let iconKeeper: IconKeeper
    private let schemaKeeper: SchemaKeeper
    private let sourceNamer: SourceNamer
    private let linkReader: LinkReader

    /// The address connected to, kept while its copy cannot be opened, so Settings can offer a sign-in for it.
    private(set) var connection: MarfaConnection? {
        didSet { if connection != nil { unusableAddress = nil } }
    }
    /// The saved address that no longer names a server the app accepts (it has a path), told until a connection is made.
    /// Its copy stays on disk, untouched, and a new address starts a new copy.
    private(set) var unusableAddress: String?
    /// The library to show, once its copy is open. It holds how its server stands and what its copy last
    /// reported, so the host keeps neither while a copy is open.
    private(set) var library: MarfaLibrary?
    /// How the server stands while no copy is open: connecting to it, or why its copy could not be opened.
    private var standing = MarfaConnectionState.disconnected
    /// What the person is told, from this host and from every library it opens.
    let notices = Notices()
    private(set) var isBusy = false
    /// Whether a sign-in waits on the person (the browser's page, or a code to approve elsewhere). Stopping the step
    /// then changes nothing; once it is false the sign-in is being used, and stopping would end it.
    private(set) var isSigningIn = false
    /// The server a switch signed in to whose approval is kept while the person answers the question about changes that
    /// arrived during the sign-in. The answer uses it, and dropping the question ends it. Its address is also kept in
    /// the defaults, since quitting with the question open drops it without a step to end it: the next launch does.
    private var pendingSignIn: MarfaConnection? {
        didSet {
            if let pendingSignIn {
                defaults.set(pendingSignIn.address.absoluteString, forKey: Self.pendingSignInKey)
            } else {
                defaults.removeObject(forKey: Self.pendingSignInKey)
            }
        }
    }
    private var reading: Task<Void, Never>?
    private var instanceNames: [String: String]
    /// Hands every open page's last edit to the library it came from. The host runs it before the windows change
    /// library and again right before it reads or closes a copy, so text typed while a step waited on the network
    /// is in the copy when it closes. Set by the app; tests may set none.
    @ObservationIgnored var handOverEdits: () async -> Bool = { true }
    /// Told each time the library shown changes, and with nil when none is, after the host holds it.
    @ObservationIgnored var libraryChanged: (MarfaLibrary?) -> Void = { _ in }

    var source: (any ItemSource)? { library?.source }
    var state: MarfaConnectionState { library?.connection ?? standing }
    var report: SyncReport { library?.syncReport ?? SyncReport() }

    init(
        defaults: UserDefaults, signIns: any SignIns, location: MarfaStoreLocation,
        opener: @escaping Opener = { try await MarfaSource.open($0, signIns: $1, location: $2) },
        describer: @escaping Describer = { try await $0.server(key: "").instanceDescription().name },
        remover: @escaping Remover = { try await MarfaHost.removeStore($0, agreedToLose: $1) },
        cleaner: @escaping Cleaner = MarfaHost.standardCleaner,
        historian: @escaping Historian = { MarfaServerCalls(connection: $0, signIns: $1) },
        configurer: @escaping Configurer = { MarfaServerCalls(connection: $0, signIns: $1) },
        iconKeeper: @escaping IconKeeper = { MarfaServerCalls(connection: $0, signIns: $1) },
        schemaKeeper: @escaping SchemaKeeper = { MarfaServerCalls(connection: $0, signIns: $1) },
        sourceNamer: @escaping SourceNamer = { MarfaServerCalls(connection: $0, signIns: $1) },
        linkReader: @escaping LinkReader = { MarfaServerCalls(connection: $0, signIns: $1) }
    ) {
        self.defaults = defaults
        self.signIns = signIns
        self.location = location
        self.opener = opener
        self.describer = describer
        self.remover = remover
        self.cleaner = cleaner
        self.historian = historian
        self.configurer = configurer
        self.iconKeeper = iconKeeper
        self.schemaKeeper = schemaKeeper
        self.sourceNamer = sourceNamer
        self.linkReader = linkReader
        instanceNames = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    /// The name the server at `connection` last gave itself, nil until one has been read.
    func instanceName(for connection: MarfaConnection) -> String? {
        instanceNames[connection.address.absoluteString]
    }

    /// The last time the copy of the server connected to finished a pull from it without an error, which is more
    /// than hearing from it: the copy was brought up to date, or a change the server made reached it. The copy keeps
    /// it, so a launch reports the one from the launch before until a pull finishes.
    var lastSynced: Date? { report.lastSynced }

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

    /// Whether Refresh has anything to do: an open copy of a server's library, not already syncing or hydrating, and
    /// a sign-in the server has not refused. A server that cannot be reached, and a library the package reports stopped
    /// or needing a hydration it is not running, still count, so the person can try again at once rather than wait
    /// for the copy's next try.
    var canRefresh: Bool {
        guard hasServer, source != nil, report.phase == .current else { return false }
        switch state {
        case .online, .connecting, .offline, .unavailable: return true
        case .disconnected, .keyRefused, .otherVersion, .inUse: return false
        }
    }

    /// Pulls what the server has changed since the copy last looked, then sends the changes waiting in the copy: the
    /// sync a launch and a return of the server run.
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

    /// Opens the saved library's copy and paints from it, then asks the server.
    func launch() async {
        // The question that held it is gone with the last run. It is never the address this run connects to: an
        // answer takes the record out before it is used, so a record names a server no step went on to open.
        if let recorded = defaults.string(forKey: Self.pendingSignInKey) {
            defaults.removeObject(forKey: Self.pendingSignInKey)
            if recorded != defaults.string(forKey: Self.addressKey), let stale = try? MarfaConnection(address: recorded) {
                await endSignIn(of: stale)
            }
        }
        guard !isBusy, source == nil, let saved = defaults.string(forKey: Self.addressKey) else { return }
        let connection: MarfaConnection
        do {
            connection = try MarfaConnection(address: saved)
        } catch {
            // Only an address with more after the server's is told: the app saves no other address that fails.
            if error == .hasMore { unusableAddress = saved }
            return
        }
        isBusy = true
        defer { isBusy = false }
        self.connection = connection
        _ = try? await open(connection)
    }

    /// How a person signs in: through the browser, or with a code typed on another device.
    enum SignInMethod: Sendable {
        case browser
        /// `shown` is called with the code once the server has given it, for the window to show while the person
        /// approves it elsewhere.
        case code(shown: @MainActor @Sendable (CodeSignIn) -> Void)
    }

    /// Signs in to the server at `address`, keeping the sign-in once the copy opens. Connecting while connected
    /// changes the address, or only signs in again where the address is the same.
    func connect(address: String, via method: SignInMethod) async throws(Problem) {
        let connection = try typed(address)
        if let current = self.connection {
            if current.sameServer(as: connection) { return try await signInAgain(via: method) }
            return try await changeAddress(to: address, via: method)
        }
        try begin()
        defer { isBusy = false }
        await dropPendingSignIn()
        guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current item before changing libraries.")) }
        try await signIn(to: connection, via: method)
        do {
            try await open(connection)
        } catch {
            await endSignIn(of: connection)
            standing = .disconnected
            throw error
        }
        remember(connection)
    }

    /// Closes the copy and forgets the address and sign-in. `choice` is needed while writes wait in the copy, and is
    /// asked for again when more arrive after it; with nothing waiting and no choice the copy is removed, since a
    /// later connection pulls it again. The address is forgotten and the discard marked before anything is waited
    /// on that the copy's closing does not decide, so a quit at any point never opens the copy or sends what the
    /// person discarded.
    func disconnect(_ choice: DisconnectChoice? = nil) async throws(Problem) {
        guard let connection else { return }
        try begin()
        defer { isBusy = false }
        await dropPendingSignIn()
        let agreed = try agreedLoss(choice, of: connection)
        let marked = markBeforeLeaving(connection, agreed: agreed, choice: choice)
        do throws(Problem) {
            if let source {
                try await close(source, for: choice)
            } else if choice == nil, hasCopy(connection) {
                let unsent = await Self.unsentChanges(in: location.store(for: connection))
                if unsent?.ids.isEmpty != true { throw .changesWaiting(unsent) }
            }
        } catch {
            if let marked { restoreAfterRefusal(connection, marked) }
            throw error
        }
        // Decided: from here to the end of this block nothing waits, so no quit comes between the steps.
        defaults.removeObject(forKey: Self.addressKey)
        if let agreed { markDiscarded(connection, agreed: agreed) }
        detach()
        forgetName(of: connection)
        self.connection = nil
        standing = .disconnected
        await cleaner()
        if let problem = await finishLeaving(connection, agreed: agreed) { throw problem }
    }

    /// Signs in again to the address connected to, for a sign-in the server ended or one the person wants to
    /// replace. The sign-in replaces the kept one only once the server has given a new one, so a sign-in the person
    /// cancels changes nothing. An open copy is given the new sign-in where it is (`ItemSource.use(_:)`): it is never
    /// closed or replaced, the writes in it wait there, and the package sends them with the next drain. Called after
    /// the sign-in ended, it brings the copy back even though the credential kept is the one it had.
    func signInAgain(via method: SignInMethod) async throws(Problem) {
        guard let connection else { throw .notConnected }
        try begin()
        defer { isBusy = false }
        await dropPendingSignIn()
        // Nothing the sign-in or the copy's change can do may close the library over edits still being typed.
        if source != nil { try await handOver() }
        await refreshGrants()
        let held = grantsRead ? grants : nil
        try await signIn(to: connection, via: method)
        await refreshGrants()
        // The owner may approve fewer than the app held, and that stands, but never silently.
        if let held, grantsRead {
            let lost = held.subtracting(grants)
            if !lost.isEmpty { notices.tell(Words.permissionsLostTitle, Words.permissionsLost(lost)) }
        }
        guard let source else { return try await open(connection) }
        let server: Server?
        do {
            server = try await Self.offMain { [signIns] in try signIns.server(for: connection) }
        } catch {
            throw .unavailable(message: Words.signInUnreadable)
        }
        guard let server else { throw .notSignedIn }
        // The sign-in can take minutes, and writes may have been made meanwhile.
        try await handOver()
        let role: SourceRole
        do {
            role = try await source.use(server)
        } catch let failure as SourceUseFailure {
            if failure.closed {
                // The package closed the copy where its store could not be opened again, so the library is closed
                // with it and the person is told. Its queue stays in the store.
                detach()
                standing = .unavailable(message: Self.message(failure.cause))
                await source.close()
                throw .unavailable(message: Self.message(failure.cause))
            }
            if let error = failure.cause as? MarfaError, case .noServer = error { return }
            if let error = failure.cause as? SignInError, case .notSignedIn = error { throw .notSignedIn }
            // Every other refusal changed nothing: the library stays as it was.
            throw .unavailable(message: Self.message(failure.cause))
        } catch {
            throw .unavailable(message: Self.message(error))
        }
        if role == .reader {
            // Another opener took the writer role while the store opened again; a reader's writes would all be
            // refused. As opening one is told: the copy and its queue stay in the store, read in the step that closes
            // it and agreed to whole, so nothing in it is discarded.
            detach()
            standing = .inUse
            _ = await source.close(agreeing: nil)
            throw .inUse
        }
    }

    private func handOver() async throws(Problem) {
        guard await handOverEdits() else {
            throw .unavailable(message: String(localized: "Finish editing the current item before changing libraries."))
        }
    }

    /// Moves to another server's library. Another address is another copy, so writes waiting in this one need
    /// the person's `choice`, asked for again when more arrive while the new copy opens. The new copy is opened
    /// before this one is left, so a failure leaves things as they were.
    func changeAddress(to address: String, via method: SignInMethod, choice: DisconnectChoice? = nil) async throws(Problem) {
        let connection = try typed(address)
        guard let old = self.connection else { return try await connect(address: address, via: method) }
        if connection.sameServer(as: old) { return try await signInAgain(via: method) }
        try begin()
        defer { isBusy = false }
        // Taken at once, so a step that stops before the approval is used or dropped does not leave it live.
        let kept = pendingSignIn
        pendingSignIn = nil
        let agreed: Agreed?
        let current = source
        let fresh: Bool
        do throws(Problem) {
            agreed = try agreedLoss(choice, of: old)
            if current != nil { guard await handOverEdits() else { throw Problem.unavailable(message: String(localized: "Finish editing the current item before changing libraries.")) } }
            if let current, choice == nil {
                let unsent = await current.unsentWrites()
                if unsent?.ids.isEmpty != true { throw Problem.changesWaiting(unsent) }
            } else if current == nil, choice == nil, hasCopy(old) {
                let unsent = await Self.unsentChanges(in: location.store(for: old))
                if unsent?.ids.isEmpty != true { throw Problem.changesWaiting(unsent) }
            }
            fresh = !hasCopy(connection)
        } catch {
            if let kept { await endSignIn(of: kept) }
            throw error
        }
        if let kept, kept.sameServer(as: connection), await holdsSignIn(for: connection) {
            // The person has answered the question put after this sign-in, so it is used and not made again.
        } else {
            if let kept { await endSignIn(of: kept) }
            try await signIn(to: connection, via: method)
        }
        // The sign-in can take minutes, and so can the question after it. Writes made meanwhile are asked about,
        // with the approval kept for the answer, rather than refused when the copy closes and the approval revoked.
        if let current, choice != .keepCopy {
            guard await handOverEdits() else {
                await endSignIn(of: connection)
                throw .unavailable(message: String(localized: "Finish editing the current item before changing libraries."))
            }
            let unsent = await current.unsentWrites()
            if !Self.covers(choice, unsent) {
                pendingSignIn = connection
                throw .changesWaiting(unsent)
            }
        }
        let opened: any ItemSource
        do {
            try await clearDiscarded(connection)
            opened = try await Self.open(connection, signIns: signIns, location: location, with: opener)
        } catch {
            await endSignIn(of: connection)
            throw error
        }
        if let current {
            // Marked before the copy closes, so a quit while it closes never sends what the person discarded.
            let marked = markBeforeLeaving(old, agreed: agreed, choice: choice, forgettingAddress: false)
            do {
                try await close(current, for: choice)
            } catch {
                if let marked { restoreAfterRefusal(old, marked, rememberingAddress: false) }
                // The move is abandoned, so the copy and the sign-in made for it go too.
                await opened.close()
                await endSignIn(of: connection)
                if fresh { _ = await removeCopy(connection, agreed: Agreed(ids: [])) }
                throw error
            }
        }
        // The new copy is shown before the old one's sign-in and copy are removed, so the windows go from one library
        // to the other and never show the connect page between them.
        remember(connection)
        attach(opened, for: connection)
        forgetName(of: old)
        // The old sign-in is ended only here: a same-origin address returned above as Sign In Again, so the package's
        // origin-keyed sign-in is never one the new connection shares.
        if let problem = await finishLeaving(old, agreed: agreed) { throw problem }
    }

    /// Whether what the person agreed to lose takes in every write the copy holds: nothing, without a choice.
    private static func covers(_ choice: DisconnectChoice?, _ unsent: UnsentChanges?) -> Bool {
        switch (choice, unsent) {
        case (nil, let unsent?): unsent.ids.isEmpty
        case (nil, nil): false
        case (.discardCopy(let agreed?), let unsent?): unsent.ids.isSubset(of: agreed.ids)
        case (.discardCopy, _): false
        case (.keepCopy, _): true
        }
    }

    /// Ends the sign-in kept for a question the person dropped. Does nothing while a step is under way, which
    /// ends or uses it itself.
    func abandonPendingSignIn() async {
        guard !isBusy else { return }
        await dropPendingSignIn()
    }

    private func dropPendingSignIn() async {
        guard let pending = pendingSignIn else { return }
        pendingSignIn = nil
        await endSignIn(of: pending)
    }

    // MARK: Lifecycle

    private func begin() throws(Problem) {
        guard !isBusy else { throw .busy }
        isBusy = true
    }

    /// The address the person typed, as entered: each spelling of an address is its own copy.
    private func typed(_ address: String) throws(Problem) -> MarfaConnection {
        do {
            return try MarfaConnection(address: address)
        } catch {
            throw error == .hasMore ? .addressHasMore : .notAServer
        }
    }

    /// Signs in as the person chose. Nothing is kept unless it finishes.
    private func signIn(to connection: MarfaConnection, via method: SignInMethod) async throws(Problem) {
        isSigningIn = true
        defer { isSigningIn = false }
        let signedIn: SignedIn
        do {
            switch method {
            case .browser:
                signedIn = try await signIns.signInWithBrowser(to: connection)
            case .code(let shown):
                let code = try await signIns.startCodeSignIn(to: connection)
                shown(code)
                signedIn = try await code.finish()
            }
        } catch {
            throw .signIn(SignInOutcome(error))
        }
        if signedIn.replacedApprovalStands {
            notices.tell(Words.replacedApprovalTitle, Words.replacedApproval(address: connection.address.absoluteString))
        }
    }

    /// Whether the Keychain holds a sign-in for `connection` that can be used, read where the main actor never waits.
    private func holdsSignIn(for connection: MarfaConnection) async -> Bool {
        let held = try? await Self.offMain { [signIns] in try signIns.server(for: connection) }
        return held != nil
    }

    /// Ends a sign-in made for a step that was abandoned. The server is told where it can be; where it could not
    /// confirm the approval ended, or the sign-out did not run, the person is told how to end it.
    func endSignIn(of connection: MarfaConnection) async {
        let address = connection.address.absoluteString
        do {
            if try await signIns.signOut(of: connection) == .notConfirmed {
                notices.tell(Words.approvalMayStandTitle(.abandoned), Words.approvalMayStand(.abandoned, address: address))
            }
        } catch {
            // A string logged without a privacy level is private.
            Telemetry.logger(.library).error("A clean-up sign-out did not run: \(String(describing: error))")
            notices.tell(Words.signOutFailedTitle, Words.signOutFailed(address: address))
        }
    }

    #if DEBUG
    /// Sets the server a launch opens, for a debug build run against a test server. The sign-in is the one kept for the address.
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

    /// Closes `source` as `choice` allows. A kept copy loses nothing, so it closes whatever waits. Otherwise the
    /// copy reads its own queue, once the writes submitted before now are in it, and closes in the same step
    /// only if every write not sent is one the person agreed to lose: none, without a choice.
    private func close(_ source: any ItemSource, for choice: DisconnectChoice?) async throws(Problem) {
        guard await handOverEdits() else { throw .unavailable(message: String(localized: "Finish editing the current item before changing libraries.")) }
        let agreed: UnsentChanges
        switch choice {
        case .keepCopy:
            await source.close()
            return
        case .discardCopy(let shown): agreed = shown ?? UnsentChanges(ids: [])
        case nil: agreed = UnsentChanges(ids: [])
        }
        if case .waiting(let unsent) = await source.close(agreeing: agreed) { throw .changesWaiting(unsent) }
    }

    /// Opens the copy and paints from it; the server is asked only after.
    private func open(_ connection: MarfaConnection) async throws(Problem) {
        standing = .connecting
        do {
            try await clearDiscarded(connection)
            attach(try await Self.open(connection, signIns: signIns, location: location, with: opener), for: connection)
        } catch {
            switch error {
            case .notSignedIn: standing = .keyRefused
            case .unavailable(let message): standing = .unavailable(message: message)
            case .otherVersion(let unsent): standing = .otherVersion(unsent: unsent)
            case .inUse: standing = .inUse
            default: standing = .disconnected
            }
            throw error
        }
    }

    private static func open(
        _ connection: MarfaConnection, signIns: any SignIns, location: MarfaStoreLocation, with opener: Opener
    ) async throws(Problem) -> any ItemSource {
        do {
            return try await opener(connection, signIns, location)
        } catch let failure as SourceFailure {
            // A source refuses to open only for want of a sign-in.
            switch failure.kind {
            case .denied: throw .notSignedIn
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

    /// The permissions the kept sign-in holds, once `grantsRead`: after a copy opens and after each sign-in.
    private(set) var grants: Set<InstancePermission> = []
    /// Whether `grants` has been read for the copy shown: a sign-in the Keychain cannot give reads as holding none.
    private(set) var grantsRead = false
    /// Whether the kept sign-in may read the owner's name, once `grantsRead`: a sign-in made before the app asked for it
    /// cannot, and Allow More… or signing in again gives it.
    private(set) var readsProfile = false
    /// Whether the kept sign-in lacks something the app asks for at sign-in (`SystemSignIns.lacksAsked`), once `grantsRead`:
    /// an owner permission the owner left out, or a scope added since the sign-in was made. Allow More… then has something
    /// to ask for.
    private(set) var lacksAsked = false

    /// Reads what the kept sign-in holds, where the main actor never waits on the Keychain. A sign-in the Keychain
    /// cannot give is not read: the grants last read stand and `grantsRead` is false, so nothing reads as holding none.
    func refreshGrants() async {
        guard let connection = configuredConnection else {
            grants = []
            grantsRead = false
            readsProfile = false
            lacksAsked = false
            return
        }
        let held: Set<InstancePermission>?
        let profile: Bool?
        let scopes: [String]?
        do {
            let read = try await Self.offMain { [signIns] in
                (try signIns.grants(for: connection), try signIns.readsProfile(for: connection), try signIns.scopes(for: connection))
            }
            held = read.0
            profile = read.1
            scopes = read.2
        } catch {
            guard configuredConnection == connection else { return }
            grantsRead = false
            return
        }
        guard configuredConnection == connection else { return }
        grants = held ?? []
        readsProfile = profile ?? false
        lacksAsked = SystemSignIns.lacksAsked(scopes ?? [])
        grantsRead = true
    }

    private func attach(_ source: any ItemSource, for connection: MarfaConnection) {
        detach()
        Task { await refreshGrants() }
        let library = MarfaLibrary(
            source: source, notices: notices, history: historian(connection, signIns), typeIcons: iconKeeper(connection, signIns),
            typeSchemas: schemaKeeper(connection, signIns),
            config: configurer(connection, signIns), sourceNames: sourceNamer(connection, signIns),
            links: linkReader(connection, signIns),
            // Each return to the server may find it renamed. A library the host has left may still be told once more.
            cameOnline: { [weak self] in
                guard let self, self.connection == connection else { return }
                readName(of: connection)
            })
        self.library = library
        libraryChanged(library)
        if let origin = (try? connection.server(key: ""))?.plainHTTPOrigin, Self.toldPlainHTTP.withLock({ $0.insert(origin).inserted }) {
            notices.tell(Words.plainHTTPTitle, Words.plainHTTP(origin: origin))
        }
        readName(of: connection)
    }

    /// The server's own settings to ask about, for the server the app is set to, with a name for it. Nil where none is set.
    func instanceConfigTarget() -> InstanceSettingsModel.Target? {
        guard let connection = configuredConnection, let source = configurer(connection, signIns) else { return nil }
        return InstanceSettingsModel.Target(id: connection.address.absoluteString, source: source)
    }

    /// Takes a save made in This Marfa: reads the server's name again where it changed, and gives the open library
    /// the server's answer, for the server the windows show. A save sent to `address` that
    /// answers after the app has moved to another server is dropped.
    func instanceSaved(_ answer: InstanceConfig, changing settings: Set<InstanceSetting>, of address: String) {
        guard let connection, connection.address.absoluteString == address else { return }
        if settings.contains(.name) { readName(of: connection) }
        library?.take(answer)
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
        reading?.cancel()
        reading = nil
        if library != nil {
            library = nil
            libraryChanged(nil)
        }
        grants = []
        grantsRead = false
        readsProfile = false
        lacksAsked = false
    }

    /// What to tell of an error a step met. What a package error or the system said is never shown: the detail goes
    /// to the log, and the person is told what the app could not do.
    static func message(_ error: any Error) -> String {
        if let error = error as? MarfaError { return Words.message(for: error) }
        // A string logged without a privacy level is private.
        Telemetry.logger(.library).error("A library step failed: \(String(describing: error))")
        if error is SignInError || error is any KeychainRefusal { return Words.signInUnreadable }
        return Words.copyCouldNotBeOpened
    }

    /// The plain http origins the person has been told of in this run, since the package keeps no state.
    private nonisolated static let toldPlainHTTP = Mutex(Set<String>())

    /// The keychain and the disk can each take a while, which the main actor never waits on.
    @concurrent nonisolated static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
