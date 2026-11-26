import Foundation

/// How many answers for a place a changing library may outrun before the next lands as it is (`PlaceWork`, the table).
nonisolated enum Outrun {
    static let limit = 3
}

/// What a window works out from a large place's items off the main actor for one of its layouts (`Browser.sections`,
/// `Browser.boardLanes`, the calendar's and the timeline's placings). The answer for the key last asked is held, and
/// stands until the next lands, so a layout never shows nothing while it is worked out again.
///
/// One run works at a time so edits cannot pile up work. After the library overtakes `Outrun.limit` runs, the next
/// overtaken answer can land if it still answers the window's choices.
@MainActor
final class PlaceWork<Key: Equatable & Sendable, Value: Sendable> {
    /// Whether the first key is the second's ask apart from what the library holds, so that an answer for it is a
    /// fair stand-in for the newer one. A key for another choice (a sort, a filter) is never one.
    private let isSameAsk: @Sendable (Key, Key) -> Bool
    /// The answers turned away since one last landed.
    private var outrun = 0

    init(isSameAsk: @escaping @Sendable (Key, Key) -> Bool = { _, _ in true }) {
        self.isSameAsk = isSameAsk
    }

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
        outrun = 0
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
            guard let self else { return }
            let isLatest = !Task.isCancelled && self.running?.token == token
            if isLatest { self.running = nil }
            // The window has left the place, so nothing lands.
            guard let asked = self.asked else { return }
            if isLatest, asked == key, accepts() {
                self.outrun = 0
                self.held = (key, value)
                return landed()
            }
            guard self.isSameAsk(key, asked) else { return }
            self.outrun += 1
            if self.outrun > Outrun.limit {
                self.outrun = 0
                self.held = (key, value)
                return landed()
            }
            // An answer the library outran is not held, but the window is told, so it asks again with what it holds
            // now instead of waiting on a run that will never land.
            if isLatest { landed() }
        }
        last = task
        running = (key, token, task)
    }

    /// Ends the ask when the window leaves the place.
    func cancel() {
        running?.task.cancel()
        running = nil
        asked = nil
        outrun = 0
    }

    /// Forgets what is held and asked and ends the run under way, as when the window changes library.
    func reset() {
        cancel()
        held = nil
    }
}
