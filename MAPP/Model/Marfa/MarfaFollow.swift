import Foundation
import Marfa

/// Keeps the engine hearing its copy. The core finishes a stream it ended on a fault, after telling it `.stopped`,
/// and one it refused a place in its watch; a finished stream hears nothing more, so a new one is asked for. A
/// failed follow of the server is not that: its stream stays open and `MarfaSync` restarts the follow.
nonisolated enum MarfaFollow {
    /// Tells the engine each change of `first`, and of each stream asked for once the one before it finished. The
    /// copy is read again as each new stream is taken, since what changed between two streams was heard by neither.
    /// Ends when the engine takes no more events or the task is cancelled.
    static func start(
        _ first: AsyncStream<Marfa.Change>, next: @escaping @Sendable () -> AsyncStream<Marfa.Change>,
        wait: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        tell: @escaping @Sendable (MarfaEngine.Event) -> Bool
    ) -> Task<Void, Never> {
        Task {
            var stream = first
            // Streams in a row that ended having told nothing but `.stopped`, which are asked for at a falling rate.
            var ended = 0
            while !Task.isCancelled {
                var heard = false
                for await change in stream {
                    if case .stopped = change.origin {} else { heard = true }
                    if !tell(.change(change)) { return }
                }
                guard !Task.isCancelled else { return }
                ended = heard ? 1 : ended + 1
                await wait(MarfaSync.delay(after: ended))
                guard !Task.isCancelled else { return }
                stream = next()
                if !tell(.resumed) { return }
            }
        }
    }
}
