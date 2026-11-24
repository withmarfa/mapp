/// The app's writes the engine has queued, each of which the package may queue as several writes, until every one
/// of those has a final answer. The app's write is answered once every queued write it made has an answer, with the
/// weightiest among them: a refusal or a conflict over a write still blocked or dead, which is over a merge, and a
/// merge over an acceptance. A blocked or dead write is sent again once released, so its later answer is given too.
nonisolated struct MarfaWriteRecord {
    /// The app's write for each queued write it made, until that write has a final answer.
    private var submitted: [String: WriteID] = [:]
    /// The queued writes of each app's write with no answer yet.
    private var unanswered: [WriteID: Set<String>] = [:]
    /// The latest answer to each queued write of each app's write.
    private var outcomes: [WriteID: [String: WriteOutcome]] = [:]

    /// Records that `id` was queued as `queued`, which is never empty: a write that queued nothing is answered at once.
    mutating func record(_ id: WriteID, queued: some Sequence<String>) {
        let queued = Set(queued)
        precondition(!queued.isEmpty, "a write that queued nothing has no answer to wait for")
        unanswered[id] = queued
        for written in queued { submitted[written] = id }
    }

    /// Takes the answer to one queued write, and gives the app's write and its answer once every queued write it
    /// made has one. A queued write the record does not hold, such as another device's or one with a final answer
    /// already, gives nothing.
    mutating func answer(_ queued: String, _ outcome: WriteOutcome) -> (id: WriteID, outcome: WriteOutcome)? {
        guard let id = submitted[queued] else { return nil }
        if Self.isFinal(outcome) { submitted[queued] = nil }
        outcomes[id, default: [:]][queued] = outcome
        unanswered[id]?.remove(queued)
        guard unanswered[id]?.isEmpty ?? true, let answers = outcomes[id] else { return nil }
        if !answers.keys.contains(where: { submitted[$0] != nil }) {
            unanswered[id] = nil
            outcomes[id] = nil
        }
        return answers.values.max { Self.weight($0) < Self.weight($1) }.map { (id, $0) }
    }

    private static func isFinal(_ outcome: WriteOutcome) -> Bool {
        switch outcome {
        case .blocked, .dead: false
        case .accepted, .merged, .conflicted, .refused: true
        }
    }

    private static func weight(_ outcome: WriteOutcome) -> Int {
        switch outcome {
        case .accepted: 0
        case .merged: 1
        case .blocked, .dead: 2
        case .refused, .conflicted: 3
        }
    }
}
