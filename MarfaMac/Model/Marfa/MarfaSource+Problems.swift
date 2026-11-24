import Foundation
import Marfa

nonisolated extension MarfaSource {
    var syncReport: SyncReport { hub.report.value }

    func syncReports() -> AsyncStream<SyncReport> {
        hub.report.values()
    }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        guard let entry = hub.report.value.problems.first(where: { $0.id == problem }), entry.actions.contains(action)
        else { return false }
        switch (problem, action) {
        case (.write(let id), .discard):
            return try await ask { .discard(id, $0) }
        case (.write(let id), .tryAgain):
            return try await ask { .release(id, $0) }
        case (.write(let id), .withdraw):
            // It reads the server, so it runs beside the engine rather than holding up the writes behind it; the
            // copy announces the withdrawal, which the engine reads again. The server never answers a write taken
            // out, so the engine answers each as not made.
            do {
                // An empty answer means nothing was taken, as when the write was no longer withdrawable.
                let withdrawn = try await MarfaEngine.asking { try await copy.queue.withdraw(id) }
                guard !withdrawn.isEmpty else { return false }
                events.yield(.withdrawn(withdrawn))
                return true
            } catch let error as MarfaError {
                throw SourceFailure(kind: .failed, message: Words.message(for: error))
            }
        case (.conflictedCopy(let copy), .discard):
            submit(.transition(copy, .trashed), as: WriteID())
            return true
        case (.conflictedCopy(let copy), .keep):
            submit(.tag(copy, MarfaProblems.conflictedCopyTag, on: false), as: WriteID())
            return true
        default:
            return false
        }
    }

    private func ask(
        _ event: (CheckedContinuation<Result<Bool, SourceFailure>, Never>) -> MarfaEngine.Event
    ) async throws -> Bool {
        let result = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(event(continuation)) { continuation.resume(returning: .success(false)) }
        }
        return try result.get()
    }
}
