import Foundation
import Marfa
import struct MarfaCore.BinPage
import os

nonisolated private let log = Logger(subsystem: "com.withmarfa.mapp", category: "marfa")

/// Everything the source asks of the server: hydrating, catching up and draining, one at a time, apart from the
/// engine, so a write reaches the copy's queue at once however long the network takes.
actor MarfaSync {
    private nonisolated enum Retry {
        case refresh, drain
    }

    /// One slice of both tiers, so the Inbox (the feed) and the rest of the library read from one copy, offline too.
    private static let tier = SliceTier.all

    private let copy: WorkingCopy
    private let hub: MarfaHub
    /// False once the engine has stopped taking events.
    private let tell: @Sendable (MarfaEngine.Event) -> Bool
    private var started = false
    private var stopped = false
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
    private var retry: Task<Void, Never>?
    private var failures = 0
    private var flushers: [CheckedContinuation<Void, Never>] = []
    private var draining: [CheckedContinuation<Void, Never>] = []
    /// How many drains this lane has sent, for the tests.
    private(set) var drains = 0
    /// How many times it has hydrated, for the tests.
    private(set) var hydrations = 0
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
        /// The server refused the sign-in and the core parked the queue until the person signs in again.
        case parked(String)
        case offline(String?)
        case online
        /// Nothing was sent, so nothing was learned about the server.
        case idle
    }

    /// What a drain says of the server. A refused sign-in is answered `blocked`, which counts as answered, before the
    /// core parks the queue, and a drain that got partway answered some writes, so neither is judged by `answered`.
    nonisolated static func result(of report: DrainReport) -> DrainResult {
        if let stopped = report.stopped { return .parked(stopped) }
        if report.undelivered > 0 || report.unavailable != nil { return .offline(report.unavailable) }
        if report.answered > 0 { return .online }
        return .idle
    }

    init(copy: WorkingCopy, hub: MarfaHub, tell: @escaping @Sendable (MarfaEngine.Event) -> Bool) {
        self.copy = copy
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

    /// The copy's held stream drains what waited, so a refreshed copy asks for nothing else but the bin.
    func reachable() {
        hub.set(.online)
        if !refreshed { wantsRefresh = true }
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
    }

    /// The follow stays stopped until the next hydration or catch-up.
    func stopped(_ error: MarfaError) async {
        await failed(error, retrying: .refresh)
    }

    func stop() {
        stopped = true
        retry?.cancel()
        working?.cancel()
        for flusher in flushers + draining { flusher.resume() }
        flushers = []
        draining = []
    }

    /// Why a copy expires when the server ends its credential, the contract's word for it.
    nonisolated static let credentialEnded = "credential_ended"

    /// The person signs in again in Settings; nothing is sent until then.
    nonisolated static var signedOut: String {
        String(localized: "MAPP is signed out of your Marfa server. Sign in again in Settings to send your changes.")
    }

    /// Five seconds, doubling to five minutes.
    nonisolated static func delay(after failures: Int) -> Duration {
        .seconds(min(5 * (1 << min(max(failures, 1) - 1, 10)), 300))
    }

    /// Whether `error` means the server no longer takes this sign-in, which only signing in again mends.
    nonisolated static func endsSignIn(_ error: MarfaError) -> Bool {
        switch error {
        case .unauthorized, .forbidden, .signedOut: true
        case .copyExpired(let reason, _): reason == credentialEnded
        default: false
        }
    }

    private func work() {
        guard started, !stopped, working == nil else { return }
        working = Task { await self.loop() }
    }

    private func loop() async {
        while !stopped, !Task.isCancelled {
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

    private func refreshNow() async throws {
        let status = try await copy.status()
        if status.hydration == .complete {
            _ = try await copy.catchUp()
            // A copy hydrated for one tier, as an earlier version of the app made them, takes the other too.
            let namespaces = try await MarfaMapping.namespaces(of: catalogue())
            if rehydration.wanted || status.sliceTier != Self.tier || Set(namespaces) != Set(status.sliceTypes) {
                try await hydrate()
            }
        } else {
            try await hydrate()
        }
        // Kept until the queue has been read, so a read that fails is tried again by the next refresh.
        if answersWaiting, await takeAnswersFromQueue() { answersWaiting = false }
    }

    /// A drain on a copy never hydrated sends one write and then throws, losing that write's verdict, so it waits
    /// for the first hydration.
    private func runDrain() async {
        guard (try? await copy.status())?.hydration == .complete else { return }
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
            hub.set(.signedOut)
            _ = tell(.failed(SourceFailure(kind: .denied, message: Self.signedOut)))
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

    /// A new copy holds only Marfa's built-in types, so its first slice is theirs; the server's catalogue then
    /// names every namespace, and the copy is hydrated again with them all.
    private func hydrate() async throws {
        hub.report.update { $0.phase = .catchingUp }
        defer { hub.report.update { $0.phase = .current } }
        hydrations += 1
        var slice = MarfaMapping.namespaces(of: try await catalogue())
        for _ in 0..<2 {
            _ = try await copy.hydrate(types: slice, tier: Self.tier)
            let wanted = MarfaMapping.namespaces(of: try await catalogue())
            if Set(wanted) == Set(slice) { break }
            slice = wanted
        }
        rehydration.finished()
    }

    private func catalogue() async throws -> Catalogue {
        try await MarfaMapping.catalogue(itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
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
                log.error("following the server stopped: \(error.localizedDescription, privacy: .public)")
                hub.set(.stopped(.other))
            }
            return
        }
        switch error {
        case .network, .io, .unnamed, .redirected, .rateLimited:
            hub.set(.offline(reason: error.message))
            schedule(kind)
        case _ where Self.endsSignIn(error):
            // A sign-in the server ends also expires the copy; hydrating again before the person signs in again
            // would only be refused again.
            if case .copyExpired = error { refreshed = false }
            hub.set(.signedOut)
            _ = tell(.failed(SourceFailure(kind: .denied, message: Self.signedOut)))
        case .copyExpired:
            // The server asks for a new hydration, which keeps the queue. The follow that stopped for it runs
            // outside the loop, so the work starts here.
            refreshed = false
            wantsRefresh = true
            work()
        case .hydrationIncomplete, .noCursor, .canceled, .closed:
            break
        case .invalid:
            // The copy moved during the call; the package asks for it again.
            schedule(kind)
        default:
            log.error("following the server stopped: \(error.code(), privacy: .public): \(error.message, privacy: .public)")
            hub.set(.stopped(CopyFailure(error)))
            guard !told else { return }
            told = true
            _ = tell(.failed(SourceFailure(kind: .failed, message: error.message)))
        }
    }
}
