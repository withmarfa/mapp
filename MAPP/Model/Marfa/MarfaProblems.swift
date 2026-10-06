import Foundation
import Marfa

/// Reads the queue, and the conflicted copies the copy holds, into what waits and what needs the person. Pure, so
/// the rules are tested on values made by hand.
nonisolated enum MarfaProblems {
    /// The server tags each conflicted copy it makes, and the tag stays until the person keeps or bins the copy.
    static let conflictedCopyTag = "conflicted-copy"
    /// Written from a conflicted copy to the item it was made from, so the original is known after a restart.
    static let derivedFromEdge = "derived-from"

    nonisolated struct ConflictedCopy: Hashable, Sendable {
        var row: Marfa.Item
        var original: ItemID?
    }

    /// `kept` holds refused writes the queue has since forgotten, because they carried no content; `types` the
    /// type of each item a write names, for the writes that do not name it themselves.
    static func report(
        queue: [QueuedWrite], kept: [QueuedWrite] = [], conflictedCopies: [ConflictedCopy] = [],
        catalogue: Catalogue, types: [String: TypeID] = [:]
    ) -> SyncReport {
        let queued = Set(queue.map(\.id))
        var waiting: [QueuedWrite] = []
        var stopped: [QueuedWrite] = []
        for write in queue + kept.filter({ !queued.contains($0.id) }) {
            switch write.verdict {
            case nil, .blocked(.awaitingDependency, _):
                waiting.append(write)
            // A refused key parks every write together; the connection says so once, and the writes still wait.
            case .blocked(.credentialRefused, let refusal) where refusal?.grant == nil:
                waiting.append(write)
            case .refused, .blocked, .dead:
                stopped.append(write)
            case .accepted, .merged, .conflicted:
                continue
            }
        }

        let roots = foldedRoots(stopped)
        var dependents: [String: [String]] = [:]
        for write in stopped {
            if let root = roots[write.id] { dependents[root, default: []].append(write.id) }
        }
        var problems = stopped.filter { roots[$0.id] == nil }.compactMap { write -> SyncProblemEntry? in
            let type = write.body["type"]?.string.map { TypeID($0) } ?? write.itemId.flatMap { types[$0] }
            var entry = entry(for: write, type: type, catalogue: catalogue)
            entry?.dependents = dependents[write.id] ?? []
            return entry
        }
        problems += conflictedCopies.map { entry(for: $0, catalogue: catalogue) }
        problems.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        return SyncReport(
            waiting: waiting.count, oldestWaiting: waiting.map { MarfaMapping.date($0.queuedAt) }.min(),
            problems: problems, queueRead: true)
    }

    /// A write the queue refused without sending, because a write it waits on was refused, died or is blocked,
    /// is shown with that write: discarding a refusal takes it too, and releasing a stopped write releases it.
    static func foldedRoots(_ stopped: [QueuedWrite]) -> [String: String] {
        let byID = Dictionary(stopped.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var roots: [String: String] = [:]
        for write in stopped {
            var current = write
            var seen: Set<String> = [write.id]
            var root: String?
            while isRefusedUnsent(current),
                let next = current.dependsOn.first(where: { byID[$0] != nil && !seen.contains($0) }),
                let ahead = byID[next]
            {
                seen.insert(next)
                root = next
                current = ahead
            }
            if let root { roots[write.id] = root }
        }
        return roots
    }

    /// The queue's own refusal carries only its reason; the server's carries its code.
    private static func isRefusedUnsent(_ write: QueuedWrite) -> Bool {
        if case .refused(let refusal) = write.verdict { refusal.code == nil } else { false }
    }

    static func entry(for write: QueuedWrite, type: TypeID?, catalogue: Catalogue) -> SyncProblemEntry? {
        let kind: SyncProblemEntry.Kind
        let reason: SyncProblem
        switch write.verdict {
        case .refused(let refusal):
            kind = .refused
            reason = MarfaMapping.problem(refusal)
        case .blocked(let marfaReason, let refusal):
            guard let blocked = MarfaMapping.blockedReason(marfaReason) else { return nil }
            kind = .blocked(blocked)
            var problem = refusal.map(MarfaMapping.problem) ?? SyncProblem(code: blocked.rawValue)
            problem.code = blocked.rawValue
            reason = problem
        case .dead:
            kind = .dead
            reason = SyncProblem(code: "dead")
        case nil, .accepted, .merged, .conflicted:
            return nil
        }
        return SyncProblemEntry(
            id: .write(write.id), itemID: write.itemId.map { ItemID($0) }, kind: kind, change: change(write.kind),
            reason: reason, content: content(of: write.body, type: type, catalogue: catalogue),
            actions: actions(for: kind), date: MarfaMapping.date(write.queuedAt))
    }

    static func entry(for copy: ConflictedCopy, catalogue: Catalogue) -> SyncProblemEntry {
        let id = ItemID(copy.row.id)
        let kind = SyncProblemEntry.Kind.conflicted(sibling: id, original: copy.original)
        var content = content(of: ["properties": .object(copy.row.properties)], type: TypeID(copy.row.type), catalogue: catalogue)
        // The copy carries the original's tags beside its own, which are not what the person wrote.
        content.tags = []
        return SyncProblemEntry(
            id: .conflictedCopy(id), itemID: id, kind: kind, change: .edit, reason: nil, content: content,
            actions: actions(for: kind), date: MarfaMapping.date(copy.row.createdAt))
    }

    /// What the contract lets the person do. A refused write is never sent again, only discarded. A blocked
    /// write whose reason clears on its own, a refused key or a missing grant, needs nothing from the queue. A
    /// write the server answers the same way however often it is sent is withdrawn rather than sent again.
    static func actions(for kind: SyncProblemEntry.Kind) -> [SyncAction] {
        switch kind {
        case .refused: [.discard]
        case .blocked(.credentialRefused): []
        case .blocked(.keySpent), .dead: [.tryAgain]
        case .blocked(.ancestorUnavailable), .blocked(.conflictUnresolved): [.withdraw]
        case .conflicted: [.keep, .discard]
        }
    }

    static func change(_ kind: WriteKind) -> SyncProblemEntry.Change {
        switch kind {
        case .createItem: .create
        case .updateItem: .edit
        case .deleteItem: .delete
        case .restoreItem: .restore
        case .transitionItem: .transition
        case .addTag: .tag
        case .removeTag: .untag
        case .createEdge, .updateEdge: .link
        case .deleteEdge: .unlink
        case .replaceMetadata, .mergeMetadata, .writeExtension, .deleteExtension, .uploadBlob: .other
        }
    }

    /// The title and body by the type's fields, then every other value written, in the catalogue's order. A
    /// cleared value is not content.
    static func content(of body: [String: JSONValue], type: TypeID?, catalogue: Catalogue) -> SyncContent {
        var properties: [String: JSONValue] = [:]
        if case .object(let written) = body["properties"] { properties = written }
        properties = properties.filter { $0.value != .null }
        let info = type.flatMap { catalogue.itemTypes[$0] }
        var content = SyncContent()
        if let titleField = MarfaMapping.titleField(of: info) {
            content.title = properties.removeValue(forKey: titleField).flatMap { text(MarfaMapping.value($0)) }
        }
        if let bodyField = info?.bodyField ?? (info == nil ? "body" : nil) {
            content.body = properties.removeValue(forKey: bodyField).flatMap { text(MarfaMapping.value($0)) }
        }
        let fields = info?.fields ?? []
        let ordered = catalogue.ordered(properties.mapValues(MarfaMapping.value), for: type ?? TypeID(""))
        content.properties = ordered.compactMap { property in
            guard let value = text(property.value) else { return nil }
            let label = fields.first { $0.key == property.key }?.label ?? MarfaMapping.label(forField: property.key)
            return SyncContent.Line(label: label, value: value)
        }
        if case .array(let tags) = body["tags"] { content.tags = tags.compactMap(\.string) }
        return content
    }

    static func text(_ value: PropertyValue) -> String? {
        switch value {
        case .null: nil
        case .bool(let bool): bool ? "true" : "false"
        case .number(let number): "\(number)"
        case .string(let string): string
        case .array(let values): values.compactMap(text).joined(separator: ", ")
        case .object(let object):
            object.sorted { $0.key < $1.key }.compactMap { key, value in text(value).map { "\(key): \($0)" } }
                .joined(separator: ", ")
        }
    }
}
