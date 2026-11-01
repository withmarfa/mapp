import Foundation
import Marfa
import os

/// What the copy tells (`WorkingCopy.updates()`), shown on the hub and handed to the engine one update at a time,
/// and the calls the app makes itself: hydrating a copy that needs it, draining after a write and
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
    /// True while a hydration is running or about to, so the progress updates it sends ask for no second one.
    private var hydrationUnderway = false
    /// Set when a drain failed for a reason nothing else handles and the person was told, until a drain succeeds.
    private var drainFailureTold = false
    private var lane: Task<Void, Never>?
    private var wantsDrain = false
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

    /// Nothing reaches the server before the engine has painted from the copy. A copy whose slice this build changed
    /// is filled again here, since the package catches up only a copy whose hydration is complete.
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        let deaf = hooks.ignoringCopy.current ?? false
        #else
        let deaf = false
        #endif
        if !deaf {
            let updates = copy.updates()
            consuming = Task { await self.consume(updates) }
        }
        work()
        Task { await self.fillIfSliceChanged() }
    }

    private func fillIfSliceChanged() async {
        guard let status = try? await refreshing.readStatus(), !stopped, !hydrationUnderway, Self.needsFill(status) else { return }
        wantsHydration = true
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

    #if DEBUG
    nonisolated let hooks = TestHooks()
    #endif

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
            failed(error)
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
    private func take(_ update: CopyUpdate) async {
        let before = connection
        connection = update.connection
        fill = update.fill
        show(update.connection, changed: before != update.connection)
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
        case .needsHydration where update.connection.fault == nil:
            // The package sends progress updates all through a hydration, each still `.needsHydration`. A copy
            // that stopped on a fault waits for the person's Refresh instead.
            if before != update.connection, !hydrationUnderway { wantsHydration = true }
        case .following where before != .following:
            // The server answered: what waited is sent, and the kept files are asked again.
            wantsDrain = true
            wantsFetch = true
        case .following where !update.reread.isEmpty:
            // Replay or a catch-up may have brought a file the copy does not hold yet.
            wantsFetch = true
        default:
            break
        }
        publishPhase()
        startFetch()
        work()
    }

    /// `changed` is whether the connection differs from the last update's, since a stop is reported and told once
    /// however many updates repeat it.
    private func show(_ connection: CopyConnection, changed: Bool) {
        switch connection {
        case .closed:
            break
        case .local:
            // No server to follow, as with the sample library: nothing is waited for.
            hub.set(.online)
        case .needsHydration:
            // A copy that stopped on a fault of the app's own first fill or hydration is shown as stopped, as a
            // stopped follow is; any other reason is cleared by the hydration this starts.
            if let fault = connection.fault {
                if changed { stop(for: fault) }
            } else {
                hub.set(.connecting)
            }
        case .connecting:
            hub.set(.connecting)
        case .following:
            // A drain that failed on a fault leaves the connection following, so the copy stays shown as stopped
            // until a drain succeeds.
            if !drainFailureTold {
                told = false
                hub.set(.online)
            }
        case .offline(let error):
            hub.set(.offline(reason: error.message))
        case .stopped(let error):
            if changed { stop(for: error) }
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
        #if DEBUG
        hooks.seen.update { $0.stops += 1 }
        #endif
        hub.set(.unavailable(message: error.message))
        tellOnce(SourceFailure(kind: .failed, message: error.message))
    }

    /// The copy was made for another server: nothing in it is sent there. The writes it holds are counted for the
    /// person, who can start a new copy and lose them, or keep this one.
    private func otherServer() async {
        let unsent = (try? await copy.queue.all()).map { UInt64(MarfaProblems.unsent($0).count) }
        guard !stopped, connection?.fault != nil else { return }
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
        case .connecting?: asking = true
        // The hydration this connection asks for, started or about to be; with none, Refresh is offered.
        case .needsHydration?: asking = hydrationUnderway || wantsHydration
        default: asking = false
        }
        let phase: SyncReport.Phase = fill != nil ? .catchingUp : (asking || refreshes > 0 ? .updating : .current)
        hub.report.update { $0.phase = phase }
    }

    // MARK: Refreshing

    private func work() {
        startFetch()
        startLane()
        guard started, !stopped, !paused, working == nil, wantsDrain else { return }
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
            hydrationUnderway = hydrating
            refreshes += 1
            publishPhase()
            do {
                try await refreshNow(hydrating: hydrating)
            } catch {
                failed(error)
            }
            refreshes -= 1
            hydrationUnderway = false
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
        work()
    }

    /// The stable slice lets the core resume an interrupted fill and includes types registered later.
    private func hydrate() async throws {
        hydrationUnderway = true
        defer { hydrationUnderway = false }
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

    /// What an app call that failed says of the copy. The package sets the connection for a `MarfaError` itself
    /// (`stopped`, `needsHydration`, `offline`, `keyRefused`, or none for a canceled call), and `show` shows it. It
    /// ignores `invalid`, `unknownType` and `validation` for an app's call, as proof of nothing about the server, so
    /// those are shown here with the errors of another kind. Either is shown as unavailable, told once.
    private func failed(_ error: any Error) {
        guard !stopped, !Task.isCancelled, !(error is CancellationError) else { return }
        if let error = error as? MarfaError {
            switch error {
            case .invalid, .unknownType, .validation: stop(for: error)
            default: break
            }
            return
        }
        Telemetry.syncStoppedUnnamed(during: "refresh")
        hub.set(.unavailable(message: error.localizedDescription))
        tellOnce(SourceFailure(kind: .failed, message: error.localizedDescription))
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

    // MARK: Draining

    private func loop() async {
        while !stopped, !paused, !Task.isCancelled {
            if wantsDrain {
                wantsDrain = false
                draining = flushers
                flushers = []
                await runDrain()
                for flusher in draining { flusher.resume() }
                draining = []
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
        var faulted = false
        do {
            #if DEBUG
            if let fault = hooks.faulting.current?(.drain) { throw fault }
            #endif
            _ = try await copy.queue.drain()
        } catch {
            // A drain that throws loses its report, and the writes it answered first are recorded, so the engine
            // takes them from the queue below. A copy that needs it hydrates again. The package retries a drain only
            // for a key refusal or a transient error and does not set the connection for a drain, so any other fault
            // leaves the writes queued, and is told once until a drain succeeds.
            if (error as? MarfaError)?.isHydrationNeeded ?? false {
                wantsHydration = true
            } else if Self.isDrainFault(error) {
                faulted = true
                if !drainFailureTold {
                    drainFailureTold = true
                    if let error = error as? MarfaError { stop(for: error) } else { failed(error) }
                }
            }
        }
        if !faulted, drainFailureTold {
            drainFailureTold = false
            told = false
            if connection == .following || connection == .local { hub.set(.online) }
        }
        // The drain ends once the engine has taken the answers, so a flush returns with them taken.
        await withCheckedContinuation { taken in
            if !tell(.answers(taken)) { taken.resume() }
        }
    }

    /// Whether a failed drain left the writes queued for a reason asking again may not clear, which the package
    /// neither retries nor shows. A copy with no server has nothing to send to, so that is no fault. An unreachable
    /// server, a transient error and a refused key are shown through the connection, and a copy that needs hydrating
    /// is hydrated.
    private static func isDrainFault(_ error: any Error) -> Bool {
        guard let error = error as? MarfaError else { return !(error is CancellationError) }
        if error.isOffline || error.isTransient || error.isKeyRefusal || error.isHydrationNeeded { return false }
        switch error {
        case .canceled, .closed, .noServer: return false
        default: return true
        }
    }
}

private nonisolated extension CopyConnection {
    /// The error the copy stopped on, where asking again may not clear it: the follow's or the app's own call's.
    /// A `needsHydration` for a reason a hydration clears is no fault.
    var fault: MarfaError? {
        switch self {
        case .stopped(let error): error
        case .needsHydration(let error?) where !error.isHydrationNeeded: error
        default: nil
        }
    }
}
