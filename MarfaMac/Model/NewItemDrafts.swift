import Foundation
import os

/// Every item a person typed and has not added, kept on this Mac so none is lost: not to a scroll, a sync, a change
/// of place, a closed window, a quit, or a create the library refused. The new-item line and the text form hold one
/// each, and an in-place row in a table, board or calendar holds its own under a slot of its own.
///
/// Each draft is written to disk at once, whole, as it changes. A window holding a draft claims it, so two windows
/// never edit one draft; a window that closes lets it go, and the next to open the same slot in the same library
/// takes it back. A draft that was added waits, still kept, until its library holds the item or refuses it.
final class NewItemDrafts {
    /// Which kind of new item a draft is for, so each place that makes items finds only its own.
    struct Slot: RawRepresentable, Hashable, Codable, Sendable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        /// The new-item line and the text form, which hand one draft between them.
        static let line = Slot(rawValue: "line")
        /// A row typed in place, named by where it stands: a list, a lane or a day.
        static func inPlace(_ key: String) -> Slot { Slot(rawValue: "row:" + key) }
    }

    struct Entry: Identifiable {
        let id: UUID
        let slot: Slot
        /// The library the draft names items and fields in (`ItemLibrary.serverKey`).
        let library: String
        var draft: QuickAdd.Draft
        /// The item the draft was added as, while the library has neither taken nor refused it.
        var sent: ItemID?
        var updated: Date
        /// The files the draft held that are no longer where they were, by name, found as it was read back.
        var missingFiles: [String] = []
        /// Given back because the library refused it, and not yet taken since.
        var returned = false
    }

    private let file: URL?
    private var entries: [UUID: Entry]
    /// The drafts a holder has open, which no other may take.
    private var claimed: Set<UUID> = []
    private let now: () -> Date

    /// Keeps the drafts in `file`, or only in memory where it is nil.
    init(file: URL?, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        entries = file.map(Self.read) ?? [:]
    }

    /// The app's own drafts. A unit test's host gets a store in memory for each holder, so no test reads another's
    /// draft or the person's.
    static func standard() -> NewItemDrafts {
        #if DEBUG
        if TestHost.isRequested { return NewItemDrafts(file: nil) }
        #endif
        return shared
    }

    private static let shared = NewItemDrafts(file: AppPaths.applicationSupport.appending(path: "New Item Drafts.json"))

    // MARK: The holder's calls

    /// Claims the slot's most recently typed draft in `library` that nobody holds, or nil where there is none. A
    /// draft added and still waiting is not offered.
    func take(_ slot: Slot, in library: String) -> Entry? {
        let open = entries.values.filter { $0.slot == slot && $0.library == library && $0.sent == nil && !claimed.contains($0.id) }
        return open.max(by: { $0.updated < $1.updated }).map(take)
    }

    /// Claims the slot's most recent draft in `library` that the library refused and nobody has taken since.
    func takeReturned(_ slot: Slot, in library: String) -> Entry? {
        let returned = entries.values.filter { $0.slot == slot && $0.library == library && $0.returned && !claimed.contains($0.id) }
        guard let entry = returned.max(by: { $0.updated < $1.updated }) else { return nil }
        return take(entry)
    }

    private func take(_ entry: Entry) -> Entry {
        claimed.insert(entry.id)
        entries[entry.id]?.returned = false
        return entry
    }

    /// Starts a draft in the slot, claimed by its maker. Nothing is written until it holds something.
    func make(_ slot: Slot, _ draft: QuickAdd.Draft, in library: String) -> UUID {
        let id = UUID()
        pending[id] = (slot, library, draft)
        claimed.insert(id)
        return id
    }

    /// What was typed: kept where it holds something, and dropped where it is empty again.
    func update(_ id: UUID, _ draft: QuickAdd.Draft) {
        if let entry = entries[id] {
            guard draft.hasContent else { return remove(id, keepingClaim: true) }
            entries[id] = Entry(id: id, slot: entry.slot, library: entry.library, draft: draft, updated: now())
        } else if let start = pending[id] {
            pending[id] = (start.slot, start.library, draft)
            guard draft.hasContent else { return }
            entries[id] = Entry(id: id, slot: start.slot, library: start.library, draft: draft, updated: now())
        } else {
            return
        }
        save()
    }

    /// The holder stepped away, as Escape does: an empty draft is dropped and a typed one kept. Returns whether it
    /// was kept. The holder still has it.
    @discardableResult
    func escape(_ id: UUID) -> Bool {
        guard let entry = entries[id], entry.draft.hasContent else {
            remove(id, keepingClaim: true)
            return false
        }
        return true
    }

    /// The draft was added as `item`. It stays kept, out of every holder's reach, until `settle` finds the library
    /// holds the item, or gives it back where the library refused it.
    func added(_ id: UUID, as item: ItemID) {
        pending[id] = nil
        claimed.remove(id)
        guard entries[id] != nil else { return }
        entries[id]?.sent = item
        save()
    }

    /// The holder went, as a window does when it closes or changes library. The draft stays for the next to take.
    func release(_ id: UUID) {
        pending[id] = nil
        claimed.remove(id)
    }

    /// The draft is gone for good: the person cleared it.
    func drop(_ id: UUID) {
        pending[id] = nil
        remove(id, keepingClaim: false)
    }

    /// Settles the drafts added in `library`: one whose item the library holds is dropped, and one it refused is
    /// offered again, as typed, and marked returned (`takeReturned`) until a holder takes it.
    func settle(in library: any ItemLibrary) {
        var changed = false
        for entry in entries.values where entry.library == library.serverKey {
            guard let item = entry.sent else { continue }
            if library.item(item) != nil {
                entries[entry.id] = nil
            } else if library.wasRefused(creating: item) || library.syncReport.problems.contains(where: { $0.itemID == item }) {
                entries[entry.id]?.sent = nil
                entries[entry.id]?.returned = true
                changed = true
            }
        }
        if changed || entries.count != stored { save() }
    }

    /// Whether a draft is kept for `slot` in `library` that a holder could take.
    func holdsDraft(_ slot: Slot, in library: String) -> Bool {
        entries.values.contains { $0.slot == slot && $0.library == library && $0.sent == nil && !claimed.contains($0.id) }
    }

    // MARK: Keeping

    /// A draft claimed but still empty, which is not written.
    private var pending: [UUID: (slot: Slot, library: String, draft: QuickAdd.Draft)] = [:]
    /// How many drafts the file held when last written.
    private var stored = 0

    private func remove(_ id: UUID, keepingClaim: Bool) {
        if !keepingClaim { claimed.remove(id) }
        if keepingClaim, let entry = entries[id] { pending[id] = (entry.slot, entry.library, entry.draft) }
        guard entries.removeValue(forKey: id) != nil else { return }
        save()
    }

    /// Writes every draft at once, whole, so a quit or a crash keeps what was last typed.
    private func save() {
        stored = entries.count
        guard let file else { return }
        let stored = entries.values.sorted { $0.updated < $1.updated }.map(StoredEntry.init)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if stored.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else {
                try JSONEncoder().encode(stored).write(to: file, options: .atomic)
            }
        } catch {
            Telemetry.logger(.navigation).error("New item drafts not written: \(error.localizedDescription)")
        }
    }

    /// An unreadable file is set aside, never removed, so a later version may read it.
    private static func read(_ file: URL) -> [UUID: Entry] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        guard let stored = try? JSONDecoder().decode([StoredEntry].self, from: data) else {
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: file, to: aside)
            return [:]
        }
        return Dictionary(stored.map(\.entry).map { ($0.id, $0) }) { first, _ in first }
    }
}

// MARK: On disk

/// A draft as the file holds it. A file is kept by its path and read again where it is.
private struct StoredEntry: Codable {
    var id: UUID
    var slot: NewItemDrafts.Slot
    var library: String
    var sent: ItemID?
    var updated: Date
    var typeID: String
    var title: String
    var body: String
    var caret: Int?
    var properties: [String: StoredValue]
    var prefilled: [String: StoredValue]
    var declinedPrefill: Bool
    var parentID: ItemID?
    var chips: [String]
    var files: [String]
    var tags: [String]
    var feed: Bool
    var declinedDay: String?

    init(_ entry: NewItemDrafts.Entry) {
        let draft = entry.draft
        id = entry.id
        slot = entry.slot
        library = entry.library
        sent = entry.sent
        updated = entry.updated
        typeID = draft.typeID
        title = draft.title
        body = draft.body
        caret = draft.caret
        properties = draft.properties.mapValues(StoredValue.init)
        prefilled = draft.prefilled.mapValues(StoredValue.init)
        declinedPrefill = draft.declinedPrefill
        parentID = draft.parentID
        chips = draft.chips.map { chip in
            switch chip {
            case .parent: "parent"
            case .field(let key): "field:" + key
            }
        }
        files = draft.files.map { $0.url.path(percentEncoded: false) }
        tags = draft.tags
        feed = draft.tier == .feed
        declinedDay = draft.declinedDay
    }

    var entry: NewItemDrafts.Entry {
        var draft = QuickAdd.Draft(typeID: typeID)
        draft.title = title
        draft.body = body
        draft.caret = caret
        draft.properties = properties.mapValues(\.value)
        draft.prefilled = prefilled.mapValues(\.value)
        draft.declinedPrefill = declinedPrefill
        draft.parentID = parentID
        draft.chips = chips.map { $0 == "parent" ? .parent : .field(String($0.dropFirst("field:".count))) }
        var missing: [String] = []
        for path in files {
            let url = URL(filePath: path)
            if let file = QuickAdd.File(url) { draft.files.append(file) } else { missing.append(url.lastPathComponent) }
        }
        draft.tags = tags
        draft.tier = feed ? .feed : .library
        draft.declinedDay = declinedDay
        return NewItemDrafts.Entry(
            id: id, slot: slot, library: library, draft: draft, sent: sent, updated: updated, missingFiles: missing)
    }
}

/// A property's value as JSON, which keeps every case `PropertyValue` has.
private enum StoredValue: Codable {
    case null, bool(Bool), number(Decimal), double(Double), string(String), array([StoredValue]), object([String: StoredValue])

    init(_ value: PropertyValue) {
        switch value {
        case .null: self = .null
        case .bool(let flag): self = .bool(flag)
        case .number(let number): self = .number(number)
        case .double(let number): self = .double(number)
        case .string(let text): self = .string(text)
        case .array(let values): self = .array(values.map(StoredValue.init))
        case .object(let values): self = .object(values.mapValues(StoredValue.init))
        }
    }

    var value: PropertyValue {
        switch self {
        case .null: .null
        case .bool(let flag): .bool(flag)
        case .number(let number): .number(number)
        case .double(let number): .double(number)
        case .string(let text): .string(text)
        case .array(let values): .array(values.map(\.value))
        case .object(let values): .object(values.mapValues(\.value))
        }
    }
}
