import Foundation
import Marfa
import Synchronization

/// Keeps the engine hearing its copy. The core ends a stream it ended on a fault, or refused a place in its watch,
/// by telling it `.stopped` and then finishing it; a finished stream hears nothing more, so a new one is asked for.
/// A stream that finishes any other way is the copy closing, which `changes()` answers with a stream already
/// finished, so the follow ends there rather than ask again for ever. A failed follow of the server is neither: its
/// stream stays open and `MarfaSync` restarts the follow.
nonisolated enum MarfaFollow {
    /// What the follow heard and the engine has not yet taken, in order. A server that sends thousands of changes
    /// would otherwise queue thousands of events, each a read of the copy; the engine takes everything heard in
    /// one step instead (`MarfaEngine.takeHeard`), so it reads each row once however often it changed meanwhile.
    nonisolated final class Heard: Sendable {
        nonisolated enum Entry: Sendable {
            case change(Marfa.Change)
            /// The copy's changes have a new stream after the last one ended, so what changed between them was
            /// not heard.
            case resumed
        }

        private let state = Mutex((entries: [Entry](), told: false))

        /// Keeps `entry`, and tells the engine `.heard` unless a `.heard` it has not taken is already on its way.
        /// False once the engine takes no more events.
        func add(_ entry: Entry, tell: (MarfaEngine.Event) -> Bool) -> Bool {
            let telling = state.withLock { state in
                state.entries.append(entry)
                defer { state.told = true }
                return !state.told
            }
            return telling ? tell(.heard) : true
        }

        /// Everything heard since the last take, oldest first.
        func take() -> [Entry] {
            state.withLock { state in
                defer { state = ([], false) }
                return state.entries
            }
        }
    }

    /// Tells the engine each change of `first`, and of each stream asked for once the one before it ended on a
    /// fault. The copy is read again as each new stream is taken, since what changed between two streams was heard
    /// by neither. Ends when a stream finishes without `.stopped`, the engine takes no more events or the task is
    /// cancelled.
    static func start(
        _ first: AsyncStream<Marfa.Change>, next: @escaping @Sendable () -> AsyncStream<Marfa.Change>,
        wait: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        into heard: Heard, tell: @escaping @Sendable (MarfaEngine.Event) -> Bool
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
                    if !heard.add(.change(change), tell: tell) { return }
                }
                guard !Task.isCancelled, stopped else { return }
                ended = told ? 1 : ended + 1
                await wait(MarfaSync.delay(after: ended))
                guard !Task.isCancelled else { return }
                stream = next()
                if !heard.add(.resumed, tell: tell) { return }
            }
        }
    }
}
