import Foundation

/// Why a write was refused or stopped, read into the parts the app shows.
nonisolated struct SyncProblem: Hashable, Sendable {
    /// A permission the sign-in lacks, which the person restores on the server rather than in the app.
    struct Grant: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case type, edgeType, `extension` }
        enum Level: Hashable, Sendable { case read, write }

        var kind: Kind
        /// The type, edge type or extension namespace.
        var name: String
        var level: Level
    }

    /// The server's code verbatim, the contract's name for a blocked reason, or a source's own code for a write
    /// it could not make.
    var code: String
    var message: String?
    /// Each property refused, with the reason given.
    var fields: [String: String] = [:]
    /// The item is in the bin and can be restored.
    var isTrashed = false
    var grant: Grant?
    /// Refused before it was queued, so no queue holds what it carried and the person's content is theirs to keep.
    var notQueued = false
}

/// The contract's closed set, less `awaiting_dependency`, which is never a verdict's reason.
nonisolated enum BlockedReason: String, Hashable, Sendable, CaseIterable {
    case credentialRefused = "credential_refused"
    case keySpent = "key_spent"
    case ancestorUnavailable = "ancestor_unavailable"
    case conflictUnresolved = "conflict_unresolved"
    case failingAlone = "failing_alone"
}

/// One of the contract's six verdicts on a write. A files source answers `accepted`, or `refused` when the disk
/// write fails.
nonisolated enum WriteOutcome: Hashable, Sendable {
    case accepted
    /// Applied over changes made since, field by field.
    case merged(fields: [String])
    /// The server kept its own value and wrote the losing one to `sibling`.
    case conflicted(sibling: ItemID, fields: [String])
    /// Terminal: the write is not sent again.
    case refused(SyncProblem)
    /// Stopped until something outside the queue changes, then sent again when released.
    case blocked(BlockedReason, SyncProblem?)
    /// Failed the same way until the retry ceiling; sent again only when released.
    case dead

    /// What the answered write leaves on its item, before other writes still waiting are counted.
    var syncState: SyncState {
        switch self {
        case .accepted, .merged: .settled
        case .conflicted(let sibling, let fields): .conflicted(sibling: sibling, fields: fields)
        case .refused(let problem): .refused(problem)
        case .blocked(let reason, let problem):
            .blocked(SyncProblem(
                code: reason.rawValue, message: problem?.message, fields: problem?.fields ?? [:],
                isTrashed: problem?.isTrashed ?? false, grant: problem?.grant))
        // A dead write waits for a release as a blocked one does, so the person is offered the same retry.
        case .dead: .blocked(SyncProblem(code: "dead"))
        }
    }
}

nonisolated enum SyncState: Hashable, Sendable {
    case settled
    case waiting(writes: Int)
    case refused(SyncProblem)
    /// The sibling is nil where a source reports the conflict without having read the copy yet.
    case conflicted(sibling: ItemID?, fields: [String])
    case blocked(SyncProblem)
}
