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
        _ id: ItemID, _ properties: JSONObject, clearing: Set<String> = [], type: String? = nil, tier: Marfa.Tier? = nil,
        typedOn: () async throws -> Int64
    ) async throws -> Marfa.QueuedWrite {
        var attempt = 0
        while true {
            attempt += 1
            let held = try await heldVersion(id)
            let version = Self.version(read: try await typedOn(), holding: held)
            let steady = try await heldVersion(id) == held && version <= held
            let edit = Edit(
                properties: properties, clearProperties: clearing, baseVersion: version, type: type, tier: tier)
            do {
                if steady, version < held { return try await copy.items.updateAsRead(id.rawValue, edit) }
                if steady || attempt == 3 { return try await copy.items.update(id.rawValue, edit) }
            } catch where attempt < 3 {
                continue
            }
        }
    }

    /// The version that text read at `read` is on, now that the copy holds `held`. A page that opens an item as soon
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
        var queue = try await queueWithAnswers()
        try await count(answers: queue, for: id)
        if let own = ownText[id], try await heldVersion(id) > own.on, waiting(queue) {
            let clock = ContinuousClock()
            let end = clock.now + .seconds(2)
            while waiting(queue), clock.now < end {
                try await Task.sleep(for: .milliseconds(50))
                queue = try await queueWithAnswers()
            }
            try await count(answers: queue, for: id)
        }
        return ownText[id]?.on ?? base.rawValue
    }

    /// Moves the version the person's own writes account for to the latest one the copy's answers prove holds exactly
    /// the person's text (`counting`). A save that follows goes on that version only, so it never lands over a change
    /// to the text the person did not see; where no answer proves a later one, it stays where it was, and the next
    /// save is sent as read there, which the server merges or keeps beside the other change.
    func count(answers queue: [Marfa.QueuedWrite], for id: ItemID) async throws {
        guard let own = ownText[id] else { return }
        var taken = counted
        let types = catalogue.itemTypes
        ownText[id] = try await Self.counting(
            queue, for: id, own: own, counted: &taken, bodyField: { MarfaMapping.bodyField(of: types[TypeID($0)]) },
            held: { try await self.heldVersion(id) })
        counted.formUnion(taken)
    }

    /// `own` moved to the latest version an answer in `queue`, not yet in `counted`, proves holds `own.text`. An
    /// answer to an update proves its version where the item it carries holds that text in its type's body field
    /// (`bodyField`), as the contract moves an edit onto an earlier edit's answer only where the answer holds what the
    /// edit was made against (`queue-and-verdicts/edit-on-answer`, `queue-and-verdicts/edit-not-on-unheld-answer`).
    /// An answer to a write that did not carry the text, as a title change, can hold another device's text, and one
    /// that names no version, or a merge that changed the text, proves none. This device's create proves version 1,
    /// the one it made, whatever version a repeat is answered at (`queue-and-verdicts/create-repeat-edit-rebased`).
    /// The latest proven version is taken, whatever order the answers come in.
    ///
    /// An answer proving a version later than the copy holds (`held`), as one whose read-back is still owed, stays out
    /// of `counted` until the copy holds it, since an edit on a version the copy does not hold is refused
    /// (`queue-and-verdicts/as-read-bounds`). Every other answer is counted. A copy whose version cannot be read, as
    /// while it is hydrated again, throws and counts nothing.
    nonisolated static func counting(
        _ queue: [Marfa.QueuedWrite], for id: ItemID, own: OwnText, counted: inout Set<String>,
        bodyField: (String) -> String?, held: () async throws -> Int64
    ) async rethrows -> OwnText {
        let answered = queue.filter {
            $0.itemId == id.rawValue && [.createItem, .updateItem].contains($0.kind) && $0.verdict != nil
                && !counted.contains($0.id)
        }
        guard !answered.isEmpty else { return own }
        let proven = answered.map { ($0.id, provenVersion(by: $0, holding: own.text, bodyField: bodyField)) }
        let copy = proven.contains { ($0.1 ?? 0) > own.on } ? try await held() : own.on
        var own = own
        for (write, version) in proven {
            if let version {
                guard version <= copy else { continue }
                own.on = max(own.on, version)
            }
            counted.insert(write)
        }
        return own
    }

    /// The version `write`'s answer proves holds exactly `text`, if any.
    private nonisolated static func provenVersion(
        by write: Marfa.QueuedWrite, holding text: String, bodyField: (String) -> String?
    ) -> Int64? {
        switch write.verdict {
        case .accepted?, .merged?: break
        default: return nil
        }
        if write.kind == .createItem { return 1 }
        guard let item = write.answer?.object?["item"]?.object, let version = item["version"]?.integer,
            let type = item["type"]?.string, let field = bodyField(type), let properties = item["properties"]?.object
        else { return nil }
        // An item with no text property holds empty text, as `MarfaMapping.body` reads it.
        let body: String? =
            switch properties[field] {
            case nil, .null?: ""
            case .string(let held)?: held
            default: nil
            }
        return body == text ? version : nil
    }

    func answeredWrites(of id: ItemID) async throws -> [String] {
        try await queueWithAnswers().filter { $0.itemId == id.rawValue && $0.verdict != nil }.map(\.id)
    }

    private func heldVersion(_ id: ItemID) async throws -> Int64 {
        if let row = try await copy.items.get(id.rawValue) { return row.version }
        guard let row = rows[id.rawValue] else {
            throw MarfaError.notFound(code: "item_not_found", message: String(localized: "This item isn’t in the library."), server: nil)
        }
        return row.version
    }
}
