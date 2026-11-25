import Foundation
import Marfa
import os

/// Taking the answers the copy holds: telling each write its verdict, and the copy clearing those taken.
extension MarfaEngine {
    /// The queue as the engine counts the person's text against: what the copy holds, and the answers taken from
    /// it that an item's text has not yet been counted past (`answeredHeld`).
    func queueWithAnswers() async throws -> [Marfa.QueuedWrite] {
        var queued = try await copy.queue.all()
        #if DEBUG
        queued += hooks.answers.current ?? []
        #endif
        let ids = Set(queued.map(\.id))
        return queued + answeredHeld.values.filter { !ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    /// Takes the answers the copy recorded, from a drain of ours or one the copy ran itself, in the engine's own
    /// step. The copy clears and returns the answered writes (`Queue.takeAnswered`); a refused write that carried
    /// content, a blocked one and a dead one stay in the queue with their verdict, so each is told here once. An
    /// expired copy refuses the take, and a later update takes them once it is hydrated again.
    func takeAnswers() async {
        let taken: [Marfa.QueuedWrite]
        do {
            taken = try await Self.asking { try await copy.queue.takeAnswered() }
        } catch {
            return
        }
        var answers = taken
        if let queued = try? await copy.queue.all() {
            // A blocked write that is released and then refused carries a new verdict, which is told too.
            answers += queued.filter { $0.verdict != nil && told[$0.id] != $0.verdict }
            told = Dictionary(queued.compactMap { write in write.verdict.map { (write.id, $0) } }, uniquingKeysWith: { _, last in last })
        }
        let library = await libraryWrites(answers)
        let shown = Set(library.map(\.id))
        preferenceAnswers.receive(answers.filter { !shown.contains($0.id) })
        answers = library
        guard !answers.isEmpty else { return }
        await answer(answers)
    }

    /// Tells each verdict to the app's write and shows it on its item. A refusal or conflict stays shown after
    /// that through `remembered`, and every refused write through `refusals` until the person discards it; one that carried content stays
    /// queued until then.
    func answer(_ writes: [Marfa.QueuedWrite]) async {
        #if DEBUG
        await hooks.answering.current?()
        #endif
        var ids: Set<String> = []
        // The copy lets an item go once its delete is answered.
        var leaving: Set<String> = []
        let answeredNow = Dictionary(writes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for answer in writes {
            if let itemID = answer.itemId, [.deleteItem, .restoreItem].contains(answer.kind) { leaving.insert(itemID) }
            guard let verdict = answer.verdict else { continue }
            if [.createItem, .updateItem].contains(answer.kind), answer.itemId != nil { answeredHeld[answer.id] = answer }
            // The copy clears a refused write that carried no content as it hands it over, so no read of the queue
            // finds it again.
            if case .refused = verdict { refusals[answer.id] = answer }
            let outcome = MarfaMapping.outcome(
                verdict, afterRefusal: MarfaProblems.waitsOnStopped(answer, among: { answeredNow[$0] ?? refusals[$0] }))
            ids.formUnion(movedEnds.removeValue(forKey: answer.id) ?? [])
            // A blocked or dead link may be released and sent again, so it is followed until it is answered for good.
            if !outcome.mayBeSentAgain, let link = parentLinks.removeValue(forKey: answer.id) {
                ids.formUnion([link.child.rawValue, link.parent.rawValue])
                if case .refused(let problem) = outcome {
                    let reason = problem.message ?? String(localized: "The Marfa server refused this change.")
                    refusedParentLinks.append(ParentRefusal(link: link, reason: reason, listed: true))
                }
            }
            if let itemID = answer.itemId {
                ids.insert(itemID)
                remember(outcome, of: answer.kind, for: ItemID(itemID))
            }
            if case .conflicted(let sibling, _) = outcome {
                ids.insert(sibling.rawValue)
                if let itemID = answer.itemId { originals[sibling.rawValue] = itemID }
            }
            answered(answer.id, outcome, holding: answer.kind == .updateItem ? MarfaMapping.holding(answeredBy: answer.answer) : nil)
        }
        await reread(ids.union(await settledLinks()))
        // An answer the person's text cannot yet be moved past is held, to be counted by the next save or the next
        // answer, since dropping it would leave the text on a version it has passed.
        if let queued = try? await queueWithAnswers() {
            for raw in Set(queued.compactMap(\.itemId)) where ownText[ItemID(raw)] != nil {
                do {
                    try await count(answers: queued, for: ItemID(raw))
                } catch {
                    // An item the copy has let go, as when its delete was answered in this drain, has no version to
                    // count against and never will, so its text is forgotten rather than holding every answer back.
                    if await hasLeft(raw) {
                        ownText[ItemID(raw)] = nil
                        counted.formUnion(queued.filter { $0.itemId == raw }.map(\.id))
                    }
                }
            }
        }
        pruneAnswers()
        if !leaving.isEmpty { await reread(leaving) }
        await readQueue()
        await publish([])
    }

    /// Lets go of an answer once its item's text has been counted past it, or the item has no text of the person's
    /// to count.
    private func pruneAnswers() {
        for (id, write) in answeredHeld where counted.contains(id) || write.itemId.map({ ownText[ItemID($0)] == nil }) ?? true {
            answeredHeld[id] = nil
        }
    }

    func remember(_ outcome: WriteOutcome, of kind: WriteKind, for item: ItemID) {
        switch outcome {
        case .refused, .conflicted:
            remembered[item] = (outcome.syncState, kind)
        case .accepted, .merged:
            if let held = remembered[item], held.kind == kind || kind == .updateItem { remembered[item] = nil }
            let queued = Set(queue.map(\.id))
            refusals = refusals.filter { id, write in
                queued.contains(id) || write.itemId != item.rawValue || (write.kind != kind && kind != .updateItem)
            }
        case .blocked, .dead:
            // The queue keeps these until they are released or withdrawn.
            break
        }
    }

    /// A write the app made as several queued writes is answered once, when the last of them is (`MarfaWriteRecord`).
    func answered(_ queued: String, _ outcome: WriteOutcome, holding: [String: PropertyValue]? = nil) {
        guard let answer = writes.answer(queued, outcome, holding: holding) else { return }
        hub.publish(.answered(answer.id, answer.outcome, holding: answer.holding))
    }

    private func hasLeft(_ raw: String) async -> Bool {
        guard rows[raw] == nil else { return false }
        return (try? await copy.items.get(raw)) == nil
    }
}

/// A new item's parent link, as queued.
nonisolated struct ParentLink: Hashable, Codable, Sendable {
    let child: ItemID
    let parent: ItemID
}

/// The new items' parent links waiting for the server, by queued write, written whole to `file` at each change.
nonisolated struct ParentLinkStore {
    private let file: URL?
    private var links: [String: ParentLink]

    init(file: URL?) {
        self.file = file
        links = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: ParentLink].self, from: $0) } ?? [:]
    }

    mutating func keep(_ link: ParentLink, for write: String) {
        links[write] = link
        save()
    }

    mutating func removeValue(forKey write: String) -> ParentLink? {
        guard let link = links.removeValue(forKey: write) else { return nil }
        save()
        return link
    }

    var isEmpty: Bool { links.isEmpty }
    func link(for write: Marfa.QueuedWrite) -> ParentLink? { links[write.id] }
    mutating func refuse(_ write: String, reason: String) {}

    mutating func keepOnly(_ writes: Set<String>) {
        let kept = links.filter { writes.contains($0.key) }
        guard kept.count != links.count else { return }
        links = kept
        save()
    }

    /// A link not written is still told while the app runs; only a relaunch loses it.
    private func save() {
        guard let file else { return }
        do {
            if links.isEmpty {
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { try FileManager.default.removeItem(at: file) }
            } else {
                try JSONEncoder().encode(links).write(to: file, options: .atomic)
            }
        } catch {
            Telemetry.logger(.engine).error("New item parent links not written: \(error.localizedDescription)")
        }
    }
}

/// A parent link refused as it was queued, or by the server later, when the refused write is also `listed` in Settings.
nonisolated struct ParentRefusal: Hashable, Sendable {
    let link: ParentLink
    let reason: String
    let listed: Bool
}

nonisolated extension WriteOutcome {
    /// Blocked or dead, so a release sends the write again.
    fileprivate var mayBeSentAgain: Bool {
        switch self {
        case .blocked, .dead: true
        case .accepted, .merged, .conflicted, .refused: false
        }
    }
}
