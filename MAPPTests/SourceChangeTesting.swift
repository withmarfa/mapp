import Foundation
import Marfa
@testable import MAPP

extension SourceChange {
    /// One step of a source that changed these items alone.
    nonisolated static func upserted(_ items: [MAPP.Item]) -> SourceChange { .changed(ItemChanges(upserted: items)) }

    /// One step of a source that removed these items alone.
    nonisolated static func removed(_ ids: [ItemID]) -> SourceChange { .changed(ItemChanges(removed: ids)) }
}

extension SourceSnapshot {
    /// The library as a reader holds it once it has taken `change`, in the order a late reader's `.loaded` gives.
    nonisolated mutating func apply(_ change: SourceChange) {
        switch change {
        case .loaded(let snapshot): self = snapshot
        case .changed(let changes):
            let gone = Set(changes.removed)
            var held = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for id in gone { held[id] = nil }
            for item in changes.upserted { held[item.id] = item }
            items = held.values.sorted(by: MarfaHub.newestFirst)
            for id in gone { bodies[id] = nil }
            for body in changes.bodies { bodies[body.id] = body }
        case .catalogue(let catalogue): self.catalogue = catalogue
        case .views(let views): self.views = views
        case .answered, .taken, .unavailable: break
        }
    }
}

extension MarfaSource {
    /// Tells the engine what the copy's lifecycle would after `change`:
    /// the kind of reread the change calls for, since the engine reads from its own cursor what changed.
    nonisolated func hear(_ change: Marfa.Change) async {
        var parts = Reread.Parts()
        var everything = false
        switch change.origin {
        case .refreshed(.viewWritten): parts.views = true
        case .refreshed(.forgotten), .queueDrained, .queueNotDrained: parts.queue = true
        case .refreshed(.hydrated), .refreshed(.unfinished): everything = true
        // The package names the rows a catch-up changed; the engine reads them from its own cursor.
        case .refreshed(.caughtUp): parts.rows = ChangedRows(items: [change.itemId ?? "caught-up"])
        default:
            parts.rows = ChangedRows(items: change.itemId.map { [$0] } ?? [], edges: change.edgeId.map { [$0] } ?? [])
            everything = parts.rows.isEmpty
        }
        await send(CopyUpdate(reread: everything ? .everything : .parts(parts), connection: .following))
    }

    /// Hands the engine one update and returns once it is in the engine's events, not once it is read, so a test can
    /// tell the engine more while it is held in a read. `engineTook` waits for it.
    nonisolated func send(_ update: CopyUpdate) async {
        await withCheckedContinuation { (queued: CheckedContinuation<Void, Never>) in
            Task {
                await withCheckedContinuation { done in
                    if case .terminated = events.yield(.update(update, done)) { done.resume() }
                    queued.resume()
                }
            }
        }
    }

    /// Tells the engine one update, as `MarfaSync` does, and returns once it has read it.
    nonisolated func tell(_ update: CopyUpdate) async {
        await withCheckedContinuation { done in
            if case .terminated = events.yield(.update(update, done)) { done.resume() }
        }
    }

    /// Tells the engine to take the answers the copy holds, and returns once it has.
    nonisolated func tellAnswers() async {
        await withCheckedContinuation { done in
            if case .terminated = events.yield(.answers(done)) { done.resume() }
        }
    }

    /// Returns once the engine has taken every event told before the call, which `queueSubmitted` no longer waits
    /// for: it waits for writes alone.
    nonisolated func engineTook() async {
        _ = await unsentWrites()
    }
}

/// The update stream a test controls: the package's first update, which asks to read everything, and then only what
/// the test sends. The fake copy's lifecycle would add updates of its own for the test's direct writes, and its
/// reads name no cursor, so a count of the engine's whole reads would depend on timing.
nonisolated func quietUpdates() -> AsyncStream<CopyUpdate>? {
    let (stream, continuation) = AsyncStream<CopyUpdate>.makeStream()
    continuation.yield(CopyUpdate(reread: .everything, connection: .local))
    return stream
}

/// The ordinary refresh steps over a copy, with `quietUpdates`.
nonisolated struct QuietRefresh: MarfaRefreshing {
    let base: MarfaRefresh
    init(copy: WorkingCopy) { base = MarfaRefresh(copy: copy) }
    func readStatus() async throws -> Status { try await base.readStatus() }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        try await base.hydrate(types: types, tier: tier, edgeTypes: edgeTypes)
    }
    func catchUp() async throws { try await base.catchUp() }
    func fetchKept() async throws -> KeptFetch { try await base.fetchKept() }
    func updates() -> AsyncStream<CopyUpdate>? { quietUpdates() }
}
