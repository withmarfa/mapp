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
    /// Tells the engine a change of the copy, as the follow does.
    nonisolated func hear(_ change: Marfa.Change) {
        hear(.change(change))
    }

    /// Tells the engine its copy's changes have a new stream, as the follow does after a stream ended on a fault.
    nonisolated func hearResumed() {
        hear(.resumed)
    }

    private nonisolated func hear(_ entry: MarfaFollow.Heard.Entry) {
        _ = engine.heard.add(entry) { event in
            if case .terminated = events.yield(event) { false } else { true }
        }
    }

    /// Returns once the engine has taken every event told before the call, which `queueSubmitted` no longer waits
    /// for: it waits for writes alone.
    nonisolated func engineTook() async {
        _ = await unsentWrites()
    }
}
