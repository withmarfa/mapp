import Foundation
import Marfa

/// Keeps the engine hearing its copy. The core ends a stream it ended on a fault, or refused a place in its watch,
/// by telling it `.stopped` and then finishing it; a finished stream hears nothing more, so a new one is asked for.
/// A stream that finishes any other way is the copy closing, which `changes()` answers with a stream already
/// finished, so the follow ends there rather than ask again for ever. A failed follow of the server is neither: its
/// stream stays open and `MarfaSync` restarts the follow.
nonisolated enum MarfaFollow {
    /// Tells the engine each change of `first`, and of each stream asked for once the one before it ended on a
    /// fault. The copy is read again as each new stream is taken, since what changed between two streams was heard
    /// by neither. Ends when a stream finishes without `.stopped`, the engine takes no more events or the task is
    /// cancelled.
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
                var told = false
                var stopped = false
                for await change in stream {
                    if case .stopped = change.origin { stopped = true } else { told = true; stopped = false }
                    if !tell(.change(change)) { return }
                }
                guard !Task.isCancelled, stopped else { return }
                ended = told ? 1 : ended + 1
                await wait(MarfaSync.delay(after: ended))
                guard !Task.isCancelled else { return }
                stream = next()
                if !tell(.resumed) { return }
            }
        }
    }
}
