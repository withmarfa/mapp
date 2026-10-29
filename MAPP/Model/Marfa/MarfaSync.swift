import Foundation
import Marfa
import struct MarfaCore.BinPage
import struct MarfaCore.KeptFetch
import os

/// Hydrating, catching up and draining run in order apart from the engine, so writes reach the queue at once.
/// Attachment downloads run separately so they cannot hold up a drain or flush.
actor MarfaSync {
    private nonisolated enum Retry {
        case refresh, drain
    }

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

    /// Only our own words go in: what stopped the lane and when it tries again, never an error's message.
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
    private var wantsRefresh = false
    private var wantsDrain = false
    /// The bin is read from the server alone, so it is read again when something may have changed it.
    private var wantsBin = false
    /// Until a refresh succeeds, a retry or a return of the server refreshes rather than only drains.
    private var refreshed = false
    /// Set when a drain threw as an answer expired the copy. The answers wait in the queue until the copy is
    /// hydrated again, since the engine reads again the items they changed, which an expired copy refuses.
    private var answersWaiting = false
    private var working: Task<Void, Never>?
    private var fetching: Task<Void, Never>?
    private var wantsFetch = false
    private(set) var lastKeptFetch: KeptFetch?
    private var retry: Task<Void, Never>?
    private var failures = 0
    private var flushers: [CheckedContinuation<Void, Never>] = []
    private var draining: [CheckedContinuation<Void, Never>] = []
    /// How many drains this lane has sent, for the tests.
    private(set) var drains = 0
    /// How many times it has hydrated, for the tests.
    private(set) var hydrations = 0
    private(set) var lastHydration: HydrateReport?
    /// Rows the copy could not read, which only a hydration replaces.
    private var rehydration = Rehydration()
    /// Whether the person has been told of a stop since something last succeeded, so a fault the core ends a stream
    /// on again and again is told once.
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

    nonisolated enum DrainResult: Hashable, Sendable {
        /// The server refused the key and the core parked the queue until a new one is given.
        case parked(String)
        case offline(String?)
        case online
        /// Nothing was sent, so nothing was learned about the server.
        case idle
    }

    /// What a drain says of the server. A refused key is answered `blocked`, which counts as answered, before the
    /// core parks the queue, and a drain that got partway answered some writes, so neither is judged by `answered`.
    nonisolated static func result(of report: DrainReport) -> DrainResult {
        if let stopped = report.stopped { return .parked(stopped) }
        if report.undelivered > 0 || report.unavailable != nil { return .offline(report.unavailable) }
        if report.answered > 0 { return .online }
        return .idle
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
        started = true
        work()
    }

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
        wantsRefresh = true
        work()
    }

    /// An item may have gone to or left the server's bin, which the copy does not say.
    func binChanged() {
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

    /// The copy's held stream drains what waited; attachment retries and the bin are this lane's own work.
    func reachable() {
        hub.set(.online)
        if !refreshed { wantsRefresh = true }
        else { fetchAttachments() }
        wantsBin = true
        work()
    }

    /// A drain the copy ran when the server came back, whose answers the engine has taken.
    func drainedByFollow(_ report: DrainReport) {
        settle(report)
        work()
    }

    /// A drain the copy ran when the server came back stopped.
    /// The engine has taken the answers the drain recorded, or `answersTaken` is false and they wait for the next
    /// refresh, since the next drain reports only the writes it answers itself.
    func drainStopped(_ error: MarfaError, answersTaken: Bool) async {
        if !answersTaken { answersWaiting = true }
        await failed(error, retrying: .drain)
    }

    func unreachable(_ reason: String?) {
        hub.set(.offline(reason: reason))
    }

    /// A server event says the server is there, whatever was last believed.
    func heard() {
        if hub.connection != .online { hub.set(.online) }
        // A change the follow applied is the copy in step with the server, but a busy server would stamp the report
        // on every one.
        guard refreshed else { return }
        let now = Date.now
        if let last = hub.report.value.lastSynced, now.timeIntervalSince(last) < Self.stampInterval { return }
        hub.report.update { $0.lastSynced = now }
    }

    /// The least time between two stamps made by the follow.
    nonisolated static let stampInterval: TimeInterval = 30

    /// The follow stays stopped until the next hydration or catch-up.
    func stopped(_ error: MarfaError) async {
        await failed(error, retrying: .refresh)
    }

    func stop() {
        Self.log.info("sync closed with the source")
        stopped = true
        retry?.cancel()
        working?.cancel()
        fetching?.cancel()
        for flusher in flushers + draining { flusher.resume() }
        flushers = []
        draining = []
    }

    /// Why a copy expires when the server ends its key, the contract's word for it.
    nonisolated static let credentialEnded = "credential_ended"

    /// The person gives a new key in Settings; nothing is sent until then.
    nonisolated static var keyRefused: String {
        String(localized: "The Marfa server no longer accepts this library’s key. Enter a new key in Settings, or disconnect the library there and start again.")
    }

    /// Five seconds, doubling to five minutes.
    nonisolated static func delay(after failures: Int) -> Duration {
        .seconds(min(5 * (1 << min(max(failures, 1) - 1, 10)), 300))
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
        retry?.cancel()
        retry = nil
        working?.cancel()
        fetching?.cancel()
        defer {
            paused = false
            work()
        }
        hub.changingKey(true)
        do {
            try await downloads.useKey(key)
        } catch {
            hub.changingKey(false)
            throw error
        }
        hub.changingKey(false)
        failures = 0
        if hub.connection != .online { hub.set(.connecting) }
        do {
            try await refreshNow()
            refreshed = true
            succeeded()
            wantsDrain = true
            return .accepted
        } catch let error as MarfaError where Self.refusesKey(error) {
            if case .copyExpired = error { refreshed = false }
            Self.log.error("sync stopped: the server refused the key")
            hub.set(.keyRefused)
            return .refused
        } catch {
            await failed(error, retrying: .refresh)
            return .unanswered((error as? MarfaError)?.message ?? error.localizedDescription)
        }
    }

    nonisolated static func refusesKey(_ error: MarfaError) -> Bool {
        switch error {
        case .unauthorized, .forbidden, .signedOut: true
        case .copyExpired(let reason, _): reason == credentialEnded
        default: false
        }
    }

    private func work() {
        startFetch()
        guard started, !stopped, !paused, working == nil else { return }
        working = Task { await self.loop() }
    }

    private func loop() async {
        while !stopped, !paused, !Task.isCancelled {
            if wantsRefresh {
                wantsRefresh = false
                await runRefresh()
            } else if wantsDrain {
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
        // A loop cancelled for a change of key leaves what it was asked for to the next one.
        if Task.isCancelled { work() }
    }

    private func runRefresh() async {
        if hub.connection != .online { hub.set(.connecting) }
        do {
            try await refreshNow()
            refreshed = true
            succeeded()
            wantsDrain = true
            wantsBin = true
        } catch {
            await failed(error, retrying: .refresh)
        }
    }

    func refreshNow() async throws {
        hub.report.update { if $0.phase == .current { $0.phase = .updating } }
        // A hydration ends in `.current` itself; this covers a catch-up and a pull that throws.
        defer { hub.report.update { $0.phase = .current } }
        let status = try await refreshing.readStatus()
        if !Self.needsFill(status), !rehydration.wanted {
            try await refreshing.catchUp()
        } else {
            try await hydrate()
        }
        try Task.checkCancellation()
        fetchAttachments()
        // Kept until the queue has been read, so a read that fails is tried again by the next refresh.
        if answersWaiting, await takeAnswersFromQueue() { answersWaiting = false }
        hub.report.update { $0.lastSynced = .now }
    }

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
                // A successful call can still leave missing bytes. Keep its counts and reasons until the next fetch.
                lastKeptFetch = report
            } catch {
                // Refresh and reconnection retry downloads without changing the queue's retry or connection state.
            }
        }
        fetching = nil
        startFetch()
    }

    /// A drain on a copy never hydrated sends one write and then throws, losing that write's verdict, so it waits
    /// for the first hydration.
    private func runDrain() async {
        guard (try? await refreshing.readStatus())?.hydration == .complete else { return }
        drains += 1
        do {
            let report = try await copy.queue.drain()
            // The drain ends once the engine has taken these answers, so a flush returns with them taken.
            if !report.verdicts.isEmpty {
                await withCheckedContinuation { taken in
                    if !tell(.drained(report, taken)) { taken.resume() }
                }
            }
            settle(report)
        } catch {
            // A drain that throws loses its report, and the writes it answered first are recorded, so the answers
            // are read from the queue instead, for an expired copy (a source move or a retype) once the refresh
            // this asks for has hydrated it again.
            if case MarfaError.copyExpired = error {
                answersWaiting = true
            } else if await !takeAnswersFromQueue() {
                answersWaiting = true
            }
            await failed(error, retrying: .drain)
        }
    }

    /// What a drain that ended says of the server and of the bin.
    private func settle(_ report: DrainReport) {
        if report.verdicts.contains(where: { [.deleteItem, .restoreItem].contains($0.kind) }) { wantsBin = true }
        switch Self.result(of: report) {
        case .parked:
            hub.set(.keyRefused)
            _ = tell(.failed(SourceFailure(kind: .denied, message: Self.keyRefused)))
        case .offline(let reason):
            hub.set(.offline(reason: reason))
            schedule(.drain)
        case .online:
            succeeded()
        case .idle:
            break
        }
    }

    /// Each write the queue holds an answer for, as a drain would have reported it.
    nonisolated static func report(answeredIn queue: [Marfa.QueuedWrite]) -> DrainReport {
        let verdicts = queue.filter { $0.verdict != nil }.map {
            DrainVerdict(
                id: $0.id, kind: $0.kind, itemId: $0.itemId, edgeId: $0.edgeId, verdict: $0.verdict, refusals: $0.refusals)
        }
        return DrainReport(answered: UInt64(verdicts.count), verdicts: verdicts)
    }

    /// Whether the queue could be read, which says nothing of whether it held answers.
    private func takeAnswersFromQueue() async -> Bool {
        guard let queue = try? await copy.queue.all() else { return false }
        let report = Self.report(answeredIn: queue)
        guard !report.verdicts.isEmpty else { return true }
        await withCheckedContinuation { taken in
            if !tell(.drained(report, taken)) { taken.resume() }
        }
        return true
    }

    /// Reads the server's bin a page at a time, newest change first, and tells the engine. A server that cannot be
    /// reached leaves the bin as it was, shown from what the engine last held, and is asked again when it can.
    private func runBin() async {
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
            switch error {
            case .network, .io, .unnamed, .redirected, .rateLimited, .closed, .invalid, .canceled, .noServer:
                break
            default:
                _ = tell(.failed(SourceFailure(kind: .failed, message: error.message)))
            }
            return
        } catch {
            return
        }
        _ = tell(.binned(found, complete: complete))
    }

    nonisolated static let binPageSize = 100
    /// Recently Deleted shows this many pages of the bin; the server keeps the rest.
    nonisolated static let binPages = 10

    /// The stable slice lets the core resume an interrupted fill and includes types registered later.
    private func hydrate() async throws {
        hub.report.update { $0.phase = .catchingUp }
        defer { hub.report.update { $0.phase = .current } }
        hydrations += 1
        // Hydration announces only its end. One acknowledged read at a time shows pages as they arrive,
        // without letting a slow engine accumulate progress events ahead of a person's writes.
        let progress = Task { [tell] in
            while !Task.isCancelled {
                await withCheckedContinuation { done in
                    if !tell(.fillProgress(done)) { done.resume() }
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        defer { progress.cancel() }
        lastHydration = try await refreshing.hydrate(types: Self.slice, tier: Self.tier, edgeTypes: Self.sliceEdgeTypes)
        rehydration.finished()
    }

    private func succeeded() {
        told = false
        failures = 0
        retry?.cancel()
        retry = nil
        hub.set(.online)
    }

    private func schedule(_ kind: Retry) {
        failures += 1
        retry?.cancel()
        let delay = Self.delay(after: failures)
        Self.log.notice("sync will \(kind == .refresh ? "refresh" : "drain", privacy: .public) again in \(delay.inMilliseconds / 1000, privacy: .public) s, after \(self.failures, privacy: .public) failures")
        retry = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.retryNow(kind)
        }
    }

    private func retryNow(_ kind: Retry) {
        if kind == .refresh || !refreshed { wantsRefresh = true } else { wantsDrain = true }
        work()
    }

    private func failed(_ error: any Error, retrying kind: Retry) async {
        guard !stopped, let error = error as? MarfaError else {
            if !stopped {
                Self.log.error("sync stopped on a failure of a kind the package does not name")
                hub.set(.stopped(code: "failed", message: error.localizedDescription))
            }
            return
        }
        switch error {
        case .network, .io, .unnamed, .redirected, .rateLimited:
            hub.set(.offline(reason: error.message))
            schedule(kind)
        case _ where Self.refusesKey(error):
            // A key refused for good also expires the copy; hydrating again before a new key is given would only
            // be refused again.
            if case .copyExpired = error { refreshed = false }
            hub.set(.keyRefused)
            _ = tell(.failed(SourceFailure(kind: .denied, message: Self.keyRefused)))
        case .copyExpired:
            // The server asks for a new hydration, which keeps the queue. The follow that stopped for it runs
            // outside the loop, so the work starts here.
            Self.log.notice("sync restarts: the copy expired, so it hydrates again")
            refreshed = false
            wantsRefresh = true
            work()
        case .hydrationIncomplete, .noCursor, .canceled, .closed:
            break
        case .invalid:
            // The copy was changing its key or moved during the call; the package asks for it again.
            schedule(kind)
        default:
            Self.log.error("sync stopped on a failure it does not retry")
            hub.set(.stopped(code: error.code(), message: error.message))
            guard !told else { return }
            told = true
            _ = tell(.failed(SourceFailure(kind: .failed, message: error.message)))
        }
    }
}
