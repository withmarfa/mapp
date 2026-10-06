import Foundation

/// What a source has yet to send, and each write that needs the person. A source that sends nothing, such as a
/// folder, reports nothing waiting.
nonisolated protocol SyncReporting: AnyObject, Sendable {
    var syncReport: SyncReport { get }
    /// Starts with the report as it stands, then each one that differs.
    func syncReports() -> AsyncStream<SyncReport>
    /// False where the action is not offered for the problem, or the queue would not take it, such as a write
    /// the server refused, which is never sent again.
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool
}

nonisolated struct SyncReport: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case current
        /// The copy is being pulled again from the start. The writes waiting are kept and go once it is done.
        case catchingUp
    }

    var phase = Phase.current
    /// Writes not answered yet, problems aside.
    var waiting = 0
    var oldestWaiting: Date?
    /// Oldest first.
    var problems: [SyncProblemEntry] = []
    /// False until the source has read what waits, when nothing can be said of it: a copy that cannot be read
    /// may still hold writes.
    var queueRead = false

    /// Writes this device holds that the server has not taken, which removing the copy would lose. A conflicted
    /// copy is on the server already.
    var changesNotSent: Int {
        waiting + problems.count { if case .conflicted = $0.kind { false } else { true } }
    }
}

/// What can be done about a problem besides copying the person's content, which is always possible.
nonisolated enum SyncAction: Hashable, Sendable, CaseIterable {
    /// Takes a refused write out of the queue; for a conflicted copy, moves the copy to the bin.
    case discard
    /// Sends a stopped write again under a fresh idempotency key.
    case tryAgain
    /// Takes a write the server will never take out of the queue, and puts the item back as the server holds it.
    /// It reads the server first, so it needs the server.
    case withdraw
    /// Keeps a conflicted copy as an item of its own.
    case keep
}

nonisolated struct SyncProblemEntry: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        /// A write the queue holds, or held until it was answered, by the queue's id.
        case write(String)
        /// A conflicted copy the server made, which outlives the write that caused it.
        case conflictedCopy(ItemID)
    }

    enum Kind: Hashable, Sendable {
        /// The server, or the queue for a write it waited on, refused it for good.
        case refused
        case blocked(BlockedReason)
        /// The server kept its own values and put the person's on `sibling`. `original` is the item it was made
        /// from, where it is known.
        case conflicted(sibling: ItemID, original: ItemID?)
        /// Failed the same way until the retry ceiling.
        case dead
    }

    /// The change the person made, so the app can name what did not land.
    enum Change: Hashable, Sendable {
        case create, edit, delete, restore, transition, tag, untag, link, unlink, other
    }

    let id: ID
    var itemID: ItemID?
    var kind: Kind
    var change: Change
    /// The refusal's parts, or the reason the write stopped. Nil for a conflicted copy.
    var reason: SyncProblem?
    /// What the person wrote, kept in the write or, for a conflicted copy, on the copy.
    var content: SyncContent
    var actions: [SyncAction]
    var date: Date?
    /// Writes refused only because this one was, which go when it is discarded.
    var dependents: [String] = []

    var copyText: String { content.plainText }
}

/// A write's content as plain text values, in the catalogue's order.
nonisolated struct SyncContent: Hashable, Sendable {
    struct Line: Hashable, Sendable {
        let label: String
        let value: String
    }

    var title: String?
    var body: String?
    /// Every other value written, labeled as the catalogue names its field.
    var properties: [Line] = []
    var tags: [String] = []

    /// Title, body, then each value on a line of its own, so it reads back as the person wrote it.
    var plainText: String {
        var sections: [String] = []
        if let title, !title.isEmpty { sections.append(title) }
        if let body, !body.isEmpty { sections.append(body) }
        var lines = properties.map { "\($0.label): \($0.value)" }
        if !tags.isEmpty { lines.append(String(localized: "Tags: \(tags.joined(separator: ", "))")) }
        if !lines.isEmpty { sections.append(lines.joined(separator: "\n")) }
        return sections.joined(separator: "\n\n")
    }
}
