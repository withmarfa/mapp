/// The app's writes the engine has queued, each of which the package may queue as several writes, until every one
/// of those has a final answer. The app's write is answered once every queued write it made has an answer, with the
/// weightiest among them: a refusal or a conflict over a write still blocked or dead, which is over a merge, and a
/// merge over an acceptance. Of answers that weigh the same, the one to the write answered first is given. A blocked
/// or dead write is sent again once released, so its later answer is given too.
nonisolated struct MarfaWriteRecord {
    nonisolated struct Answer: Equatable {
        let id: WriteID
        let outcome: WriteOutcome
        /// What the answers say the item holds of each property, an answer to a write first answered later over one to
        /// a write first answered earlier; nil where none says.
        let holding: [String: PropertyValue]?
    }

    private struct Answered {
        let queued: String
        var outcome: WriteOutcome
        var holding: [String: PropertyValue]?
    }

    /// The app's write for each queued write it made, until that write has a final answer.
    private var submitted: [String: WriteID] = [:]
    /// The queued writes of each app's write with no answer yet.
    private var unanswered: [WriteID: Set<String>] = [:]
    /// The latest answer to each queued write of each app's write, in the order the writes were first answered.
    private var answers: [WriteID: [Answered]] = [:]

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
    mutating func answer(_ queued: String, _ outcome: WriteOutcome, holding: [String: PropertyValue]? = nil) -> Answer? {
        guard let id = submitted[queued] else { return nil }
        if Self.isFinal(outcome) { submitted[queued] = nil }
        var answered = answers[id] ?? []
        if let at = answered.firstIndex(where: { $0.queued == queued }) {
            answered[at].outcome = outcome
            answered[at].holding = holding
        } else {
            answered.append(Answered(queued: queued, outcome: outcome, holding: holding))
        }
        answers[id] = answered
        unanswered[id]?.remove(queued)
        guard unanswered[id]?.isEmpty ?? true else { return nil }
        if !answered.contains(where: { submitted[$0.queued] != nil }) {
            unanswered[id] = nil
            answers[id] = nil
        }
        var weightiest = answered[0].outcome
        for later in answered.dropFirst() where Self.weight(later.outcome) > Self.weight(weightiest) { weightiest = later.outcome }
        let held = answered.compactMap(\.holding)
        let holding = held.isEmpty ? nil : held.reduce(into: [:]) { all, one in all.merge(one) { _, later in later } }
        return Answer(id: id, outcome: weightiest, holding: holding)
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
