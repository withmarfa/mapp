import Foundation
import os

/// Every item a person typed and has not added, kept on this Mac so none is lost: not to a scroll, a sync, a change
/// of place, a closed window, a quit, or a create the library refused. The new-item line and the text form hold one
/// each, and an in-place row in a table, board or calendar holds its own under a slot of its own.
///
/// Each draft is written to disk at once, whole, as it changes. A window holding a draft claims it, so two windows
/// never edit one draft; a window that closes lets it go, and the next to open the same slot in the same library
/// takes it back. A draft that was added, or whose file is on its way, waits, still kept, until its library holds the
/// item or refuses it.
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
        /// The item the draft is being or was added as, written before the create is made, so a create is never made
        /// twice: not after a crash, nor after a write that is only held up.
        var sent: ItemID?
        var updated: Date
        /// The files the draft held that are no longer where they were, by name, found as it was read back.
        var missingFiles: [String] = []
        /// Given back because the library refused it, and not yet taken since.
        var returned = false
        /// Its file is being added, which the library names only once it is queued, so no holder may take it.
        var addingFile = false
        /// The app stopped while its file was being added, so the file may be in the library already.
        var interrupted = false
    }

    private let file: URL?
    private var entries: [UUID: Entry]
    /// The drafts a holder has open, which no other may take.
    private var claimed: Set<UUID> = []
    private let now: () -> Date
    /// Where a draft that cannot be written to disk is told, once until a write works again.
    weak var notices: Notices?

    /// Keeps the drafts in `file`, or only in memory where it is nil.
    init(file: URL?, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        let read = file.map(Self.read) ?? (entries: [:], blocked: false)
        entries = read.entries
        blocked = read.blocked
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
    /// draft added or with its file on the way, and still waiting, is not offered.
    func take(_ slot: Slot, in library: String) -> Entry? {
        let open = entries.values.filter { $0.slot == slot && $0.library == library && isFree($0) }
        return open.max(by: { $0.updated < $1.updated }).map(take)
    }

    /// Claims the draft `id`, as one holder hands it to another, or nil where it is held, waiting or gone.
    func take(_ id: UUID, in library: String) -> Entry? {
        guard let entry = entries[id], entry.library == library, isFree(entry) else { return nil }
        return take(entry)
    }

    private func isFree(_ entry: Entry) -> Bool {
        entry.sent == nil && !entry.addingFile && !claimed.contains(entry.id)
    }

    /// Claims the slot's most recent draft in `library` that the library refused and nobody has taken since.
    func takeReturned(_ slot: Slot, in library: String) -> Entry? {
        let returned = entries.values.filter { $0.slot == slot && $0.library == library && $0.returned && isFree($0) }
        guard let entry = returned.max(by: { $0.updated < $1.updated }) else { return nil }
        return take(entry)
    }

    private func take(_ entry: Entry) -> Entry {
        claimed.insert(entry.id)
        if entry.returned || entry.interrupted {
            entries[entry.id]?.returned = false
            entries[entry.id]?.interrupted = false
            save()
        }
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
        if entries[id] != nil {
            guard draft.hasContent else { return remove(id, keepingClaim: true) }
            entries[id]?.draft = draft
            entries[id]?.updated = now()
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

    /// The draft is about to be added as `item`: written so before the create is made. Answers whether it was
    /// written, so a create is made only from a draft the store can follow after a crash.
    @discardableResult
    func sending(_ id: UUID, as item: ItemID) -> Bool {
        guard let entry = entries[id], !entry.library.isEmpty else { return false }
        entries[id]?.sent = item
        guard save() else {
            entries[id]?.sent = nil
            return false
        }
        return true
    }

    /// The draft's file is about to be added. The library names the file's item only once it is queued, so a draft
    /// read back with this still set comes back saying the file may be in the library already.
    func sendingFile(_ id: UUID) {
        guard entries[id] != nil else { return }
        entries[id]?.addingFile = true
        save()
    }

    /// The library made nothing from the draft, so it stays the holder's as typed.
    func notSent(_ id: UUID) {
        guard entries[id] != nil else { return }
        entries[id]?.sent = nil
        entries[id]?.addingFile = false
        save()
    }

    /// The draft was added as `item`. It stays kept, out of every holder's reach, until `settle` finds Marfa accepted
    /// the item, or gives it back where Marfa refused it.
    func added(_ id: UUID, as item: ItemID) {
        pending[id] = nil
        claimed.remove(id)
        guard entries[id] != nil else { return }
        entries[id]?.sent = item
        entries[id]?.addingFile = false
        save()
    }

    /// The holder went while the draft's file is on its way. `sent`, the draft as it went, stays under `id`, hidden
    /// until the library answers (`added`, `giveBack`); `rest`, what was typed besides, is kept for the next holder.
    func release(_ id: UUID, sending sent: QuickAdd.Draft, rest: QuickAdd.Draft) {
        pending[id] = nil
        claimed.remove(id)
        guard let entry = entries[id] else { return }
        entries[id]?.draft = sent
        if rest.hasContent {
            let kept = UUID()
            entries[kept] = Entry(id: kept, slot: entry.slot, library: entry.library, draft: rest, updated: now())
        }
        save()
    }

    /// The library made nothing from a draft no holder has, so it is offered again, marked returned.
    func giveBack(_ id: UUID) {
        guard entries[id] != nil else { return }
        entries[id]?.sent = nil
        entries[id]?.addingFile = false
        entries[id]?.returned = true
        entries[id]?.updated = now()
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

    /// Settles the drafts added in `library`, once it has read its copy and what waits to be sent. One whose create
    /// Marfa accepted is dropped. One whose create Marfa refused for good is offered again, as typed, and marked
    /// returned (`takeReturned`) until a holder takes it. Every other stays hidden, since it may yet be accepted: a
    /// create that waits, is held up, or is not in the copy yet.
    func settle(in library: any ItemLibrary) {
        if failing { save() }
        guard library.isLoaded, library.syncReport.queueRead else { return }
        var changed = false
        for entry in entries.values where entry.library == library.serverKey {
            guard let item = entry.sent else { continue }
            switch Self.answer(creating: item, in: library) {
            case .accepted:
                entries[entry.id] = nil
                changed = true
            case .refused:
                entries[entry.id]?.sent = nil
                entries[entry.id]?.returned = true
                changed = true
            case .waiting:
                break
            }
        }
        if changed { save() }
    }

    /// Settles `library`'s drafts each time Marfa refuses a create there, so the refusal is written with its draft at
    /// once, with no new item open, and outlives a quit.
    func follow(_ library: any ItemLibrary) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in Observations({ library.refusedCreates }) { self?.settle(in: library) }
        }
    }

    /// Whether a draft is kept for `slot` in `library` that a holder could take.
    func holdsDraft(_ slot: Slot, in library: String) -> Bool {
        entries.values.contains { $0.slot == slot && $0.library == library && isFree($0) }
    }

    /// What Marfa has said of a create: its final answer, never only the copy's own row for it.
    enum CreateAnswer: Equatable {
        case accepted, refused, waiting
    }

    static func answer(creating item: ItemID, in library: any ItemLibrary) -> CreateAnswer {
        if library.refusedCreates.contains(item) { return .refused }
        // Only Marfa's refusal gives a draft back. A create not in the copy may be on its way, so it waits.
        guard let held = library.item(item) else { return .waiting }
        switch held.sync {
        case .waiting, .blocked: return .waiting
        case .settled, .conflicted, .refused: return .accepted
        }
    }

    // MARK: Keeping

    /// A draft claimed but still empty, which is not written.
    private var pending: [UUID: (slot: Slot, library: String, draft: QuickAdd.Draft)] = [:]
    /// Whether the last write failed, so the person was told and the next change, or settle, tries again.
    private var failing = false
    /// The file was there and could not be read or set aside, so it is never written over.
    private var blocked: Bool

    private func remove(_ id: UUID, keepingClaim: Bool) {
        if !keepingClaim { claimed.remove(id) }
        if keepingClaim, let entry = entries[id] { pending[id] = (entry.slot, entry.library, entry.draft) }
        guard entries.removeValue(forKey: id) != nil else { return }
        save()
    }

    /// Writes every draft at once, whole, so a quit or a crash keeps what was last typed. A write that fails is told
    /// once, and tried again at the next change. A draft whose library has not read its instance yet stays in memory,
    /// since no later run could tell which library it is for.
    @discardableResult
    private func save() -> Bool {
        guard let file else { return true }
        let stored = entries.values.filter { !$0.library.isEmpty }.sorted { $0.updated < $1.updated }.map(StoredEntry.init)
        do {
            if blocked { throw CocoaError(.fileReadNoPermission) }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if stored.isEmpty {
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { try FileManager.default.removeItem(at: file) }
            } else {
                try JSONEncoder().encode(stored).write(to: file, options: .atomic)
            }
            failing = false
            return true
        } catch {
            Telemetry.logger(.navigation).error("New item drafts not written: \(error.localizedDescription)")
            guard !failing else { return false }
            failing = true
            notices?.tell(
                String(localized: "New Items Not Saved"),
                String(localized: "The app can’t save what you type in new items on this Mac, so it would be lost if the app quit. It keeps trying."))
            return false
        }
    }

    /// An unreadable file is set aside under a name of its own, never removed or written over, so a later version
    /// may read it.
    private static func read(_ file: URL) -> (entries: [UUID: Entry], blocked: Bool) {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return ([:], false) }
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([StoredEntry].self, from: data) {
            return (Dictionary(stored.map(\.entry).map { ($0.id, $0) }) { first, _ in first }, false)
        }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let name = "\(file.deletingPathExtension().lastPathComponent) unreadable \(stamp) \(UUID().uuidString.prefix(8)).json"
        let aside = file.deletingLastPathComponent().appending(path: name)
        do {
            try FileManager.default.moveItem(at: file, to: aside)
            return ([:], false)
        } catch {
            return ([:], true)
        }
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
    var marks: [StoredMark]
    var declined: [String]
    var setAside: [String: StoredValue]
    var setAsideParent: ItemID?
    var addingFile: Bool
    /// Present, and true, only for a draft Marfa refused that no holder has taken since.
    var returned: Bool?

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
        chips = draft.chips.map(\.stored)
        marks = draft.marks.map { StoredMark(lower: $0.range.lowerBound, upper: $0.range.upperBound, words: $0.words, chip: $0.chip.stored) }
        declined = draft.declined
        files = draft.files.map { $0.url.path(percentEncoded: false) }
        tags = draft.tags
        feed = draft.tier == .feed
        setAside = draft.setAside.mapValues(StoredValue.init)
        setAsideParent = draft.setAsideParent
        addingFile = entry.addingFile
        returned = entry.returned ? true : nil
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
        draft.chips = chips.map(QuickAdd.Chip.init(stored:))
        // A mark that no longer fits the title it was kept with is left out, so Add never takes the wrong words.
        draft.marks = marks.compactMap { mark in
            guard mark.lower >= 0, mark.lower <= mark.upper, mark.upper <= title.count else { return nil }
            return QuickAdd.Mark(range: mark.lower..<mark.upper, words: mark.words, chip: QuickAdd.Chip(stored: mark.chip))
        }
        draft.declined = declined
        var missing: [String] = []
        for path in files {
            let url = URL(filePath: path)
            if let file = QuickAdd.File(url) { draft.files.append(file) } else { missing.append(url.lastPathComponent) }
        }
        draft.tags = tags
        draft.tier = feed ? .feed : .library
        draft.setAside = setAside.mapValues(\.value)
        draft.setAsideParent = setAsideParent
        return NewItemDrafts.Entry(
            id: id, slot: slot, library: library, draft: draft, sent: sent, updated: updated, missingFiles: missing,
            returned: addingFile || returned == true, interrupted: addingFile)
    }
}

/// The typed words a chosen chip was read from, as the file holds them.
private struct StoredMark: Codable {
    var lower: Int
    var upper: Int
    var words: String
    var chip: String
}

extension QuickAdd.Chip {
    /// The chip as the file holds it: `parent`, `field:<key>` or `tag:<tag>`.
    fileprivate var stored: String {
        switch self {
        case .parent: "parent"
        case .field(let key): "field:" + key
        case .tag(let tag): "tag:" + tag
        }
    }

    fileprivate init(stored: String) {
        if stored.hasPrefix("tag:") {
            self = .tag(String(stored.dropFirst("tag:".count)))
        } else if stored == "parent" {
            self = .parent
        } else {
            self = .field(String(stored.dropFirst("field:".count)))
        }
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
