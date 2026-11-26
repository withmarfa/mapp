import Foundation

/// What a window works out from a large place's items off the main actor for one of its layouts (`Browser.sections`,
/// `Browser.boardLanes`, the calendar's and the timeline's placings). The answer for the key last asked is held, and
/// stands until the next lands, so a layout never shows nothing while it is worked out again.
///
/// One rule decides what lands: a run's answer carries the key it was worked out for, and is held only if that key is
/// still the one last asked when it lands. One run works at a time: a newer one waits for the run before it, cancelled
/// or not, to end.
@MainActor
final class PlaceWork<Key: Equatable & Sendable, Value: Sendable> {
    private(set) var held: (key: Key, value: Value)?
    /// The key the window asked for last, which a run's answer must be for to land.
    private var asked: Key?
    private var running: (key: Key, token: UUID, task: Task<Void, Never>)?
    /// The last run begun, cancelled or not, which the next waits for.
    private var last: Task<Void, Never>?

    /// The run under way, if any, and what it is for.
    var runningKey: Key? { running?.key }

    /// Takes `key` as what the window asks for now, ends a run for anything else, and returns the answer held for it.
    func value(for key: Key) -> Value? {
        asked = key
        if let running, running.key != key {
            running.task.cancel()
            self.running = nil
        }
        guard let held, held.key == key else { return nil }
        return held.value
    }

    /// Holds `value`, worked out in place, and ends any run under way, which is then older.
    func hold(_ value: Value, for key: Key) {
        running?.task.cancel()
        running = nil
        asked = key
        held = (key, value)
    }

    /// Works out the value for `key` with `make` off the main actor, unless a run for it is under way, and holds it if `key`
    /// is still the one asked when it lands and `accepts` still holds; `landed` is told on the main actor, also when
    /// `accepts` turns it away, so the window asks again. A run waits for the one before it to end,
    /// so a steady stream of changes never piles work up. With `settling`, a run of changes is let end first.
    func start(
        _ key: Key, settling: Duration? = nil, _ make: @escaping @Sendable () -> Value,
        accepts: @escaping @MainActor () -> Bool = { true }, landed: @escaping @MainActor () -> Void
    ) {
        asked = key
        guard running?.key != key else { return }
        running?.task.cancel()
        let previous = last
        let token = UUID()
        let task = Task { [weak self] in
            if let settling { try? await Task.sleep(for: settling) }
            await previous?.value
            guard !Task.isCancelled else { return }
            let value = await Task.detached(priority: .userInitiated) { make() }.value
            guard let self, !Task.isCancelled, self.running?.token == token else { return }
            self.running = nil
            guard self.asked == key else { return }
            // An answer the library outran is not held, but the window is told, so it asks again with what it holds
            // now instead of waiting on a run that will never land.
            guard accepts() else { return landed() }
            self.held = (key, value)
            landed()
        }
        last = task
        running = (key, token, task)
    }

    /// Ends the ask when the window leaves the place.
    func cancel() {
        running?.task.cancel()
        running = nil
        asked = nil
    }

    /// Forgets what is held and asked and ends the run under way, as when the window changes library.
    func reset() {
        cancel()
        held = nil
    }
}
