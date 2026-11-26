import Foundation

/// A read raced against a timer, for a question that must not wait on the server: a started core or server call
/// can't be cancelled, so the caller goes on with `otherwise` once the deadline passes and a late answer is ignored.
@MainActor
enum FirstAnswer {
    static func within<Answer: Sendable>(
        _ deadline: Duration, otherwise fallback: Answer, of read: @escaping @MainActor () async -> Answer
    ) async -> Answer {
        let race = Race<Answer>()
        return await withCheckedContinuation { continuation in
            race.start(continuation, deadline: deadline, fallback: fallback, read: read)
        }
    }

    /// The first of the read and the timer to finish resumes the caller; the other is ignored.
    private final class Race<Answer: Sendable> {
        private var continuation: CheckedContinuation<Answer, Never>?
        private var timer: Task<Void, Never>?

        func start(
            _ continuation: CheckedContinuation<Answer, Never>, deadline: Duration, fallback: Answer,
            read: @escaping @MainActor () async -> Answer
        ) {
            self.continuation = continuation
            timer = Task {
                try? await Task.sleep(for: deadline)
                finish(fallback)
            }
            Task { finish(await read()) }
        }

        private func finish(_ answer: Answer) {
            continuation?.resume(returning: answer)
            continuation = nil
            timer?.cancel()
        }
    }
}
