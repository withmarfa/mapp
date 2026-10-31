import Foundation
import Marfa

extension MarfaEngine {
    /// The way into the engine's stream. It counts each event told, and each of the person's writes among them, so
    /// `EngineActivity` can say how many wait and a quit can wait for the writes alone; it is otherwise the stream's
    /// own continuation.
    nonisolated struct Events: Sendable {
        private let continuation: AsyncStream<Event>.Continuation
        let activity: EngineActivity

        init(_ continuation: AsyncStream<Event>.Continuation, activity: EngineActivity) {
            self.continuation = continuation
            self.activity = activity
        }

        @discardableResult
        func yield(_ event: Event) -> AsyncStream<Event>.Continuation.YieldResult {
            let write = event.isWrite
            activity.tell(write: write)
            let result = continuation.yield(event)
            if case .terminated = result { activity.untell(write: write) }
            return result
        }

        func finish() {
            continuation.finish()
        }
    }
}

extension MarfaEngine.Event {
    /// A write of the person's, which `ItemSource.queueSubmitted` waits for.
    nonisolated var isWrite: Bool {
        switch self {
        case .write, .undo, .attach, .addFile: true
        default: false
        }
    }

    /// What the event is, for a signpost's name and the log: never what it carries.
    nonisolated var kind: StaticString {
        switch self {
        case .paint: "paint"
        case .fillProgress: "fillProgress"
        case .write: "write"
        case .undo: "undo"
        case .holdExpired: "holdExpired"
        case .heard: "heard"
        case .drained: "drained"
        case .failed: "failed"
        case .flush: "flush"
        case .close: "close"
        case .discard: "discard"
        case .release: "release"
        case .unsent: "unsent"
        case .closeAgreeing: "closeAgreeing"
        case .binned: "binned"
        case .answer: "answer"
        case .attach: "attach"
        case .addFile: "addFile"
        case .attached: "attached"
        case .addedFile: "addedFile"
        }
    }
}
