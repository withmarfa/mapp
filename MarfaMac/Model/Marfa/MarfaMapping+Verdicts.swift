import Foundation
import Marfa

nonisolated extension MarfaMapping {
    /// `afterRefusal`: a write the refused one waited on was refused or died, which only the queue can tell
    /// (`MarfaProblems.waitsOnStopped`).
    static func outcome(_ verdict: Marfa.Verdict, afterRefusal: Bool = false) -> WriteOutcome {
        switch verdict {
        case .accepted: .accepted
        case .merged(let fields): .merged(fields: fields)
        case .conflicted(let sibling?, let fields, _): .conflicted(sibling: ItemID(sibling), fields: fields)
        // An item conflict always names the copy it wrote; one that names none is a table row's, which the app never writes.
        case .conflicted(nil, let fields, _): .merged(fields: fields)
        case .refused(let refusal): .refused(problem(refusal, afterRefusal: afterRefusal))
        case .blocked(let reason, let refusal): .blocked(blockedReason(reason), refusal.map { problem($0) })
        case .dead: .dead
        }
    }

    /// What the item holds of every property after an item edit, read from the server's whole answer to it, which
    /// alone says what a merge, a conflict or a rebased edit left. Nil where the answer carries no item.
    static func holding(answeredBy answer: JSONValue?) -> [String: PropertyValue]? {
        guard let properties = answer?.object?["item"]?.object?["properties"]?.object else { return nil }
        return Dictionary(properties.map { ($0.key, value($0.value)) }, uniquingKeysWith: { first, _ in first })
    }

    /// A refusal with no code is either the server's answer with none, stored as a one-word reason, or the copy's
    /// own, never sent, with an English sentence as its reason. The copy's is told in the app's words: too large, or
    /// after a write it waited on (`afterRefusal`, which the caller reads from the queue), or otherwise as not sent.
    static func problem(_ refusal: Marfa.Refusal, afterRefusal: Bool = false) -> SyncProblem {
        let sentence = refusal.reason.contains(where: \.isWhitespace)
        let unsent: SyncProblem.Unsent? =
            if let limit = refusal.requestLimit { .tooLarge(size: limit.size, limit: limit.limit) }
            else if refusal.code != nil { nil }
            else if afterRefusal { .afterRefusal }
            else if sentence { .notSent(reason: refusal.reason) }
            else { nil }
        return SyncProblem(
            code: refusal.code ?? unsent.map(unsentCode) ?? refusal.reason,
            message: unsent.map(Words.unsent) ?? refusal.message, unsent: unsent,
            fields: Dictionary(refusal.fields.map { ($0.field, $0.message) }, uniquingKeysWith: { first, _ in first }),
            isTrashed: refusal.trashed, grant: refusal.grant.map(grant))
    }

    private static func unsentCode(_ unsent: SyncProblem.Unsent) -> String {
        switch unsent {
        case .tooLarge: "over_request_limit"
        case .afterRefusal: "refused_with_dependency"
        case .notSent: "refused_unsent"
        }
    }

    private static func grant(_ grant: MissingGrant) -> SyncProblem.Grant {
        let kind: SyncProblem.Grant.Kind =
            switch grant.kind {
            case .type: .type
            case .edgeType: .edgeType
            case .extension: .extension
            }
        return SyncProblem.Grant(kind: kind, name: grant.name, level: grant.level == .read ? .read : .write)
    }

    static func blockedReason(_ reason: Marfa.BlockedReason) -> BlockedReason {
        switch reason {
        case .credentialRefused: .credentialRefused
        case .keySpent: .keySpent
        case .ancestorUnavailable: .ancestorUnavailable
        case .conflictUnresolved: .conflictUnresolved
        case .failingAlone: .failingAlone
        case .instanceChanged: .instanceChanged
        case .recordUnread: .recordUnread
        case .serverRestored: .serverRestored
        }
    }

    /// Each item the queue holds a write for, or that a drain answered `refused` or `conflicted` (which the queue
    /// forgets unless the write carried content), with what most needs the person: a stopped write, then a refused
    /// one, then a conflict, then the count still waiting, and whether a write held for its size is among them. An
    /// item missing from the answer is settled.
    static func syncStates(queue: [Marfa.QueuedWrite], remembered: [ItemID: SyncState] = [:]) -> [ItemID: SyncState] {
        var waiting: [ItemID: Int] = [:]
        var answered: [ItemID: SyncState] = remembered
        var oversized: Set<ItemID> = []
        for write in queue {
            guard let itemID = write.itemId else { continue }
            let id = ItemID(itemID)
            guard let verdict = write.verdict else {
                waiting[id, default: 0] += 1
                continue
            }
            let state = outcome(verdict).syncState
            switch state {
            case .refused(let problem), .blocked(let problem): if problem.isTooLarge { oversized.insert(id) }
            default: break
            }
            if state != .settled, rank(state) > rank(answered[id]) { answered[id] = state }
        }
        // A write held for its size keeps the person's latest text in Settings, which a block or another refusal that
        // outranks it must not hide.
        for id in oversized {
            switch answered[id] {
            case .refused(var problem)?: problem.alsoHoldsOversizedText = true; answered[id] = .refused(problem)
            case .blocked(var problem)?: problem.alsoHoldsOversizedText = true; answered[id] = .blocked(problem)
            default: break
            }
        }
        for (id, count) in waiting where answered[id] == nil {
            answered[id] = .waiting(writes: count)
        }
        return answered
    }

    /// How much a state needs the person: a conflict outranks writes that merely wait, and a refusal or a block
    /// outranks a conflict.
    static func rank(_ state: SyncState?) -> Int {
        switch state {
        case nil, .settled: 0
        case .waiting: 1
        case .conflicted: 2
        case .refused: 3
        case .blocked: 4
        }
    }
}
