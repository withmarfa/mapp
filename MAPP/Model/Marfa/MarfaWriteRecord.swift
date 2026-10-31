/// The app's writes the engine has queued, each of which the package may queue as several writes, until every one
/// of those is answered. The app's write is then answered once, with the weightiest answer among them: a refusal
/// or a conflict over a merge, and a merge over an acceptance.
nonisolated struct MarfaWriteRecord {
    /// The app's write for each queued write it made.
    private var submitted: [String: WriteID] = [:]
    /// The queued writes of each app's write not yet answered.
    private var outstanding: [WriteID: Set<String>] = [:]
    /// The weightiest answer each app's write has had so far.
    private var outcomes: [WriteID: WriteOutcome] = [:]

    /// Records that `id` was queued as `queued`, which is never empty: a write that queued nothing is answered at once.
    mutating func record(_ id: WriteID, queued: some Sequence<String>) {
        let queued = Set(queued)
        precondition(!queued.isEmpty, "a write that queued nothing has no answer to wait for")
        outstanding[id] = queued
        for written in queued { submitted[written] = id }
    }

    /// Takes the answer to one queued write, and gives the app's write and its answer once every queued write it
    /// made is answered. A queued write the record does not hold, such as another device's or one already answered,
    /// gives nothing.
    mutating func answer(_ queued: String, _ outcome: WriteOutcome) -> (id: WriteID, outcome: WriteOutcome)? {
        guard let id = submitted.removeValue(forKey: queued) else { return nil }
        if Self.weight(outcome) > outcomes[id].map(Self.weight) ?? -1 { outcomes[id] = outcome }
        outstanding[id]?.remove(queued)
        guard outstanding[id]?.isEmpty ?? true else { return nil }
        outstanding[id] = nil
        return outcomes.removeValue(forKey: id).map { (id, $0) }
    }

    private static func weight(_ outcome: WriteOutcome) -> Int {
        switch outcome {
        case .accepted: 0
        case .merged: 1
        default: 2
        }
    }
}
