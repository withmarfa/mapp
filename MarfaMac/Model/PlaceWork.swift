import Foundation

/// What a window works out from a large place's items off the main actor for one of its layouts (`Browser.sections`,
/// `Browser.boardLanes`, the calendar's and the timeline's placings). The answer for the key last asked is held, and
/// stands until the next lands, so a layout never shows nothing while it is worked out again. One run is under way at a
/// time: a newer key ends the run before it, whose answer is never held.
@MainActor
final class PlaceWork<Key: Equatable & Sendable, Value: Sendable> {
    private(set) var held: (key: Key, value: Value)?
    private var running: (key: Key, token: UUID, task: Task<Void, Never>)?

    /// The run under way, if any, and what it is for.
    var runningKey: Key? { running?.key }

    /// The value held for `key`, if it is what is held. A run under way for another key is then older and is ended, so an
    /// answer asked for before the person went back, such as a sort they left, never lands over this one.
    func value(for key: Key) -> Value? {
        guard let held, held.key == key else { return nil }
        if let running, running.key != key {
            running.task.cancel()
            self.running = nil
        }
        return held.value
    }

    /// Holds `value`, worked out in place, and ends any run under way, which is then older.
    func hold(_ value: Value, for key: Key) {
        running?.task.cancel()
        running = nil
        held = (key, value)
    }

    /// Works out the value for `key` with `make` off the main actor, unless a run for it is under way, and holds it then
    /// if no newer run began; `landed` is told on the main actor. A run waits for the one it replaces to end, at its next
    /// step, so a steady stream of changes never piles work up. With `settling`, a run of changes is let end first.
    func start(
        _ key: Key, settling: Duration? = nil, _ make: @escaping @Sendable () -> Value, landed: @escaping @MainActor () -> Void
    ) {
        guard running?.key != key else { return }
        running?.task.cancel()
        let previous = running?.task
        let token = UUID()
        let task = Task { [weak self] in
            if let settling { try? await Task.sleep(for: settling) }
            await previous?.value
            guard !Task.isCancelled else { return }
            let value = await Task.detached(priority: .userInitiated) { make() }.value
            guard let self, !Task.isCancelled, self.running?.token == token else { return }
            self.running = nil
            self.held = (key, value)
            landed()
        }
        running = (key, token, task)
    }

    /// Forgets what is held and ends the run under way, as when the window changes library.
    func reset() {
        running?.task.cancel()
        running = nil
        held = nil
    }
}
