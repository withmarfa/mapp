import Foundation
import Testing
@testable import MarfaMac

/// How many pictures are made at once, and what a card that leaves the screen leaves behind.
@Suite(.hangLimit) struct PreviewGateTests {
    private actor Tally {
        var active = 0
        var most = 0
        var done = 0
        func enter() { active += 1; most = max(most, active) }
        func leave() { active -= 1; done += 1 }
    }

    @Test func noMoreThanTheLimitRunAtOnceAndAllFinish() async throws {
        let gate = PreviewGate(limit: 3)
        let tally = Tally()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await gate.run {
                        await tally.enter()
                        // Stands for a picture's work, long enough for the others to queue behind it.
                        try? await Task.sleep(for: .milliseconds(20))
                        await tally.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await tally.most == 3)
        #expect(await tally.done == 12)
    }

    @Test func aCancelledWaiterNeverRunsAndHoldsNoPlace() async throws {
        let gate = PreviewGate(limit: 1)
        let tally = Tally()
        // The holder's work, which keeps the gate's one place while the waiter queues.
        let holder = Task { try await gate.run { try? await Task.sleep(for: .milliseconds(200)) } }
        // Lets the holder take the place first.
        try await Task.sleep(for: .milliseconds(30))
        let waiter = Task { try await gate.run { await tally.enter(); await tally.leave() } }
        // Lets the waiter queue behind the holder before it is cancelled.
        try await Task.sleep(for: .milliseconds(30))
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        _ = try await holder.value
        #expect(await tally.done == 0, "the cancelled card's work never started")
        // The place is free again, so the next card is not kept waiting for the one that left.
        try await gate.run { await tally.enter(); await tally.leave() }
        #expect(await tally.done == 1)
    }

    @Test func aTaskCancelledBeforeItAsksNeverRuns() async {
        let gate = PreviewGate(limit: 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await gate.run { 1 }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
