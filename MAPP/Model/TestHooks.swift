#if DEBUG
import Foundation
import Marfa
import Synchronization

/// A step a test takes inside a model type, or a value it sets there, read where that step runs. Debug builds only:
/// a shipping type holds one `hooks` value and reads it at each step behind `#if DEBUG`, with no setter of its own.
nonisolated final class TestHook<Value: Sendable>: Sendable {
    private let value = Mutex<Value?>(nil)

    init() {}

    var current: Value? { value.withLock { $0 } }

    func set(_ newValue: Value?) {
        value.withLock { $0 = newValue }
    }
}

/// What a model type saw, counted for a test as it happens. Debug builds only, like `TestHook`.
nonisolated final class TestTally<Value: Sendable>: Sendable {
    private let value: Mutex<Value>

    init(_ initial: Value) {
        value = Mutex(initial)
    }

    var current: Value { value.withLock { $0 } }

    func update(_ change: (inout Value) -> Void) {
        value.withLock { change(&$0) }
    }
}

extension MarfaEngine {
    nonisolated struct TestHooks: Sendable {
        /// Runs before each drain's answers are taken.
        let answering = TestHook<@Sendable () async -> Void>()
        /// Runs after the queue was last read and before the answers are forgotten.
        let forgetting = TestHook<@Sendable () async -> Void>()
        /// Chooses the error the copy refuses a write with, since a copy made for the tests is never brought up to date.
        let refusing = TestHook<@Sendable (ItemWrite) -> MarfaError?>()
        /// Replaces how long a held undo waits for a copy that is not catching up.
        let holdLimit = TestHook<Duration>()
    }
}

extension MarfaSync {
    nonisolated struct TestHooks: Sendable {
        /// Replaces how long the bin's changes settle before it is read, and the longest a read waits for them.
        let binWait = TestHook<BinWait>()
        /// What the lane has done.
        let seen = TestTally(Seen())

        nonisolated struct Seen: Sendable {
            /// The drains sent.
            var drains = 0
            /// The hydrations begun.
            var hydrations = 0
            /// The reads of the bin begun.
            var binReads = 0
            /// The report of the last fetch of kept files that succeeded.
            var lastKeptFetch: KeptFetch?
            /// The report of the last hydration that finished.
            var lastHydration: HydrateReport?
        }

        var drains: Int { seen.current.drains }
        var hydrations: Int { seen.current.hydrations }
        var binReads: Int { seen.current.binReads }
        var lastKeptFetch: KeptFetch? { seen.current.lastKeptFetch }
        var lastHydration: HydrateReport? { seen.current.lastHydration }
    }
}

extension MarfaDownloads {
    nonisolated struct TestHooks: Sendable {
        /// Runs after the downloads are trimmed and before the budget is put back.
        let removing = TestHook<@Sendable () async -> Void>()
    }
}

extension PictureCache {
    nonisolated struct TestHooks: Sendable {
        /// Runs as a trim begins, given whether the lock `removeAll` and `store` share is free then.
        let trimming = TestHook<@Sendable (_ lockIsFree: Bool) -> Void>()
    }
}
#endif
