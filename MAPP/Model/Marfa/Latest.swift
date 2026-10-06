import Foundation
import Synchronization

/// A value that changes, told to each watcher from the value it had when the watcher came.
nonisolated final class Latest<Value: Hashable & Sendable>: Sendable {
    private struct State {
        var value: Value
        var watchers: [UUID: AsyncStream<Value>.Continuation] = [:]
        var finished = false
    }

    private let state: Mutex<State>

    init(_ value: Value) {
        state = Mutex(State(value: value))
    }

    var value: Value { state.withLock { $0.value } }

    func values() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.watchers.removeValue(forKey: token) } }
        let finished = state.withLock { state in
            guard !state.finished else { return true }
            continuation.yield(state.value)
            state.watchers[token] = continuation
            return false
        }
        if finished { continuation.finish() }
        return stream
    }

    func set(_ value: Value) {
        update { $0 = value }
    }

    /// Watchers are told inside the lock, since two updaters racing would otherwise tell an older value last.
    func update(_ change: (inout Value) -> Void) {
        state.withLock { state in
            var value = state.value
            change(&value)
            guard value != state.value else { return }
            state.value = value
            for watcher in state.watchers.values { watcher.yield(value) }
        }
    }

    func finish() {
        let watchers = state.withLock { state in
            state.finished = true
            defer { state.watchers = [:] }
            return Array(state.watchers.values)
        }
        for watcher in watchers { watcher.finish() }
    }
}
