import Foundation
import Marfa
import os

/// What the copy tells (`WorkingCopy.updates()`), shown on the hub and handed to the engine one update at a time,
/// and the calls the app makes itself: hydrating a copy that needs it, draining after a write, reading the bin and
/// fetching kept files. The package keeps the copy following its server, catches it up, and tries again after a
/// failure and after a drain left writes undelivered; none of that is done here. Attachment downloads run
/// separately so they cannot hold up a drain or flush.
actor MarfaSync {
    /// One slice of both tiers, so the Inbox (the feed) and the rest of the library read from one copy, offline too.
    private static let tier = SliceTier.all
    /// `*` leaves out every `system.*` type, so the saved views are named beside it. The engine keeps them out of
    /// the items it shows.
    nonisolated static let slice = ["*", "system.view"]
    /// Held whole so a view that lists what is `beneath` an item can be answered from the copy.
    nonisolated static let sliceEdgeTypes = ["parent-of"]

    nonisolated static func needsFill(_ status: Status) -> Bool {
        status.hydration != .complete || status.sliceTier != .all || Set(status.sliceTypes) != Set(slice)
            || Set(status.sliceEdgeTypes) != Set(sliceEdgeTypes)
    }

    /// Only our own words go in: what stopped the lane, never an error's message.
    private static let log = Telemetry.logger(.sync)

    private let copy: WorkingCopy
    private let downloads: MarfaDownloads
    private let refreshing: any MarfaRefreshing
    private let hub: MarfaHub
    /// False once the engine has stopped taking events.
    private let tell: @Sendable (MarfaEngine.Event) -> Bool
    private var started = false
    private var stopped = false
    /// Set while the copy changes key, when every call on it is refused.
    private var paused = false
    private var consuming: Task<Void, Never>?
    /// What the copy last said it was doing, so a change of it is told once.
    private var connection: CopyConnection?
    private var fill: FillProgress?
    /// The calls of the app's own refreshes under way, which the report shows as updating.
    private var refreshes = 0
    private var wantsRefresh = false
    private var wantsHydration = false
    private var lane: Task<Void, Never>?
    private var wantsDrain = false
    /// The bin is read from the server alone, so it is read again when something may have changed it.
    private var wantsBin = false
    /// A read of the bin asked for and not yet due, and when the first ask of it came.
    private var binTimer: Task<Void, Never>?
    private var binAsked: ContinuousClock.Instant?
    private var working: Task<Void, Never>?
    private var fetching: Task<Void, Never>?
    private var wantsFetch = false
    private var flushers: [CheckedContinuation<Void, Never>] = []
    private var draining: [CheckedContinuation<Void, Never>] = []
    /// Rows the copy could not read, which only a hydration replaces.
    private var rehydration = Rehydration()
    /// Whether the person has been told of a stop since the copy last followed its server, so a stop is told once.
    private var told = false

    /// Rows the copy could not read and the hydration they wait for. A hydration replaces such a row from the server,
    /// but a row that is unreadable again after it would ask again for ever, so each row asks once.
    nonisolated struct Rehydration {
        private var asked: Set<String> = []
        private(set) var wanted = false

        /// Whether any of `ids` is new, which wants a hydration.
        mutating func ask(about ids: Set<String>) -> Bool {
            let fresh = ids.subtracting(asked)
            guard !fresh.isEmpty else { return false }
            asked.formUnion(fresh)
            wanted = true
            return true
        }

        /// A hydration succeeded.
        mutating func finished() {
            wanted = false
        }
    }

    init(copy: WorkingCopy, hub: MarfaHub, downloads: MarfaDownloads? = nil, refreshing: (any MarfaRefreshing)? = nil,
         tell: @escaping @Sendable (MarfaEngine.Event) -> Bool) {
        self.copy = copy
        self.downloads = downloads ?? MarfaDownloads(copy: copy)
        self.refreshing = refreshing ?? MarfaRefresh(copy: copy)
        self.hub = hub
        self.tell = tell
    }

    /// Nothing reaches the server before the engine has painted from the copy.
    func start() {
        guard !started else { return }
        started = true
        if let own = refreshing.updates() {
            consuming = Task { await self.consume(own) }
        } else {
            let updates = copy.updates()
            consuming = Task { await self.consume(updates) }
        }
        work()
    }

    /// The person asked for a refresh: the copy is caught up, or hydrated where it needs that, and what waits is sent.
    func refresh() {
        wantsRefresh = true
        work()
    }

    func drain() {
        wantsDrain = true
        work()
    }

    /// Rows the copy could not read, found by a read: the copy replaces them on a hydration, which keeps its queue.
    func unreadable(_ ids: Set<String>) {
        guard rehydration.ask(about: ids) else { return }
        Telemetry.rowsUnreadable(count: ids.count)
        wantsHydration = true
        work()
    }

    /// How long the bin's changes are let settle before it is read, and the longest a read waits for them to.
    nonisolated struct BinWait: Sendable {
        var quiet: Duration
        var longest: Duration
    }

    var binWait: BinWait {
        #if DEBUG
        if let wait = hooks.binWait.current { return wait }
        #endif
        return BinWait(quiet: .seconds(1), longest: .seconds(5))
    }

    #if DEBUG
    nonisolated let hooks = TestHooks()
    #endif

    /// An item may have gone to or left the server's bin, which the copy does not say. The bin is read from the
    /// server whole, so a flood of server changes reads it once they pause, and at least every `binWait.longest`.
    func binChanged() {
        guard !stopped else { return }
        let now = ContinuousClock.now
        let first = binAsked ?? now
        binAsked = first
        binTimer?.cancel()
        let wait = binWait
        let due = min(now + wait.quiet, first + wait.longest)
        binTimer = Task {
            try? await Task.sleep(until: due)
            guard !Task.isCancelled else { return }
            self.binDue()
        }
    }

    private func binDue() {
        binAsked = nil
        binTimer = nil
        wantsBin = true
        work()
    }

    /// Returns once a drain begun after this call has ended, or at once when the source is closing.
    func flush() async {
        guard !stopped else { return }
        await withCheckedContinuation { continuation in
            flushers.append(continuation)
            wantsDrain = true
            work()
        }
    }

    func stop() {
        Self.log.info("sync closed with the source")
        stopped = true
        consuming?.cancel()
        lane?.cancel()
        binTimer?.cancel()
        working?.cancel()
        fetching?.cancel()
        for flusher in flushers + draining { flusher.resume() }
        flushers = []
        draining = []
    }

    /// The person gives a new key in Settings; nothing is sent until then.
    nonisolated static var keyRefused: String {
        String(localized: "The Marfa server no longer accepts this library’s key. Enter a new key in Settings, or disconnect the library there and start again.")
    }

    /// What the server made of a key the copy was given.
    nonisolated enum KeyCheck: Hashable, Sendable {
        case accepted
        case refused
        /// The server could not be asked; the copy goes on with the key and asks again later.
        case unanswered(String?)
    }

    /// Gives the copy `key` between server calls and refreshes with it at once, so the caller learns whether the
    /// server takes it. Writes made meanwhile wait for the copy rather than fail. Writes a refused key parked
    /// clear on their own at the next drain, which follows an accepted key, so nothing is released here.
    func tryKey(_ key: String) async throws -> KeyCheck {
        paused = true
        lane?.cancel()
        working?.cancel()
        fetching?.cancel()
        defer {
            paused = false
            work()
        }
        try await downloads.useKey(key)
        do {
            try await refreshNow()
            wantsDrain = true
            return .accepted
        } catch let error as MarfaError where error.isKeyRefusal {
            Self.log.error("sync stopped: the server refused the key")
            return .refused
        } catch {
            await failed(error)
            return .unanswered((error as? MarfaError)?.message ?? error.localizedDescription)
        }
    }

    // MARK: Updates

    private func consume<Updates: AsyncSequence>(_ updates: Updates) async where Updates.Element == CopyUpdate, Updates.Failure == Never {
        for await update in updates {
            guard !stopped, !Task.isCancelled else { return }
            await take(update)
        }
    }

    /// Shows what the update says of the connection, hands the engine what to read again, and acts on a change of
    /// connection. The engine acknowledges each update, so the package coalesces what arrives while it reads.
    func take(_ update: CopyUpdate) async {
        let before = connection
        connection = update.connection
        fill = update.fill
        show(update.connection)
        hub.report.update { report in
            if let date = update.lastSynced { report.lastSynced = date }
        }
        publishPhase()
        if !update.reread.isEmpty || update.fill != nil || before != update.connection {
            await withCheckedContinuation { done in
                if !tell(.update(update, done)) { done.resume() }
            }
        }
        switch update.connection {
        case .needsHydration:
            wantsHydration = true
        case .following where before != .following:
            // The server answered: what waited is sent, and the bin and the kept files are asked again.
            wantsDrain = true
            wantsBin = true
            wantsFetch = true
        case .following where !update.reread.isEmpty:
            // Replay or a catch-up may have brought a file the copy does not hold yet.
            wantsFetch = true
        default:
            break
        }
        startFetch()
        work()
    }

    private func show(_ connection: CopyConnection) {
        switch connection {
        case .closed:
            break
        case .local:
            // No server to follow, as with the sample library: nothing is waited for.
            hub.set(.online)
        case .needsHydration, .connecting:
            hub.set(.connecting)
        case .following:
            told = false
            hub.set(.online)
        case .offline(let error):
            hub.set(.offline(reason: error.message))
        case .stopped(let error):
            stop(for: error)
        case .keyRefused:
            Self.log.error("sync stopped: the server refused the key")
            hub.set(.keyRefused)
            tellOnce(SourceFailure(kind: .denied, message: Self.keyRefused))
        }
    }

    /// A follow that stopped on an error that asking again may not clear shows as unavailable, told once, until the
    /// package's next try or a refresh succeeds.
    private func stop(for error: MarfaError) {
        if case .wrongServer = error {
            Task { await self.otherServer() }
            return
        }
        Telemetry.syncStopped(error, during: "refresh")
        hub.set(.unavailable(message: error.message))
        tellOnce(SourceFailure(kind: .failed, message: error.message))
    }

    /// The copy was made for another server: nothing in it is sent there. The writes it holds are counted for the
    /// person, who can start a new copy and lose them, or keep this one.
    private func otherServer() async {
        let unsent = (try? await copy.queue.all()).map { UInt64(MarfaProblems.unsent($0).count) }
        guard !stopped, connection.map({ if case .stopped = $0 { true } else { false } }) ?? false else { return }
        hub.set(.unavailable(message: Words.otherServer(unsent: unsent)))
        tellOnce(SourceFailure(kind: .failed, message: Words.otherServer(unsent: unsent)))
    }

    private func tellOnce(_ failure: SourceFailure) {
        guard !told else { return }
        told = true
        _ = tell(.failed(failure))
    }

    /// The report is catching up while a hydration runs, and updating while the copy asks its server or the
    /// person's refresh is under way.
    private func publishPhase() {
        let asking: Bool
        switch connection {
        case .needsHydration?, .connecting?: asking = true
        default: asking = false
        }
        let phase: SyncReport.Phase = fill != nil ? .catchingUp : (asking || refreshes > 0 ? .updating : .current)
        hub.report.update { $0.phase = phase }
    }

    // MARK: Refreshing

    private func work() {
        startFetch()
        startLane()
        guard started, !stopped, !paused, working == nil, wantsDrain || wantsBin else { return }
        working = Task { await self.loop() }
    }

    private func startLane() {
        guard started, !stopped, !paused, lane == nil, wantsRefresh || wantsHydration else { return }
        lane = Task { await self.laneLoop() }
    }

    private func laneLoop() async {
        while !stopped, !paused, !Task.isCancelled, wantsRefresh || wantsHydration {
            let hydrating = wantsHydration
            wantsRefresh = false
            wantsHydration = false
            refreshes += 1
            publishPhase()
            do {
                try await refreshNow(hydrating: hydrating)
            } catch {
                await failed(error)
            }
            refreshes -= 1
            publishPhase()
        }
        lane = nil
    }

    /// Catches the copy up, or hydrates it where it needs that or `hydrating` says the package asked for one, and
    /// asks again for what the server alone says.
    func refreshNow(hydrating: Bool = false) async throws {
        let status = try await refreshing.readStatus()
        if !hydrating, !Self.needsFill(status), !rehydration.wanted {
            try await refreshing.catchUp()
        } else {
            try await hydrate()
        }
        try Task.checkCancellation()
        fetchAttachments()
        wantsDrain = true
        wantsBin = true
        work()
    }

    /// The stable slice lets the core resume an interrupted fill and includes types registered later.
    private func hydrate() async throws {
        #if DEBUG
        hooks.seen.update { $0.hydrations += 1 }
        #endif
        let hydrated = try await refreshing.hydrate(types: Self.slice, tier: Self.tier, edgeTypes: Self.sliceEdgeTypes)
        #if DEBUG
        hooks.seen.update { $0.lastHydration = hydrated }
        #else
        _ = hydrated
        #endif
        rehydration.finished()
    }

    /// What a call the app made itself says of the copy. The package shows an unreachable server, a refused key
    /// and a copy that needs a hydration through the connection it reports, and tries again by itself; what is left
    /// is a fault that asking again may not clear, which stays stopped until a refresh succeeds.
    private func failed(_ error: any Error) async {
        guard !stopped, !Task.isCancelled else { return }
        guard let error = error as? MarfaError else {
            Telemetry.syncStoppedUnnamed(during: "refresh")
            hub.set(.unavailable(message: error.localizedDescription))
            return
        }
        if error.isOffline || error.isTransient || error.isKeyRefusal { return }
        switch error {
        // The call was canceled, the copy closed, or the key is changing; none is a fault.
        case .canceled, .closed: return
        case .keyChanging: return
        // Reported as `.needsHydration`, which hydrates.
        case .copyExpired, .instanceChanged, .noCursor, .hydrationIncomplete, .firstSyncWaiting: return
        default: stop(for: error)
        }
    }

    // MARK: Attachments

    func fetchAttachments() {
        wantsFetch = true
        startFetch()
    }

    private func startFetch() {
        guard wantsFetch, fetching == nil, !stopped, !paused else { return }
        fetching = Task { await self.fetchLoop() }
    }

    private func fetchLoop() async {
        while wantsFetch, !stopped, !paused, !Task.isCancelled {
            wantsFetch = false
            do {
                let report = try await refreshing.fetchKept()
                try Task.checkCancellation()
                #if DEBUG
                hooks.seen.update { $0.lastKeptFetch = report }
                #else
                _ = report
                #endif
            } catch is CancellationError {
            } catch {
                // A refresh and a return of the server fetch the downloads again.
                Self.log.notice("fetching kept files failed; a refresh or reconnection fetches them again")
            }
        }
        fetching = nil
        startFetch()
    }

    // MARK: Draining and the bin

    private func loop() async {
        while !stopped, !paused, !Task.isCancelled {
            if wantsDrain {
                wantsDrain = false
                draining = flushers
                flushers = []
                await runDrain()
                for flusher in draining { flusher.resume() }
                draining = []
            } else if wantsBin {
                wantsBin = false
                await runBin()
            } else {
                break
            }
        }
        working = nil
        // A loop canceled for a change of key leaves what it was asked for to the next one.
        if Task.isCancelled { work() }
    }

    /// A drain on a copy never hydrated sends one write and then throws, losing that write's verdict, so it waits
    /// for the first hydration. The package tries again a drain that left writes undelivered.
    private func runDrain() async {
        guard (try? await refreshing.readStatus())?.hydration == .complete else { return }
        #if DEBUG
        hooks.seen.update { $0.drains += 1 }
        #endif
        do {
            let report = try await copy.queue.drain()
            if report.verdicts.contains(where: { [.deleteItem, .restoreItem].contains($0.kind) }) { wantsBin = true }
        } catch {
            // A drain that throws loses its report, and the writes it answered first are recorded, so the engine
            // takes them from the queue below. An expired copy hydrates again.
            switch error as? MarfaError {
            case .copyExpired?, .instanceChanged?, .hydrationIncomplete?:
                wantsHydration = true
            default:
                break
            }
        }
        // The drain ends once the engine has taken the answers, so a flush returns with them taken.
        await withCheckedContinuation { taken in
            if !tell(.answers(taken)) { taken.resume() }
        }
    }

    /// Reads the server's bin a page at a time, newest change first, and tells the engine. A server that cannot be
    /// reached leaves the bin as it was, shown from what the engine last held, and is asked again when it can.
    private func runBin() async {
        #if DEBUG
        hooks.seen.update { $0.binReads += 1 }
        #endif
        var found: [Marfa.Item] = []
        var cursor: String?
        var complete = false
        do {
            for _ in 0..<Self.binPages {
                let page = try await copy.items.bin(after: cursor, limit: Self.binPageSize)
                found += page.items
                guard let next = page.nextCursor else {
                    complete = true
                    break
                }
                cursor = next
            }
        } catch let error as MarfaError {
            if error.isOffline || error.isTransient { return }
            if case .canceled = error { return }
            if case .closed = error { return }
            if case .invalid = error { return }
            Telemetry.binUnreadable(error)
            _ = tell(.failed(SourceFailure(kind: .failed, message: error.message)))
            return
        } catch {
            return
        }
        _ = tell(.binned(found, complete: complete))
    }

    nonisolated static let binPageSize = 100
    /// Recently Deleted shows this many pages of the bin; the server keeps the rest.
    nonisolated static let binPages = 10
}
