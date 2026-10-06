import Foundation
import Observation

/// One item as the views read it, observed on its own, so a change to one item redraws only what shows it.
@Observable final class ItemRecord {
    var item: Item
    /// Nil for an item with no text, and until its text is read.
    var body: ItemBody?
    /// False once the source no longer holds the item, which tells the views that read only this record.
    var isHeld = true

    init(_ item: Item) {
        self.item = item
    }
}

/// A library read from a Marfa server's working copy through its source. It holds what the source last said and
/// changes nothing on its own: every write goes to the source, which applies it to its copy at once and says what
/// changed. Undo is kept here, as writes that put back what a write changed, made at the version current when
/// the undo runs.
@Observable final class MarfaLibrary: ItemLibrary {
    private(set) var isLoaded = false
    var failure: (title: String, message: String)?
    var notesToPurge: Set<ItemID> = []
    private(set) var catalogue = Catalogue()
    private(set) var syncReport: SyncReport
    /// How the server stands, for the app to show beside the library.
    private(set) var connection: MarfaHost.State
    let now: () -> Date

    /// Bumped when any item changes, for the lists and search.
    private var contentRevision = 0
    /// Bumped only when an item comes, goes or changes which places hold it, for the counts.
    private var membershipRevision = 0
    private var searchRevision = 0

    @ObservationIgnored let source: any ConnectedItemSource
    @ObservationIgnored private var records: [ItemID: ItemRecord] = [:]
    @ObservationIgnored private(set) var index = MarfaItemIndex()
    @ObservationIgnored private var listed: [SidebarItem: Listing] = [:]
    @ObservationIgnored private var counted: [SidebarItem: (revision: Int, count: Int)] = [:]
    @ObservationIgnored private var searches: [String: Search] = [:]
    @ObservationIgnored private var searchOrder: [String] = []
    /// What the last search to finish found, shown while the next one runs so the list does not empty per key.
    @ObservationIgnored private var lastFound: [ItemID] = []
    /// Text writes the source has not answered, by item. While any wait, the text the person gave is what the
    /// library holds, since a read that raced the write could give older text.
    @ObservationIgnored private var unsettledText: [ItemID: Set<WriteID>] = [:]
    @ObservationIgnored private var textWrites: [WriteID: ItemID] = [:]
    /// The version of the text the person's last save of each item was typed on. Only the first save typed on a
    /// version is merged against it; the rest follow the person's own.
    @ObservationIgnored private var savedOn: [ItemID: ItemVersion] = [:]
    /// Links removed only once the source has taken the links added in their place, by the link writes awaited.
    @ObservationIgnored private var replacements: [UUID: Replacement] = [:]
    @ObservationIgnored private var replacing: [WriteID: UUID] = [:]
    /// What to tell the person if the source refuses each write the library made.
    @ObservationIgnored private var refusals: [WriteID: Refusal] = [:]
    @ObservationIgnored private var following: [Task<Void, Never>] = []
    /// The item each create names, until the source answers it.
    @ObservationIgnored private var creating: [WriteID: ItemID] = [:]
    /// Creates the source refused before it held the item, such as one made while the copy is brought up to date,
    /// so the draft it came from is the person's to send again.
    private(set) var refusedCreations: Set<ItemID> = []
    /// The text of each item's last save until the source answers it, so text a closing source refuses can be
    /// given back to the person. Only the last is kept, since it holds everything typed before it.
    @ObservationIgnored private var lastTyped: [ItemID: (write: WriteID, text: String)] = [:]
    /// Where a write this library's closed source would not take is told, with the text it carried. By then the
    /// windows read another library, so this one's `failure` would be shown nowhere. Set by the app; without it
    /// the library's own `failure` says so.
    @ObservationIgnored var onNotKept: ((NotKept) -> Void)?

    /// A write no queue holds, since the source had closed.
    nonisolated struct NotKept: Hashable, Sendable {
        var title: String
        var text: String?
    }

    /// A place's order changes only with what it holds, so a change to one item maps the items again without
    /// sorting them.
    private nonisolated struct Listing {
        var membership: Int
        var content = -1
        var ids: [ItemID]
        var items: [Item] = []
    }

    private nonisolated struct Refusal {
        var title: String
        /// What a create carried, which a closing source would otherwise lose.
        var text: String?
    }

    private nonisolated struct Replacement {
        var awaiting: Set<WriteID>
        var unlinks: [EdgeDraft]
    }

    private nonisolated struct Search {
        var revision: Int
        var hits: [ItemID]
        var running: Bool
    }

    /// Searches keep the items not in the bin, as the files library's do.
    static let searchScope = ItemQuery(states: [.active, .archived])

    init(source: any ConnectedItemSource, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
        syncReport = source.syncReport
        connection = MarfaHost.state(source.connectionState)
        let changes = source.changes()
        let reports = source.syncReports()
        let states = source.connectionStates()
        following = [
            Task { [weak self] in
                for await change in changes {
                    guard let self else { return }
                    await take(change)
                }
            },
            Task { [weak self] in
                for await report in reports { self?.syncReport = report }
            },
            Task { [weak self] in
                for await state in states { self?.connection = MarfaHost.state(state) }
            }
        ]
    }

    isolated deinit {
        for task in following { task.cancel() }
    }

    /// Purge needs the server, so it is offered only while the server can be reached. Moving, renaming files,
    /// folders and importing are a files library's: the package attaches a file to an item, and has no call that
    /// makes a file item of its own.
    var capabilities: SourceCapabilities {
        var offered = source.capabilities.intersection([.archive, .retype, .retier, .purge])
        if connection != .online { offered.remove(.purge) }
        return offered
    }

    /// The server keeps the bin, and its own rules for how long.
    var trashDays: Int? { nil }
    var folders: [Folder] { [] }
    var completedImports: [UUID: ItemID] { [:] }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        try await source.resolve(problem, by: action)
    }

    // MARK: Following the source

    private func take(_ change: SourceChange) async {
        switch change {
        case .loaded(let snapshot):
            let bodies = await readBodies(Set(snapshot.items.map(\.id)))
            load(snapshot, bodies: bodies)
        case .upserted(let items):
            // A body is read before an item whose version moved is shown, so the version and the text the page
            // reads agree; a local write keeps the version, and its text comes with `.bodyChanged`.
            let moved = items.filter { item in records[item.id].map { $0.item.version != item.version } ?? true }
            let bodies = moved.isEmpty ? [] : await readBodies(Set(moved.map(\.id)))
            upsert(items, bodies: bodies)
        case .removed(let ids):
            remove(ids)
        case .bodyChanged(let id, _):
            hold(await readBodies([id]))
        case .answered(let id, let outcome):
            await answered(id, outcome)
        case .catalogue(let catalogue):
            self.catalogue = catalogue
            reindex()
        case .places:
            // The sidebar's places are still the app's own; the source's are for when places drive it.
            break
        case .unavailable(let failure):
            self.failure = (String(localized: "Can’t Read This Library"), failure.message)
        }
    }

    private func readBodies(_ ids: Set<ItemID>) async -> [ItemBody] {
        do {
            return try await source.bodies(of: ids)
        } catch {
            failure = (String(localized: "Can’t Read This Library"), error.localizedDescription)
            return []
        }
    }

    /// Keeps the records the views already observe, so a second load tells each of them what changed.
    private func load(_ snapshot: SourceSnapshot, bodies: [ItemBody]) {
        catalogue = snapshot.catalogue
        let present = Set(snapshot.items.map(\.id))
        for (id, record) in records where !present.contains(id) {
            record.isHeld = false
            records[id] = nil
        }
        for item in snapshot.items {
            if let record = records[item.id] {
                if record.item != item { record.item = item }
            } else {
                records[item.id] = ItemRecord(item)
            }
        }
        hold(bodies)
        reindex()
        isLoaded = true
    }

    private func upsert(_ items: [Item], bodies: [ItemBody]) {
        var changed = false
        var moved = false
        for item in items {
            if let record = records[item.id] {
                let old = record.item
                guard old != item else { continue }
                index.remove(old)
                record.item = item
                index.insert(item, catalogue: catalogue)
                if Self.placesDiffer(old, item) { moved = true }
            } else {
                records[item.id] = ItemRecord(item)
                index.insert(item, catalogue: catalogue)
                moved = true
            }
            changed = true
        }
        hold(bodies)
        if changed { contentRevision += 1 }
        if moved { membershipRevision += 1 }
    }

    private func remove(_ ids: [ItemID]) {
        var changed = false
        for id in ids {
            guard let record = records.removeValue(forKey: id) else { continue }
            index.remove(record.item)
            record.isHeld = false
            changed = true
        }
        guard changed else { return }
        contentRevision += 1
        membershipRevision += 1
    }

    /// Text read while the person's own text is still on its way is older than what the library holds. Text
    /// taken in is a new read: the page follows `body(of:)` and shows it, so the next save starts from it, and
    /// where the server kept its own text over the person's, the page shows the server's.
    private func hold(_ bodies: [ItemBody]) {
        for body in bodies where unsettledText[body.id] == nil {
            guard let record = records[body.id], record.body != body else { continue }
            record.body = body
        }
    }

    private func reindex() {
        index = MarfaItemIndex()
        for record in records.values { index.insert(record.item, catalogue: catalogue) }
        contentRevision += 1
        membershipRevision += 1
    }

    private static func placesDiffer(_ old: Item, _ new: Item) -> Bool {
        old.state != new.state || old.tier != new.tier || old.tags != new.tags || old.type != new.type
            || old.edgesOut != new.edgesOut
    }

    private func answered(_ id: WriteID, _ outcome: WriteOutcome) async {
        let refusal = refusals.removeValue(forKey: id)
        let typed = textWrites[id].flatMap { item in lastTyped[item].flatMap { $0.write == id ? $0.text : nil } }
        if let item = textWrites[id], lastTyped[item]?.write == id { lastTyped[item] = nil }
        if case .refused(let problem) = outcome, let refusal {
            if problem.code == MarfaEngine.closedCode {
                notKept(refusal.title, text: typed ?? refusal.text)
            } else {
                failure = (refusal.title, problem.message ?? String(localized: "The Marfa server refused this change."))
            }
        }
        if let created = creating.removeValue(forKey: id), case .refused = outcome, records[created] == nil {
            refusedCreations.insert(created)
        }
        settleReplacement(id, outcome)
        guard let item = textWrites.removeValue(forKey: id) else { return }
        unsettledText[item]?.remove(id)
        guard unsettledText[item]?.isEmpty == true else { return }
        unsettledText[item] = nil
        // The server may have merged the text, or kept its own and put the person's on a copy.
        hold(await readBodies([item]))
    }

    // MARK: Writing through the source

    func awaitLinks(_ links: Set<WriteID>, thenUnlink unlinks: [EdgeDraft]) {
        let group = UUID()
        replacements[group] = Replacement(awaiting: links, unlinks: unlinks)
        for link in links { replacing[link] = group }
    }

    /// A link refused or held drops the removal, which leaves the old link beside any new one taken.
    private func settleReplacement(_ id: WriteID, _ outcome: WriteOutcome) {
        guard let group = replacing.removeValue(forKey: id), var replacement = replacements[group] else { return }
        switch outcome {
        case .accepted, .merged:
            replacement.awaiting.remove(id)
            guard replacement.awaiting.isEmpty else {
                replacements[group] = replacement
                return
            }
            replacements[group] = nil
            unlink(replacement.unlinks)
        case .conflicted, .refused, .blocked, .dead:
            replacements[group] = nil
            for link in replacement.awaiting { replacing[link] = nil }
        }
    }

    /// Every write the library makes goes through here, so a refusal reaches the person under `title`, as does
    /// a write made after the source closed, which nothing keeps.
    @discardableResult
    func submit(_ write: ItemWrite, failing title: String) -> WriteID {
        let id = WriteID()
        refusals[id] = Refusal(title: title, text: Self.createdText(write))
        if !source.submit(write, as: id) {
            refusals[id] = nil
            notKept(title, text: Self.typedText(write))
        }
        return id
    }

    /// Told where the person sees it, with the text they typed, since nothing else holds that text.
    private func notKept(_ title: String, text: String?) {
        if let onNotKept {
            onNotKept(NotKept(title: title, text: text))
        } else {
            failure = (title, MarfaEngine.notKept)
        }
    }

    private static func typedText(_ write: ItemWrite) -> String? {
        if case .editBody(_, let text, _, _) = write { return text }
        return createdText(write)
    }

    /// A draft refused while it waits is given back by the window that made it, unless that window has moved on.
    private static func createdText(_ write: ItemWrite) -> String? {
        guard case .create(_, let draft) = write else { return nil }
        return draft.body.isEmpty ? draft.title : draft.title + "\n\n" + draft.body
    }

    /// A create is followed to its answer, so one refused before the source holds the item gives its draft back.
    func submitCreate(_ id: ItemID, _ draft: ItemDraft, failing title: String) {
        let write = submit(.create(id: id, draft), failing: title)
        if refusals[write] != nil { creating[write] = id } else { refusedCreations.insert(id) }
    }

    /// The person's text, typed on the text the library gave at `readAt`. The first save typed on a version is
    /// merged against it where the copy has moved on; every later one follows the person's own, so their saves
    /// never come back conflicted against each other. Text typed on the text the library holds is held at once
    /// until the source answers. Text typed on older text, reported after the page took in newer text, is sent as
    /// made on what it was typed on (queue-and-verdicts 43), so the server keeps both rather than this text
    /// replacing what the person never saw, and the library goes on holding the newer text.
    func saveText(_ text: String, of id: ItemID, readAt: ItemVersion, failing title: String) {
        let held = records[id]?.body?.version ?? records[id]?.item.version ?? ItemVersion(0)
        let merge: BodyMerge = savedOn[id] == readAt ? .following : .asRead
        let write = submit(.editBody(id, text, base: readAt, merge: merge), failing: title)
        unsettledText[id, default: []].insert(write)
        textWrites[write] = id
        lastTyped[id] = (write, text)
        guard readAt == held else { return }
        savedOn[id] = readAt
        records[id]?.body = ItemBody(id: id, text: text, version: readAt)
    }

    // MARK: Reading

    func item(_ id: ItemID) -> Item? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        return record.isHeld ? record.item : nil
    }

    /// The items held among `ids`, observed as the lists are, for reads that gather many items at once.
    func heldItems(_ ids: some Sequence<ItemID>) -> [Item] {
        _ = contentRevision
        return ids.compactMap { records[$0]?.item }
    }

    func items(in place: SidebarItem) -> [Item] {
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[place], held.content == content { return held.items }
        var listing = listed[place].flatMap { $0.membership == membership ? $0 : nil }
            ?? Listing(membership: membership, ids: Self.ordered(members(of: place).compactMap { records[$0]?.item }).map(\.id))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listed[place] = listing
        return listing.items
    }

    func count(in place: SidebarItem) -> Int {
        let revision = membershipRevision
        if let held = counted[place], held.revision == revision { return held.count }
        let count = members(of: place).count
        counted[place] = (revision, count)
        return count
    }

    /// Newest first, as the source paints them; the views sort as the person chose.
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id.rawValue < $1.id.rawValue }
    }

    /// The Inbox is the feed tier. All Items is every active item in either tier, files among them, as All Notes
    /// is in a folder. A type's place holds its subtypes too.
    private func members(of place: SidebarItem) -> Set<ItemID> {
        switch place {
        case .inbox: return index.feed
        case .allNotes: return index.ids(in: .active)
        case .favorites: return index.favorites
        case .favoriteItem(let id): return index.favorites.contains(id) ? [id] : []
        case .itemType(let type): return active(ofType: TypeID(type))
        case .files: return active(ofType: MarfaMapping.fileType)
        case .project(let id):
            let active = index.ids(in: .active)
            return index.reachable(from: id, type: MarfaMapping.parentEdge).union([id]).intersection(active)
        case .recentlyDeleted: return index.ids(in: .trashed)
        case .folder, .marfaTypes: return []
        }
    }

    private func active(ofType type: TypeID) -> Set<ItemID> {
        catalogue.descendants(of: type).union([type]).reduce(into: Set<ItemID>()) { found, type in
            found.formUnion(index.activeByType[type] ?? [])
        }
    }

    func name(of place: SidebarItem) -> String {
        switch place {
        case .inbox: String(localized: "Inbox")
        case .allNotes: String(localized: "All Items")
        case .favorites: String(localized: "Favorites")
        case .favoriteItem(let id), .project(let id): item(id)?.title ?? ""
        case .folder: ""
        case .itemType(let type) where TypeID(type) == MarfaMapping.projectType: String(localized: "Projects")
        case .itemType(let type): catalogue.itemTypes[TypeID(type)]?.label ?? type
        case .files: String(localized: "Files")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .marfaTypes: String(localized: "Marfa Types")
        }
    }

    func folder(_ id: ItemID) -> Folder? { nil }
    func folder(of item: Item) -> Folder? { nil }

    func isGone(_ id: ItemID?) -> Bool {
        isLoaded && id.flatMap { item($0) } == nil
    }

    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID] {
        ids.filter { item($0) != nil }
    }

    func body(of id: ItemID) -> ItemBody? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        return record.isHeld ? record.body : nil
    }

    /// Marfa does not ask titles to differ.
    func isItemTitleTaken(_ title: String) -> Bool { false }
    func isNoteNameTaken(_ name: String, for id: ItemID) -> Bool { false }
    func isFolderNameTaken(_ name: String, except id: ItemID?) -> Bool { false }

    // MARK: Search

    /// Answers from the copy's own search, which runs beside the views: until it returns, the last results stand,
    /// and the views are told when the new ones arrive. A change to the items runs the search again.
    func items(matching query: String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        _ = searchRevision
        let revision = contentRevision
        let held = searches[query]
        if held.map({ $0.revision != revision && !$0.running }) ?? true { startSearch(query, at: revision) }
        return (held?.hits ?? lastFound).compactMap { id in
            records[id].flatMap { $0.isHeld && $0.item.state != .trashed ? $0.item : nil }
        }
    }

    /// A search that fails keeps the results already shown and says why, rather than showing that nothing was
    /// found; it is not asked again until the items change.
    private func startSearch(_ query: String, at revision: Int) {
        searches[query, default: Search(revision: revision, hits: [], running: true)].running = true
        searchOrder.removeAll { $0 == query }
        searchOrder.append(query)
        while searchOrder.count > 16 { searches[searchOrder.removeFirst()] = nil }
        Task { [weak self, source] in
            let found: Result<[ItemID], any Error>
            do {
                found = .success(try await source.search(query, in: Self.searchScope))
            } catch {
                found = .failure(error)
            }
            guard let self else { return }
            switch found {
            case .success(let hits):
                searches[query] = Search(revision: revision, hits: hits, running: false)
                lastFound = hits
            case .failure(let error):
                searches[query] = Search(revision: revision, hits: searches[query]?.hits ?? lastFound, running: false)
                failure = (String(localized: "Can’t Search"), error.localizedDescription)
            }
            searchRevision += 1
        }
    }

    // MARK: Files

    var folderURL: URL? { nil }
    /// A file's bytes come from the server's blobs, so they are never at hand without asking.
    func fileURL(for id: ItemID) -> URL? { nil }

    func fileURL(of id: ItemID) async throws -> URL? {
        guard item(id)?.isFile == true else { return nil }
        return try await source.fileURL(of: id)
    }

    func path(of id: ItemID) -> String? { nil }
    func fileName(of id: ItemID) -> String? { nil }
    func imageBase(of id: ItemID) -> String? { nil }
}
