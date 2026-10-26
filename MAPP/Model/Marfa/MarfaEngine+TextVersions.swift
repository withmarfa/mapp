import Foundation
import Marfa

/// Which version of an item's text an edit is sent on.
extension MarfaEngine {
    /// An edit is sent on the version of the text it was typed on: as an ordinary update where the copy holds that
    /// version, and otherwise said to be read there, so the server merges it against what was read rather than
    /// laying it over a change the person never saw (`queue-and-verdicts/as-read-sent-on-read`). An edit queued
    /// behind the person's own on the version the copy holds moves onto that edit's answer
    /// (`queue-and-verdicts/edit-on-answer`). The copy moves as answers and catch-ups land, so the version is
    /// decided against one reading of the copy, and again if the copy moved meanwhile.
    func send(
        _ id: ItemID, _ properties: JSONObject, replacing: Bool = false, type: String? = nil, tier: Marfa.Tier? = nil,
        typedOn: () async throws -> Int64
    ) async throws -> Marfa.QueuedWrite {
        var attempt = 0
        while true {
            attempt += 1
            let held = try await heldVersion(id)
            let version = Self.version(read: try await typedOn(), holding: held)
            let steady = try await heldVersion(id) == held && version <= held
            let edit = Edit(
                properties: properties, replaceProperties: replacing, baseVersion: version, type: type, tier: tier)
            do {
                if steady, version < held {
                    let queued = try await copy.items.updateAsRead(id.rawValue, edit)
                    sentAsRead.insert(queued.id)
                    return queued
                }
                if steady || attempt == 3 { return try await copy.items.update(id.rawValue, edit) }
            } catch where attempt < 3 {
                continue
            }
        }
    }

    /// The version that text read at `read` is on, now that the copy holds `held`. A page that opens a note as soon
    /// as it is made can read this device's own create before the server answers it, at version 0, which no server
    /// holds (`device/version-local-create`). Once the copy holds the answer, that text is version 1
    /// (`versions/create-version-one`), so an edit typed on it is sent on version 1; sent on 0, it would be refused.
    nonisolated static func version(read: Int64, holding held: Int64) -> Int64 {
        read == 0 && held > 0 ? 1 : read
    }

    /// The version an edit that follows the person's last edit of the text was typed on: the version their own
    /// writes account for. Where the copy holds that version it holds only the person's text over what they read;
    /// where it holds a later one, another device's change came in, and the edit is merged against it. While the
    /// person's own edits of it still wait, a later version cannot yet say whether the server will take them or
    /// keep the other device's text, so the answer is waited for a moment, as the drain under way brings it; one
    /// that does not come leaves the edit merged against the older version, which never overwrites.
    func followingVersion(_ id: ItemID, otherwise base: ItemVersion) async throws -> Int64 {
        guard ownText[id] != nil else { return base.rawValue }
        func waiting(_ queue: [Marfa.QueuedWrite]) -> Bool {
            queue.contains { $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict == nil }
        }
        var queue = try await copy.queue.all()
        try await count(answers: queue, for: id)
        if let own = ownText[id], try await heldVersion(id) > own.on, waiting(queue) {
            let clock = ContinuousClock()
            let end = clock.now + .seconds(2)
            while waiting(queue), clock.now < end {
                try await Task.sleep(for: .milliseconds(50))
                queue = try await copy.queue.all()
            }
            try await count(answers: queue, for: id)
        }
        return ownText[id]?.on ?? base.rawValue
    }

    /// Moves the version the person's own writes account for past the answers the copy has taken. A create or update
    /// the server took on the version it held moves the item one version on (`versions/create-version-one`,
    /// `versions/update-step`); one merged, or sent as read on an older version, lands on whatever the server held,
    /// which the copy now shows with every answer taken so far. Any other answer leaves the item where it was.
    func count(answers queue: [Marfa.QueuedWrite], for id: ItemID) async throws {
        guard let own = ownText[id] else { return }
        var taken = counted
        ownText[id] = try await Self.counting(queue, for: id, own: own, counted: &taken, sentAsRead: sentAsRead) {
            try await self.heldVersion(id)
        }
        counted.formUnion(taken)
    }

    /// `own` moved past the answers in `queue` not yet in `counted`. Each is put in `counted` only once its effect
    /// is known, so an answer whose version cannot be read, as while the copy is hydrated again, is counted later.
    nonisolated static func counting(
        _ queue: [Marfa.QueuedWrite], for id: ItemID, own: OwnText, counted: inout Set<String>, sentAsRead: Set<String>,
        held: () async throws -> Int64
    ) async rethrows -> OwnText {
        let answered = queue.filter {
            $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict != nil
                && !counted.contains($0.id)
        }
        guard !answered.isEmpty else { return own }
        let landedElsewhere = answered.contains { write in
            if case .merged = write.verdict { return true }
            return write.verdict == .accepted && sentAsRead.contains(write.id)
        }
        var own = own
        own.on = landedElsewhere ? try await held() : own.on + Int64(answered.count { $0.verdict == .accepted })
        counted.formUnion(answered.map(\.id))
        return own
    }

    func answeredWrites(of id: ItemID) async throws -> [String] {
        try await copy.queue.all().filter { $0.itemId == id.rawValue && $0.verdict != nil }.map(\.id)
    }

    private func heldVersion(_ id: ItemID) async throws -> Int64 {
        if let row = try await copy.items.get(id.rawValue) { return row.version }
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."))
        }
        return row.version
    }
}
