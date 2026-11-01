import Foundation
import Marfa
import MarfaTesting
import Testing
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

/// A source over a fake copy, painted and hearing the copy's updates, so a test scripts what the package tells
/// with `fake.sendUpdate` and the sync, the hub and the engine take it as they take the package's own. Returns once
/// the first update has been taken, which `sendUpdate` needs: it is delivered to the sequences held when it is sent.
nonisolated func scriptedSource(
    _ fake: FakeCopy = WorkingCopy.fake(), refreshing: any MarfaRefreshing, reading: (any MarfaReading)? = nil
) async throws -> (FakeCopy, MarfaSource, ChangeLog) {
    let source = MarfaSource(
        copy: fake.copy, connection: SampleLibrary.connection, reading: reading ?? MarfaRead(copy: fake.copy), refreshing: refreshing)
    let log = ChangeLog(source)
    source.events.yield(.paint)
    _ = try #require(await log.wait { $0.snapshot != nil })
    try #require(await waitForConnection(source) { $0 == .online }, "the sync never took the copy's first update")
    return (fake, source, log)
}
