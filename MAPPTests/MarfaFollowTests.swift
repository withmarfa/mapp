import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// The streams the core hands out, which it finishes when a fault ends them, and what the engine is told.
private nonisolated final class Streams: Sendable {
    private struct State {
        var pending: [AsyncStream<Change>] = []
        var taken = 0
        var told: [MarfaEngine.Event] = []
        var waits: [Duration] = []
    }

    private let state = Mutex(State())

    init(_ streams: [AsyncStream<Change>]) {
        state.withLock { $0.pending = streams }
    }

    func next() -> AsyncStream<Change> {
        state.withLock { state in
            state.taken += 1
            return state.pending.isEmpty ? AsyncStream { _ in } : state.pending.removeFirst()
        }
    }

    func tell(_ event: MarfaEngine.Event) -> Bool {
        state.withLock { $0.told.append(event) }
        return true
    }

    func wait(_ delay: Duration) async {
        state.withLock { $0.waits.append(delay) }
    }

    var taken: Int { state.withLock { $0.taken } }
    var waits: [Duration] { state.withLock { $0.waits } }
    var heard: [Change] {
        state.withLock { $0.told.compactMap { if case .change(let change) = $0 { change } else { nil } } }
    }
    var resumed: Int { state.withLock { $0.told.count { if case .resumed = $0 { true } else { false } } } }
}

private nonisolated func finished(_ changes: Change...) -> AsyncStream<Change> {
    AsyncStream { continuation in
        for change in changes { continuation.yield(change) }
        continuation.finish()
    }
}

private nonisolated let stopped = Change(origin: .stopped(.network(message: "gone")), itemId: nil, edgeId: nil)
private nonisolated let saved = Change(origin: .local(.updateItem), itemId: "a", edgeId: nil)

@Suite struct MarfaFollowTests {
    private func settle(until condition: () -> Bool) async {
        let clock = ContinuousClock()
        let end = clock.now + .seconds(10)
        while !condition(), clock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aStreamTheCoreEndedOnAFaultIsReplacedAndTheCopyIsReadAgain() async {
        let streams = Streams([finished(saved, stopped), finished(saved)])
        let task = MarfaFollow.start(
            streams.next(), next: { streams.next() }, wait: { await streams.wait($0) }, tell: { streams.tell($0) })
        await settle { streams.taken >= 3 && streams.heard.count >= 3 }
        task.cancel()

        #expect(streams.heard == [saved, stopped, saved], "every stream's changes reach the engine, in order")
        #expect(streams.resumed >= 2, "a change between two streams is not heard, so the copy is read again after each new one")
        #expect(streams.taken >= 3)
    }

    @Test func aNewStreamIsAskedForOnlyAfterAWait() async {
        let streams = Streams([finished(stopped), finished(stopped), finished(stopped)])
        let task = MarfaFollow.start(
            streams.next(), next: { streams.next() }, wait: { await streams.wait($0) }, tell: { streams.tell($0) })
        await settle { streams.waits.count >= 3 }
        task.cancel()

        // A core that refuses a place again and again is asked at a falling rate, never in a tight loop.
        #expect(Array(streams.waits.prefix(3)) == [MarfaSync.delay(after: 1), MarfaSync.delay(after: 2), MarfaSync.delay(after: 3)])
    }

    @Test func aStreamThatToldAChangeStartsTheWaitOver() async {
        let streams = Streams([finished(stopped), finished(stopped), finished(saved, stopped), finished(stopped)])
        let task = MarfaFollow.start(
            streams.next(), next: { streams.next() }, wait: { await streams.wait($0) }, tell: { streams.tell($0) })
        await settle { streams.waits.count >= 4 }
        task.cancel()

        #expect(Array(streams.waits.prefix(4)) == [
            MarfaSync.delay(after: 1), MarfaSync.delay(after: 2), MarfaSync.delay(after: 1), MarfaSync.delay(after: 2)
        ])
    }

    @Test func aStreamLeftOpenAfterStoppedIsNotReplaced() async {
        // `.stopped` is told on a stream that stays open as well; only a stream that finishes is replaced.
        let open = AsyncStream<Change> { continuation in
            continuation.yield(stopped)
            continuation.yield(saved)
        }
        let streams = Streams([])
        let task = MarfaFollow.start(open, next: { streams.next() }, wait: { await streams.wait($0) }, tell: { streams.tell($0) })
        await settle { streams.heard.count >= 2 }
        task.cancel()

        #expect(streams.heard == [stopped, saved])
        #expect(streams.taken == 0, "an open stream is not replaced")
    }

    @Test func theEngineClosingEndsTheFollowWithoutAskingAgain() async {
        let streams = Streams([finished(saved)])
        let ended = Mutex(false)
        let task = MarfaFollow.start(
            streams.next(), next: { streams.next() }, wait: { await streams.wait($0) },
            tell: { event in
                if case .change = event { ended.withLock { $0 = true }; return false }
                return streams.tell(event)
            })
        await task.value

        #expect(ended.withLock { $0 })
        #expect(streams.taken == 1, "a refused change ends the follow before another stream is asked for")
    }

    @Test func cancellingTheFollowStopsItWaiting() async {
        let streams = Streams([finished(stopped)])
        let task = MarfaFollow.start(
            streams.next(), next: { streams.next() }, wait: { _ in try? await Task.sleep(for: .seconds(60)) },
            tell: { streams.tell($0) })
        await settle { streams.heard.count >= 1 }
        task.cancel()
        await task.value

        #expect(streams.taken == 1, "no stream is asked for once the follow is cancelled")
    }
}
