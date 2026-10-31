import Foundation
import Observation
import Testing

/// How long a test waits for something before it fails. A passing test never waits this long, since a wait returns as
/// soon as its condition holds. The limit is long because a hosted runner is slow and runs many suites at once, and
/// the first editor page of a test process starts WebKit cold, which has taken 27 seconds there.
nonisolated let waitLimit: Duration = .seconds(60)

/// The time limit of a suite whose tests await something that may never arrive, such as a WebKit call, an answer from
/// another process or a task. A hang then fails the test that hangs, by name, and the run goes on, where it would
/// otherwise hold the whole job to its own limit. It is above `waitLimit`, so that a wait that gives up reports its own
/// expectation first, and well above the slowest test on a hosted runner. A test sets no limit of its own. Two kinds
/// of suite do not carry it: a `Live` suite, whose tests each set a limit that allows for a real server, and
/// `NavigationCostTests`, which only the Measure plan runs and a person reads.
extension Trait where Self == TimeLimitTrait {
    nonisolated static var hangLimit: Self { .timeLimit(.minutes(2)) }
}

/// Waits until `condition` holds, and answers whether it did before `limit` passed.
///
/// It checks again as soon as observable state the condition read changes, such as a library's `isLoaded`, so it
/// returns on the change itself. It also checks every 100 ms, for state that is not observable, such as a fake's log
/// or a window's visibility.
func eventually(
    within limit: Duration = waitLimit,
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async -> Bool {
    let end = ContinuousClock.now + limit
    while true {
        let (changes, change) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let holds = withObservationTracking(condition) { change.yield() }
        if holds { return true }
        if ContinuousClock.now >= end { return false }
        let tick = Task {
            try? await Task.sleep(for: .milliseconds(100))
            change.yield()
        }
        for await _ in changes { break }
        tick.cancel()
    }
}

/// Waits until a condition that must await, such as a question to the editor's page or to an actor, holds, and
/// answers whether it did before `limit` passed. It asks every 50 ms.
func eventuallyAsking(
    within limit: Duration = waitLimit,
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async throws -> Bool
) async throws -> Bool {
    let end = ContinuousClock.now + limit
    while true {
        if try await condition() { return true }
        if ContinuousClock.now >= end { return false }
        try await Task.sleep(for: .milliseconds(50))
    }
}
