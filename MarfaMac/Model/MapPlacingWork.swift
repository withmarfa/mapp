import Foundation

/// Keeps the last placement for the current place visible while a new placement runs off the main actor.
@MainActor @Observable
final class MapPlacingWork {
    nonisolated static let inPlaceLimit = 2_000

    /// Counts the answers that landed, which a view reads through `placing` to draw the new one.
    private var landed = 0
    @ObservationIgnored private var held: (key: Browser.MapKey, placing: MapLayout.Placing)?
    @ObservationIgnored private var running: (key: Browser.MapKey, task: Task<Void, Never>)?

    /// The placing for `key`: made now for a small place, and for a large one the last answer, or nil before the first.
    func placing(for key: Browser.MapKey, items: [Item], catalogue: Catalogue) -> MapLayout.Placing? {
        _ = landed
        if let held, held.key == key { return held.placing }
        guard items.count > Self.inPlaceLimit else {
            running?.task.cancel()
            running = nil
            let placing = MapLayout.placing(for: items, catalogue: catalogue)
            held = (key, placing)
            return placing
        }
        if running?.key != key {
            running?.task.cancel()
            let previous = running?.task
            let task = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                let placing = await Task.detached(priority: .userInitiated) { MapLayout.placing(for: items, catalogue: catalogue) }.value
                guard let self, !Task.isCancelled, self.running?.key == key else { return }
                self.running = nil
                self.held = (key, placing)
                self.landed += 1
            }
            running = (key, task)
        }
        // What the window held for another place or library is not this one's.
        guard let held, held.key.library == key.library, held.key.place == key.place else { return nil }
        return held.placing
    }

    /// Discards the result when the map leaves the window.
    func cancel() {
        running?.task.cancel()
        running = nil
    }
}
