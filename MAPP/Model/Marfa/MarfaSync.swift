import Foundation
import Marfa

/// Everything the source asks of the server: hydrating, catching up and draining, one at a time, apart from the
/// engine, so a write reaches the copy's queue at once however long the network takes.
actor MarfaSync {
    private nonisolated enum Retry {
        case refresh, drain
    }

    /// One slice, the library tier. Marfa is to hold both tiers in one copy; the feed then joins this slice, never a
    /// second store.
    private static let tier = Marfa.Tier.library

    private let copy: WorkingCopy
    private let hub: MarfaHub
    /// False once the engine has stopped taking events.
    private let tell: @Sendable (MarfaEngine.Event) -> Bool
    private var started = false
    private var stopped = false
    private var wantsRefresh = false
    private var wantsDrain = false
    /// Until a refresh succeeds, a retry or a return of the server refreshes rather than only drains.
    private var refreshed = false
    private var working: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var failures = 0
    private var flushers: [CheckedContinuation<Void, Never>] = []
    private var draining: [CheckedContinuation<Void, Never>] = []
    /// How many drains this lane has sent, for the tests.
    private(set) var drains = 0

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

    /// Returns once a drain begun after this call has ended, or at once when the source is closing.
    func flush() async {
        guard !stopped else { return }
        await withCheckedContinuation { continuation in
            flushers.append(continuation)
            wantsDrain = true
            work()
        }
    }

    func reachable() {
        hub.set(.online)
        if refreshed { wantsDrain = true } else { wantsRefresh = true }
        work()
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

    /// The person gives a new key in Settings; nothing is sent until then.
    nonisolated static var keyRefused: String {
        String(localized: "The Marfa server refused this library’s key. Check the key in Settings.")
    }

    /// Five seconds, doubling to five minutes.
    nonisolated static func delay(after failures: Int) -> Duration {
        .seconds(min(5 * (1 << min(max(failures, 1) - 1, 10)), 300))
    }

    private func work() {
        guard started, !stopped, working == nil else { return }
        working = Task { await self.loop() }
    }

    private func loop() async {
        while !stopped {
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
            } else {
                break
            }
        }
        working = nil
    }

    private func runRefresh() async {
        if hub.connection != .online { hub.set(.connecting) }
        do {
            let status = try await copy.status()
            if status.hydration == .complete {
                _ = try await copy.catchUp()
                if Set(MarfaMapping.namespaces(of: try await catalogue())) != Set(status.sliceTypes) {
                    try await hydrate()
                }
            } else {
                try await hydrate()
            }
            refreshed = true
            succeeded()
            wantsDrain = true
        } catch {
            await failed(error, retrying: .refresh)
        }
    }

    /// A drain on a copy never hydrated sends one write and then throws, losing that write's verdict, so it waits
    /// for the first hydration.
    private func runDrain() async {
        guard (try? await copy.status())?.hydration == .complete else { return }
        drains += 1
        do {
            let report = try await copy.queue.drain()
            // The next drain waits until the engine has taken these answers, since the engine's forgetting them
            // would also forget a later drain's answers it has not taken yet.
            if !report.verdicts.isEmpty {
                await withCheckedContinuation { taken in
                    if !tell(.drained(report, taken)) { taken.resume() }
                }
            }
            switch Self.result(of: report) {
            case .parked(let reason):
                hub.set(.stopped(code: BlockedReason.credentialRefused.rawValue, message: reason))
                _ = tell(.failed(SourceFailure(kind: .denied, message: Self.keyRefused)))
            case .offline(let reason):
                hub.set(.offline(reason: reason))
                schedule(.drain)
            case .online:
                succeeded()
            case .idle:
                break
            }
        } catch {
            await failed(error, retrying: .drain)
        }
    }

    /// A new copy holds only Marfa's built-in types, so its first slice is theirs; the server's catalogue then
    /// names every namespace, and the copy is hydrated again with them all.
    private func hydrate() async throws {
        var slice = MarfaMapping.namespaces(of: try await catalogue())
        for _ in 0..<2 {
            _ = try await copy.hydrate(types: slice, tier: Self.tier)
            let wanted = MarfaMapping.namespaces(of: try await catalogue())
            if Set(wanted) == Set(slice) { break }
            slice = wanted
        }
    }

    private func catalogue() async throws -> Catalogue {
        try await MarfaMapping.catalogue(itemTypes: copy.catalog.itemTypes(), edgeTypes: copy.catalog.edgeTypes())
    }

    private func succeeded() {
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
            if !stopped { hub.set(.stopped(code: "failed", message: error.localizedDescription)) }
            return
        }
        switch error {
        case .network, .io, .unnamed, .redirected, .rateLimited:
            hub.set(.offline(reason: error.message))
            schedule(kind)
        case .unauthorized, .forbidden, .signedOut:
            hub.set(.stopped(code: error.code(), message: error.message))
            _ = tell(.failed(SourceFailure(kind: .denied, message: Self.keyRefused)))
        case .copyExpired:
            // The server asks for a new hydration, which keeps the queue. The follow that stopped for it runs
            // outside the loop, so the work starts here.
            refreshed = false
            wantsRefresh = true
            work()
        case .hydrationIncomplete, .noCursor, .canceled, .closed:
            break
        default:
            hub.set(.stopped(code: error.code(), message: error.message))
            _ = tell(.failed(SourceFailure(kind: .failed, message: error.message)))
        }
    }
}
