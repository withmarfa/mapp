import Foundation
import Marfa
import Synchronization

/// What the server answered a write to this app's settings item.
nonisolated enum PreferenceAnswer: Equatable, Sendable {
    /// The item took the write (accepted, or merged over changes made since).
    case taken
    /// The server kept another Mac's value of the field and wrote this one to a conflicted copy.
    case lost
    /// Refused, blocked or dead: the write will not reach the item.
    case notTaken

    init?(_ verdict: Marfa.Verdict?) {
        switch verdict {
        case nil: return nil
        case .accepted, .merged: self = .taken
        case .conflicted: self = .lost
        case .refused, .blocked, .dead: self = .notTaken
        }
    }
}

/// The answers to writes to hidden items, which the engine takes with every other answer (`Queue.takeAnswered`) and
/// leaves here, one set for each opened copy, for `PreferencesSync` to take. A conflicted copy can reach the copy after
/// the item's new value does, so the sync judges a field write by its answer rather than by what arrives first.
nonisolated final class PreferenceAnswers: Sendable {
    /// Names this opened copy: a write queued under another was answered where no sync could take it.
    let run = UUID().uuidString
    private let state = Mutex<(answers: [String: PreferenceAnswer], listeners: [UUID: AsyncStream<Void>.Continuation])>(([:], [:]))

    /// Keeps the answer of each write that has one, and tells every listener.
    func receive(_ writes: [Marfa.QueuedWrite]) {
        let answered = writes.compactMap { write in PreferenceAnswer(write.verdict).map { (write.id, $0) } }
        guard !answered.isEmpty else { return }
        let listeners = state.withLock { state in
            for (id, answer) in answered { state.answers[id] = answer }
            return Array(state.listeners.values)
        }
        for listener in listeners { listener.yield() }
    }

    /// The answers kept since the last take, by write.
    func take() -> [String: PreferenceAnswer] {
        state.withLock { state in
            defer { state.answers = [:] }
            return state.answers
        }
    }

    /// Yields each time answers arrive.
    func arrivals() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { $0.listeners[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.listeners.removeValue(forKey: id) } }
        return stream
    }
}
