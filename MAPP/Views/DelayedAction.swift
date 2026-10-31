import Foundation

/// Runs the latest of a run of requests once they stop for `delay`, as saving a scroll position does.
@MainActor
final class DelayedAction {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration = .milliseconds(500), _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { action() }
        }
    }
}
