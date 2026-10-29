import Foundation
import Marfa

extension MarfaEngine {
    /// The way into the engine's stream. It counts each event told, so `EngineActivity` can say how many wait, and
    /// is otherwise the stream's own continuation.
    nonisolated struct Events: Sendable {
        private let continuation: AsyncStream<Event>.Continuation
        let activity: EngineActivity

        init(_ continuation: AsyncStream<Event>.Continuation, activity: EngineActivity) {
            self.continuation = continuation
            self.activity = activity
        }

        @discardableResult
        func yield(_ event: Event) -> AsyncStream<Event>.Continuation.YieldResult {
            activity.tell()
            let result = continuation.yield(event)
            if case .terminated = result { activity.untell() }
            return result
        }

        func finish() {
            continuation.finish()
        }
    }
}

extension MarfaEngine.Event {
    /// What the event is, for a signpost's name and the log: never what it carries.
    nonisolated var kind: StaticString {
        switch self {
        case .paint: "paint"
        case .fillProgress: "fillProgress"
        case .resumed: "resumed"
        case .write: "write"
        case .undo: "undo"
        case .holdExpired: "holdExpired"
        case .change(let change): change.origin.kind
        case .drained: "drained"
        case .failed: "failed"
        case .flush: "flush"
        case .queued: "queued"
        case .close: "close"
        case .discard: "discard"
        case .release: "release"
        case .unsent: "unsent"
        case .closeAgreeing: "closeAgreeing"
        case .binned: "binned"
        case .answer: "answer"
        case .attach: "attach"
        case .addFile: "addFile"
        }
    }
}

extension Marfa.Change.Origin {
    nonisolated var kind: StaticString {
        switch self {
        case .local: "change.local"
        case .server: "change.server"
        case .serverUnreachable: "change.serverUnreachable"
        case .serverReachable: "change.serverReachable"
        case .queueDrained: "change.queueDrained"
        case .queueNotDrained: "change.queueNotDrained"
        case .answered: "change.answered"
        case .saved: "change.saved"
        case .refreshed(let refresh): refresh.kind
        case .stopped: "change.stopped"
        }
    }
}

extension Marfa.Change.Refresh {
    nonisolated var kind: StaticString {
        switch self {
        case .hydrated: "change.refreshed.hydrated"
        case .unfinished: "change.refreshed.unfinished"
        case .caughtUp: "change.refreshed.caughtUp"
        case .drained: "change.refreshed.drained"
        case .withdrawn: "change.refreshed.withdrawn"
        case .forgotten: "change.refreshed.forgotten"
        case .pinned: "change.refreshed.pinned"
        case .unpinned: "change.refreshed.unpinned"
        case .purged: "change.refreshed.purged"
        case .folderWritten: "change.refreshed.folderWritten"
        case .viewWritten: "change.refreshed.viewWritten"
        case .catalog: "change.refreshed.catalog"
        }
    }
}
