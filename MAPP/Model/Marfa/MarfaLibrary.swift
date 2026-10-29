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
    /// Where the library tells the person what it could not do or keep: the host's, for every library it opens.
    @ObservationIgnored let notices: Notices
    /// Has every open page hand over its last edit, then says whether all of them did, so a change that moves an
    /// item's text moves what the person sees.
    @ObservationIgnored var handOverEdits: (@escaping (Bool) -> Void) -> Void = { EditorController.flushAll(leaving: false, then: $0) }
    var notesToPurge: Set<ItemID> = []
    private(set) var catalogue = Catalogue()
    private(set) var views: [LibraryView] = []
    private(set) var syncReport: SyncReport
    var downloadedFiles: (any DownloadedFiles)? { source.downloadedFiles }
    /// How the server stands, for the app to show beside the library.
    private(set) var connection: MarfaHost.State
    let now: () -> Date

    /// Bumped when any item changes, for the lists and search.
    private(set) var contentRevision = 0
    /// Bumped only when an item comes, goes or changes which places hold it, for the counts.
    private var membershipRevision = 0
    /// Bumped when an edge comes, goes or changes, and when the index is built again, which is all that changes what
    /// points at an item. A read of
    /// an item's relationships follows this and the records of the items it names, never `contentRevision`.
    private(set) var linksRevision = 0
    private var searchRevision = 0
    private var viewRevision = 0

    @ObservationIgnored let source: any ItemSource
    /// Reads an item's earlier versions from the server, which the copy does not hold. Nil where there is no server
    /// to ask, as in the sample library.
    @ObservationIgnored let history: (any ItemHistorySource)?
    /// Keeps the owner's choice of a type's icon on the server. Nil where there is no server to ask.
    @ObservationIgnored let typeIcons: (any TypeIconSource)?
    /// The icon each type last showed after the person chose one, until the working copy's own catalogue shows the type
    /// with another icon than it had when the person chose, since the copy takes a schema change only when its stream
    /// reopens. `before` is the icon the copy showed then.
    @ObservationIgnored private var chosenIcons: [TypeID: (icon: String?, before: String?)] = [:]
    /// The catalogue the working copy last reported, without the chosen icons.
    @ObservationIgnored private var readCatalogue = Catalogue(itemTypes: [])
    @ObservationIgnored private var records: [ItemID: ItemRecord] = [:]
    @ObservationIgnored private(set) var index = MarfaItemIndex()
    @ObservationIgnored private var listed: [SidebarItem: Listing] = [:]
    @ObservationIgnored private var counted: [SidebarItem: (revision: Int, count: Int)] = [:]
    @ObservationIgnored private var searches: [SearchKey: SearchRun] = [:]
    @ObservationIgnored private var searchOrder: [SearchKey] = []
    /// What the last search to finish found, shown while the next one runs so the list does not empty per key. Its
    /// excerpts are left out, since they quote another search's words.
    @ObservationIgnored private var lastFound: [ItemID] = []
    /// What each view last listed, read from the copy beside the views as a search is.
    @ObservationIgnored private var viewed: [ItemID: Search] = [:]
    /// Views whose list could not be read, told once until one is read again.
    @ObservationIgnored private var viewsFailing: Set<ItemID> = []
    /// Bumped when the views change, so a read begun before is dropped.
    @ObservationIgnored private var viewsGeneration = 0
    /// Text writes the source has not answered, by item. While any wait, the text the person gave is what the
    /// library holds, since a read that raced the write could give older text.
    @ObservationIgnored private var unsettledText: [ItemID: Set<WriteID>] = [:]
    /// Each of those writes, until the source answers it.
    @ObservationIgnored private var textWrites: [WriteID: TextWrite] = [:]
    /// What the copy holds of each item's text while the person's own text is unsettled, held once it settles: the
    /// text before the first save, the typed text of each save the copy took, or a body the source told after.
    @ObservationIgnored private var sourceText: [ItemID: ItemBody] = [:]
    /// From the person's text being submitted to the engine having taken or answered it.
    @ObservationIgnored private var textSaves: [WriteID: Telemetry.Interval] = [:]
    /// Text writes the copy has not yet taken and read back, by item, so what it bound in the text may be older.
    @ObservationIgnored private var unreadText: [ItemID: Set<WriteID>] = [:]
    /// The version of the text the person's last save of each item was typed on. Only the first save typed on a
    /// version is merged against it; the rest follow the person's own.
    @ObservationIgnored private var savedOn: [ItemID: ItemVersion] = [:]
    /// Links removed only once the source has taken the links added in their place, by the link writes awaited.
    @ObservationIgnored private var replacements: [UUID: Replacement] = [:]
    @ObservationIgnored private var replacing: [WriteID: UUID] = [:]
    /// The undo or redo whose handler is making writes now, and the one each write that may be held belongs to
    /// (`MarfaLibrary+Undoing`).
    @ObservationIgnored var undoRun: UndoRun?
    @ObservationIgnored private var undoRuns: [WriteID: UndoRun] = [:]
    /// What to tell the person if the source refuses each write the library made.
    @ObservationIgnored private var refusals: [WriteID: Refusal] = [:]
    @ObservationIgnored private var following: [Task<Void, Never>] = []
    /// The item each create names, until the source answers it.
    @ObservationIgnored private var creating: [WriteID: ItemID] = [:]
    /// Creates the source refused before it held the item, such as one made while the copy is brought up to date,
    /// so the window has no item to open and gives the New up.
    private(set) var refusedCreations: Set<ItemID> = []
    /// Why text typed over an item that can no longer be written is not kept.
    static var cantChange: String {
        String(localized: "This item can’t be changed now, so MAPP couldn’t keep what you typed.")
    }

    /// A place's order changes only with what it holds, so a change to one item maps the items again without
    /// sorting them.
    private nonisolated struct Listing {
        var membership: Int
        var content = -1
        var ids: [ItemID]
        var items: [Item] = []
    }

    /// A text save the source has not answered.
    private nonisolated struct TextWrite {
        let item: ItemID
        /// The text the save put on the page, until the copy takes the save. None where the person typed on older
        /// text, which left the page as it was.
        var shown: ItemBody?
        /// What the person typed, so text a closing source refuses can be given back to them. Only the item's last
        /// save keeps it, since that holds everything typed before it.
        var typed: String?
    }

    private nonisolated struct Refusal {
        var title: String
        /// What the write carried, which a closing source would otherwise lose.
        var text: String?
        /// What the person typed into the write, which a refusal before queueing would otherwise lose
        /// (`unqueuedText(_:)`).
        var unqueuedText: String?
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

    private nonisolated struct SearchKey: Hashable {
        var query: String
        var scope: SearchScope

        var isOfView: Bool {
            if case .place(.view) = scope { true } else { false }
        }
    }

    private nonisolated struct SearchRun {
        var revision: Int
        var found = SourceSearch()
        var running: Bool
        /// Whether the copy has answered this search yet.
        var answered = false
        /// How the copy was filling when the search was asked. A search that found the copy incomplete is asked
        /// again when this has changed, since the copy may be whole now, and not before, since a copy that stays
        /// stale (offline, say) would otherwise be searched again and again.
        var fill: LibraryFill?
    }

    /// Searches keep the items not in the bin.
    static let searchScope = ItemQuery(states: [.active, .archived])

    init(
        source: any ItemSource, notices: Notices, history: (any ItemHistorySource)? = nil,
        typeIcons: (any TypeIconSource)? = nil, now: @escaping () -> Date = Date.init,
        didSync: @escaping (Date) -> Void = { _ in }) {
        self.source = source
        self.history = history
        self.typeIcons = typeIcons
        self.notices = notices
        self.now = now
        syncReport = source.syncReport
        connection = MarfaHost.state(source.connectionState)
        let changes = source.changes()
        let reports = source.syncReports()
        let states = source.connectionStates()
        let first = syncReport.lastSynced
        following = [
            Task { [weak self] in
                for await change in changes {
                    guard let self else { return }
                    await take(change)
                }
            },
            Task { [weak self] in
                var synced = first
                for await report in reports {
                    self?.syncReport = report
                    if let date = report.lastSynced, date != synced { didSync(date) }
                    synced = report.lastSynced
                }
            },
            Task { [weak self] in
                for await state in states { self?.connection = MarfaHost.state(state) }
            }
        ]
    }

    isolated deinit {
        for task in following { task.cancel() }
    }

    /// Purge needs the server, so it is offered only while the server can be reached.
    var canPurge: Bool { connection == .online }

    /// A view is written through the server at once, so it can be only while the server can be reached.
    var canEditViews: Bool { connection == .online }

    /// Whether a type's icon can be chosen: it is kept on the server, so only while the server can be reached.
    var canChooseTypeIcons: Bool { typeIcons != nil && connection == .online }

    func setIcon(_ icon: String?, ofType type: TypeID) async -> TypeIconFailure? {
        guard let typeIcons else { return .unsupported }
        do {
            let shown = try await typeIcons.setIcon(icon, ofType: type)
            chosenIcons[type] = (shown, readCatalogue.itemTypes[type]?.icon)
            catalogue = catalogue.choosingIcon(shown, ofType: type)
            reindex()
            return nil
        } catch {
            return error
        }
    }

    /// The catalogue the copy read, with the icons the person has chosen since. A choice ends once the copy shows the
    /// type with a different icon than it did at the choice, whether the chosen one or one another app set.
    private func holdingChosenIcons(_ read: Catalogue) -> Catalogue {
        readCatalogue = read
        var held = read
        for (type, choice) in chosenIcons {
            if read.itemTypes[type]?.icon != choice.before {
                chosenIcons[type] = nil
            } else {
                held = held.choosingIcon(choice.icon, ofType: type)
            }
        }
        return held
    }

    func createView(_ settings: LibraryViewSettings) async -> LibraryView? {
        let result = await writingView(.create(settings), failing: String(localized: "Can’t Save View")) { [source] key in
            try await source.createView(settings, idempotencyKey: key)
        }
        guard case .success(let view) = result else { return nil }
        hold(view)
        return view
    }

    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure> {
        let renames = change.title != nil && change.query == nil && change.sort == nil && change.group == nil
        let title = renames ? String(localized: "Can’t Rename View") : String(localized: "Can’t Update View")
        let result = await writingView(.change(view, change, baseVersion), failing: title) { [source] key in
            try await source.changeView(view, change, baseVersion: baseVersion, idempotencyKey: key)
        }
        switch result {
        case .success(let changed): hold(changed)
        // The copy keeps what it held, so the server is asked again for what changed.
        case .failure(let failure) where failure.kind == .conflict: source.refresh()
        case .failure: break
        }
        return result
    }

    func deleteView(_ view: ItemID) async -> Bool {
        let result = await writingView(.delete(view), failing: String(localized: "Can’t Delete View")) { [source] key in
            try await source.deleteView(view, idempotencyKey: key)
        }
        guard case .success = result else { return false }
        take(views.filter { $0.id != view })
        return true
    }

    /// What the server answered is shown at once, before the copy's own word arrives.
    private func hold(_ view: LibraryView) {
        take(LibraryView.ordered(views.filter { $0.id != view.id } + [view]))
    }

    /// The idempotency key of each write that failed for want of the server, so trying it again cannot make it twice
    /// where the server took it before the answer was lost.
    @ObservationIgnored private var viewWriteKeys: [ViewWrite: String] = [:]

    private enum ViewWrite: Hashable {
        case create(LibraryViewSettings)
        case change(ItemID, LibraryViewChange, Int64)
        case delete(ItemID)
    }

    private func writingView<Value>(
        _ write: ViewWrite, failing title: String, _ send: (String) async throws -> Value
    ) async -> Result<Value, ViewWriteFailure> {
        let key = viewWriteKeys[write] ?? UUID().uuidString
        do {
            let value = try await send(key)
            viewWriteKeys[write] = nil
            return .success(value)
        } catch {
            let failure = error as? ViewWriteFailure ?? ViewWriteFailure(kind: .refused, message: error.localizedDescription)
            viewWriteKeys[write] = failure.kind == .offline ? key : nil
            notices.tell(title, failure.message)
            return .failure(failure)
        }
    }

    /// The server keeps the bin, and its own rules for how long.
    var trashDays: Int? { nil }

    /// The favorite tag, which the Favorite command owns, and the tag the server puts on a conflicted copy, which
    /// stays until the person keeps or bins the copy.
    var reservedTags: Set<String> { [ItemTag.favorite, MarfaProblems.conflictedCopyTag] }

    var knownTags: [String] {
        index.tagCounts.filter { !reservedTags.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.key)
    }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        try await source.resolve(problem, by: action)
    }

    // MARK: Following the source

    private func take(_ change: SourceChange) async {
        let interval = Telemetry.begin(.library, change.kind, ("items", change.itemCount))
        defer { interval.end() }
        switch change {
        case .loaded(let snapshot):
            load(snapshot)
        case .changed(let changes):
            take(changes)
        case .answered(let id, let outcome):
            textSaves.removeValue(forKey: id)?.end()
            read(id)
            answered(id, outcome)
        case .taken(let id):
            textSaves.removeValue(forKey: id)?.end()
            took(id)
            read(id)
        case .catalogue(let catalogue):
            self.catalogue = holdingChosenIcons(catalogue)
            reindex()
        case .views(let views):
            take(views)
        case .unavailable(let failure):
            // The window keeps showing the library while its copy is open, so a refused key is told with the way
            // to Settings, where the key is replaced or the library disconnected.
            if failure.kind == .denied {
                notices.tell(String(localized: "Marfa Server Doesn’t Accept Your Key"), failure.message, action: .openSettings(.library))
            } else {
                notices.tell(String(localized: "Can’t Read This Library"), failure.message)
            }
        }
    }

    /// Keeps the records the views already observe, so a second load tells each of them what changed.
    private func load(_ snapshot: SourceSnapshot) {
        catalogue = holdingChosenIcons(snapshot.catalogue)
        take(snapshot.views)
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
        hold(Array(snapshot.bodies.values))
        reindex()
        isLoaded = true
        LaunchTrace.shared.mark(.firstLoaded)
    }

    /// One step of the source, taken in at once, so each revision moves at most once for it.
    private func take(_ changes: ItemChanges) {
        var changed = false
        var moved = false
        var relinked = false
        for id in changes.removed {
            guard let record = records.removeValue(forKey: id) else { continue }
            index.remove(record.item)
            record.isHeld = false
            changed = true
            moved = true
            if !record.item.edgesOut.isEmpty { relinked = true }
        }
        for item in changes.upserted {
            if let record = records[item.id] {
                let old = record.item
                guard old != item else { continue }
                index.remove(old)
                record.item = item
                index.insert(item, catalogue: catalogue)
                if Self.placesDiffer(old, item) { moved = true }
                if old.edgesOut != item.edgesOut { relinked = true }
            } else {
                records[item.id] = ItemRecord(item)
                index.insert(item, catalogue: catalogue)
                moved = true
                if !item.edgesOut.isEmpty { relinked = true }
            }
            changed = true
        }
        hold(changes.bodies)
        if changed { contentRevision += 1 }
        if moved { membershipRevision += 1 }
        if relinked { linksRevision += 1 }
    }

    /// Text read while the person's own text is still on its way is older than what the library holds. Text
    /// taken in is a new read: the page follows `body(of:)` and shows it, so the next save starts from it, and
    /// where the server kept its own text over the person's, the page shows the server's.
    private func hold(_ bodies: [ItemBody]) {
        for body in bodies {
            guard unsettledText[body.id] == nil else {
                sourceText[body.id] = body
                continue
            }
            guard let record = records[body.id], record.body != body else { continue }
            record.body = body
        }
    }

    /// A view changed elsewhere may list other items, so its last list is dropped. The others keep theirs until
    /// read again, since a read begun before is dropped.
    private func take(_ views: [LibraryView]) {
        let current = Set(views)
        viewed = viewed.filter { id, _ in self.views.contains { $0.id == id && current.contains($0) } }
            .mapValues { Search(revision: -1, hits: $0.hits, running: false) }
        // A search of a view lists what the view held, which may have changed.
        for key in searches.keys where key.isOfView { searches[key]?.revision = -1 }
        if self.views != views { self.views = views }
        viewsGeneration += 1
        viewsFailing.formIntersection(views.map(\.id))
        viewRevision += 1
    }

    private func reindex() {
        let interval = Telemetry.begin(.library, "reindex", ("items", records.count))
        defer { interval.end() }
        index = MarfaItemIndex()
        for record in records.values { index.insert(record.item, catalogue: catalogue) }
        contentRevision += 1
        membershipRevision += 1
        linksRevision += 1
    }

    private static func placesDiffer(_ old: Item, _ new: Item) -> Bool {
        old.state != new.state || old.tier != new.tier || old.tags != new.tags || old.type != new.type
            || old.edgesOut != new.edgesOut
    }

    private func answered(_ id: WriteID, _ outcome: WriteOutcome) {
        let refusal = refusals.removeValue(forKey: id)
        let textWrite = textWrites.removeValue(forKey: id)
        let typed = textWrite?.typed
        let run = undoRuns.removeValue(forKey: id)
        if case .refused(let problem) = outcome, let run, MarfaEngine.isHeldRefusal(problem.code) {
            giveBack(run, problem, title: refusal?.title, text: typed ?? refusal?.text)
        } else if case .refused(let problem) = outcome, let refusal {
            let message = problem.message ?? String(localized: "The Marfa server refused this change.")
            if problem.code == MarfaEngine.closedCode {
                notices.notKept(refusal.title, text: typed ?? refusal.text)
            } else if problem.notQueued, let text = typed ?? refusal.unqueuedText {
                // Nothing queued it, so the text is in no write the person could copy it from, and the page is
                // about to show the text the library holds.
                notices.notKept(refusal.title, text: text, reason: message)
            } else if let typed {
                // The refused write stays listed, but the page is about to show the text the library holds.
                notices.notKept(refusal.title, text: typed, reason: String(localized: "\(message) The change is also listed in Settings."))
            } else {
                notices.tell(refusal.title, message)
            }
        }
        if let created = creating.removeValue(forKey: id), case .refused = outcome, records[created] == nil {
            refusedCreations.insert(created)
        }
        settleReplacement(id, outcome)
        guard let item = textWrite?.item else { return }
        unsettledText[item]?.remove(id)
        guard unsettledText[item]?.isEmpty == true else { return }
        unsettledText[item] = nil
        // The server may have merged the text, or kept its own and put the person's on a copy: the source tells
        // what the copy holds in the change that follows the answer, and this is what it held before that.
        if let body = sourceText.removeValue(forKey: item) { hold([body]) }
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
        let unqueued = Self.unqueuedText(write)
        let refusal = Refusal(title: title, text: unqueued ?? Self.createdText(write), unqueuedText: unqueued)
        refusals[id] = refusal
        if let run = undoRun { undoRuns[id] = run }
        if !source.submit(write, as: id, undoing: undoRun?.group) {
            refusals[id] = nil
            undoRuns[id] = nil
            notices.notKept(title, text: refusal.text)
        }
        return id
    }

    /// The text the person typed into a write, which nothing else holds once the package refuses it before queueing:
    /// a body, a create's title, body and text values, since the person typed them in quick add, a tag, and the text values
    /// of a property edit, a title among them, or of a change of type, the values typed in its sheet among them.
    private static func unqueuedText(_ write: ItemWrite) -> String? {
        switch write {
        case .editBody(_, let text, _, _):
            return text
        case .create:
            return createdText(write)
        case .editProperties(_, let changes, _, _), .retype(_, _, let changes, _):
            let texts = changes.sorted { $0.key < $1.key }.compactMap { $0.value?.string }
            return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        case .tag(_, let tag, on: true) where tag != ItemTag.favorite:
            return tag
        default:
            return nil
        }
    }

    /// The text a create holds, its title, body and text values, which a source that closes before it answers
    /// gives back to the person.
    private static func createdText(_ write: ItemWrite) -> String? {
        guard case .create(_, let draft) = write else { return nil }
        let values = draft.properties.sorted { $0.key < $1.key }.compactMap { $0.value.string }
        return ([draft.title, draft.body] + values).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A create is followed to its answer, so one refused before the source holds the item is told to the window that made it.
    func submitCreate(_ id: ItemID, _ draft: ItemDraft, failing title: String) {
        let write = submit(.create(id: id, draft), failing: title)
        if refusals[write] != nil { creating[write] = id } else { refusedCreations.insert(id) }
    }

    /// The person's text, typed on the text the library gave at `readAt`. The first save typed on a version is merged
    /// against it where the copy has moved on; every later one follows the person's own, so their saves never come back
    /// conflicted against each other. Text typed on the text the library holds is held at once until the source
    /// answers. Text typed on older text, reported after the page took in newer text, is sent as made on what it was
    /// typed on (`queue-and-verdicts/as-read-sent-on-read`), so the server keeps both rather than this text replacing
    /// what the person never saw, and the library goes on holding the newer text.
    func saveText(_ text: String, of id: ItemID, readAt: ItemVersion, failing title: String) {
        let held = records[id]?.body?.version ?? records[id]?.item.version ?? ItemVersion(0)
        let readAt = ItemVersion(MarfaEngine.version(read: readAt.rawValue, holding: held.rawValue))
        // A save held on a local create's version 0 is on version 1 once the answer lands, as `readAt` now is.
        let saved = savedOn[id].map { ItemVersion(MarfaEngine.version(read: $0.rawValue, holding: held.rawValue)) }
        let merge: BodyMerge = saved == readAt ? .following : .asRead
        let saving = Telemetry.begin(.library, "text.save")
        let write = submit(.editBody(id, text, base: readAt, merge: merge), failing: title)
        let shown = readAt == held ? ItemBody(id: id, text: text, version: readAt) : nil
        // Every write the engine takes ends in `.taken` or `.answered`; only one the source refuses to take, as it
        // has closed, gets neither, so nothing waits on it.
        if refusals[write] != nil {
            // Until a write is taken, the copy holds the text it held before, which a save refused before queueing
            // leaves on the page.
            if unsettledText[id] == nil { sourceText[id] = records[id]?.body }
            for earlier in unsettledText[id] ?? [] { textWrites[earlier]?.typed = nil }
            unsettledText[id, default: []].insert(write)
            unreadText[id, default: []].insert(write)
            textWrites[write] = TextWrite(item: id, shown: shown, typed: text)
            textSaves[write] = saving
        } else {
            saving.end()
        }
        guard let shown else { return }
        savedOn[id] = readAt
        records[id]?.body = shown
    }

    /// The copy holds the text the person typed once it takes their write, so text told before is older: the page
    /// keeps the typed text at the answer unless a read after the write tells the copy's.
    private func took(_ write: WriteID) {
        guard let shown = textWrites[write]?.shown else { return }
        textWrites[write]?.shown = nil
        sourceText[shown.id] = shown
    }

    // MARK: Reading

    func hasUnreadSave(_ id: ItemID) -> Bool {
        unreadText[id] != nil
    }

    /// A write answered before the copy took it, as one refused, is read too: nothing more will come of it.
    private func read(_ write: WriteID) {
        guard let item = textWrites[write]?.item, unreadText[item]?.remove(write) != nil, unreadText[item]?.isEmpty == true
        else { return }
        unreadText[item] = nil
    }

    func item(_ id: ItemID) -> Item? {
        guard let record = records[id] else {
            _ = membershipRevision
            return nil
        }
        return record.isHeld ? record.item : nil
    }

    /// A file's bytes are named by facts the server sets, which the inspector shows as its kind and size.
    func hiddenPropertyKeys(of item: Item) -> Set<String> {
        let keys = catalogue.pageKeys(of: item)
        return item.isFile ? keys.union(MarfaMapping.fileFacts) : keys
    }

    /// The items held among `ids`, observed as the lists are, for reads that gather many items at once.
    func heldItems(_ ids: some Sequence<ItemID>) -> [Item] {
        _ = contentRevision
        return ids.compactMap { records[$0]?.item }
    }

    func items(in place: SidebarItem) -> [Item] {
        if case .view(let id) = place { return items(inView: id) }
        let content = contentRevision
        let membership = membershipRevision
        if let held = listed[place], held.content == content { return held.items }
        // Which items are recent, and in what order, changes with any edit, not only with membership; so does a
        // collection's order, which falls back on titles.
        let isCollection: Bool = if case .collection = place { true } else { false }
        var listing = listed[place].flatMap { $0.membership == membership && place != .recents && !isCollection ? $0 : nil }
            ?? Listing(membership: membership, ids: listingOrder(of: place))
        listing.content = content
        listing.items = listing.ids.compactMap { records[$0]?.item }
        listed[place] = listing
        return listing.items
    }

    func count(in place: SidebarItem) -> Int {
        if place == .recents { return min(index.ids(in: .active).count, Self.recentLimit) }
        if case .view = place { return items(in: place).count }
        let revision = membershipRevision
        if let held = counted[place], held.revision == revision { return held.count }
        let count = members(of: place).count
        counted[place] = (revision, count)
        return count
    }

    private func listingOrder(of place: SidebarItem) -> [ItemID] {
        switch place {
        case .recents: Self.recent(index.ids(in: .active).compactMap { records[$0]?.item }).map(\.id)
        case .collection(let id): membersInOrder(of: id, among: members(of: place).compactMap { records[$0]?.item })
        default: Self.ordered(members(of: place).compactMap { records[$0]?.item }).map(\.id)
        }
    }

    /// Newest first, as the source paints them; the views sort as the person chose.
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id.rawValue < $1.id.rawValue }
    }

    /// The Inbox is the feed tier. All Items is every active item in either tier, files among them. A type's place holds that type's own items and no subtype's, so the sidebar's count is the list's length.
    private func members(of place: SidebarItem) -> Set<ItemID> {
        switch place {
        case .inbox: return index.feed
        case .allNotes: return index.ids(in: .active)
        case .sources, .collections: return []
        case .source(let name):
            return Set(index.ids(in: .active).filter { records[$0]?.item.source == name })
        // Listed in its own order by `items(in:)` and counted by its limit, so never read here.
        case .recents: return []
        // Read from the copy by `items(inView:)`, so never read here.
        case .view: return []
        case .favorites: return index.favorites
        case .favoriteItem(let id): return index.favorites.contains(id) ? [id] : []
        case .itemType(let type): return index.activeByType[TypeID(type)] ?? []
        case .files: return active(withSubtypesOf: MarfaMapping.fileType)
        // The active items filed in the collection through `in-collection`.
        case .collection(let id):
            return Set(index.links(to: id, type: MarfaMapping.collectionEdge).map(\.source)).intersection(index.ids(in: .active))
        case .recentlyDeleted: return index.ids(in: .trashed)
        }
    }

    private func active(withSubtypesOf type: TypeID) -> Set<ItemID> {
        catalogue.descendants(of: type).union([type]).reduce(into: Set<ItemID>()) { found, type in
            found.formUnion(index.activeByType[type] ?? [])
        }
    }

    func name(of place: SidebarItem) -> String {
        switch place {
        case .inbox: String(localized: "Inbox")
        case .recents: String(localized: "Recents")
        case .allNotes: String(localized: "Items")
        case .sources: String(localized: "Sources")
        case .collections: String(localized: "Collections")
        case .source(let name): name
        case .favorites: String(localized: "Favorites")
        case .favoriteItem(let id), .collection(let id): item(id)?.title ?? ""
        case .itemType(let type): catalogue.itemTypes[TypeID(type)]?.label ?? type
        case .files: String(localized: "Files")
        case .view(let id): views.first { $0.id == id }?.title ?? ""
        case .recentlyDeleted: String(localized: "Recently Deleted")
        }
    }

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

    // MARK: Links

    /// A link names what the copy bound that very link to when the note was saved (`Item.boundLinks`, the package's
    /// own answer): Marfa binds each spelling on its own and keeps the first note a spelling was bound to, so two
    /// links to one name can name two notes. An identity names the item that holds it, whatever other items are
    /// titled (`device/body-link-id-first`). A link the copy has not bound, as one just typed, or has not been able
    /// to look up is `pending`, never guessed from the titles held, since the server may hold another note with that
    /// title; it opens once the copy binds it.
    func resolveLink(_ link: NoteLink, in source: ItemID) -> NoteReferenceResolution {
        guard !link.lookupName.isEmpty else { return .missing }
        if NoteLinks.looksLikeIdentity(link.lookupName), let held = item(ItemID(link.lookupName)) { return Self.named(held) }
        guard let bound = item(source)?.boundLinks.first(where: { $0.link == link }) else { return .pending }
        guard case .resolved(let id) = bound.resolution else { return bound.resolution }
        return item(id).map(Self.named) ?? .pending
    }

    /// An item in the bin is not a note a link names.
    private static func named(_ item: Item) -> NoteReferenceResolution {
        item.state == .trashed ? .missing : .resolved(item.id)
    }

    // MARK: Search

    /// Answers from the copy's own search, which runs beside the views: until it returns, the last results stand,
    /// and the views are told when the new ones arrive. A change to the items runs the search again, and so does
    /// a change in how the copy is filling after a search that found it incomplete, so the notice follows the
    /// latest answer.
    func search(_ query: String, in scope: SearchScope) -> SearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .none }
        _ = searchRevision
        let key = SearchKey(query: query, scope: scope)
        let revision = contentRevision
        let fill = syncReport.fill
        let held = searches[key]
        let outdated = held.map { run in
            !run.running && (run.revision != revision || (run.found.isIncomplete && run.fill != fill))
        } ?? true
        if outdated { startSearch(key, at: revision, fill: fill) }
        let answered = held?.answered ?? false
        let ids = answered ? held?.found.hits ?? [] : lastFound
        var results = SearchResults(isIncomplete: held?.found.isIncomplete ?? false, isCapped: held?.found.isCapped ?? false)
        results.isPending = !answered
        for id in ids {
            guard let record = records[id], record.isHeld, record.item.state != .trashed else { continue }
            results.items.append(record.item)
            // An excerpt quotes the item as it was searched, so one for an item since edited would show text that
            // is no longer there.
            if answered, let excerpt = held?.found.excerpts[id], excerpt.describes(record.item) { results.excerpts[id] = excerpt }
        }
        return results
    }

    /// The copy's way of narrowing to a place or a view, or nil where the place stands for no query: the search
    /// then covers everything, as `SearchScope.narrows` says.
    private func target(for scope: SearchScope) -> SearchTarget {
        guard case .place(let place) = scope, SearchScope.narrows(place) else { return .items(Self.searchScope) }
        if case .view(let id) = place, views.contains(where: { $0.id == id }) { return .view(id) }
        guard let query = ViewDraft.query(for: place, catalogue: catalogue, views: views) else { return .items(Self.searchScope) }
        let narrowed = ItemQuery(
            types: Set(query.types), beneath: query.beneath, states: query.states ?? [], tier: query.tier)
        return .items(narrowed, filter: query.filter)
    }

    /// A search that fails keeps the results already shown for the same words and place and says why, rather than
    /// showing that nothing was found, and shows nothing where it has none; it is not asked again until the items
    /// change.
    private func startSearch(_ key: SearchKey, at revision: Int, fill: LibraryFill?) {
        searches[key, default: SearchRun(revision: revision, running: true, fill: fill)].running = true
        searchOrder.removeAll { $0 == key }
        searchOrder.append(key)
        while searchOrder.count > 16 { searches[searchOrder.removeFirst()] = nil }
        let target = target(for: key.scope)
        Task { [weak self, source] in
            let found: Result<SourceSearch, any Error>
            do {
                found = .success(try await source.search(key.query, in: target))
            } catch {
                found = .failure(error)
            }
            guard let self else { return }
            switch found {
            case .success(let result):
                searches[key] = SearchRun(revision: revision, found: result, running: false, answered: true, fill: fill)
                lastFound = result.hits
            case .failure(let error):
                // Only this search's own earlier answer is kept; another's hits would be shown as this one's. A failure
                // says nothing of completeness, so the notice follows how the copy stands now.
                var kept = searches[key].flatMap { $0.answered ? $0.found : nil } ?? SourceSearch()
                kept.isIncomplete = syncReport.fill.map { $0.state != .complete } ?? false
                searches[key] = SearchRun(revision: revision, found: kept, running: false, answered: true, fill: fill)
                notices.tell(String(localized: "Can’t Search"), error.localizedDescription)
            }
            searchRevision += 1
        }
    }

    // MARK: Views

    /// Answers from the copy's own reading of the view, which runs beside the views as a search does: until it
    /// returns, the last list stands, and a change to the items reads it again. The list is what the copy holds.
    private func items(inView id: ItemID) -> [Item] {
        _ = viewRevision
        let revision = contentRevision
        let held = viewed[id]
        if views.contains(where: { $0.id == id }), held.map({ $0.revision != revision && !$0.running }) ?? true {
            startViewRead(id, at: revision)
        }
        return Self.ordered((held?.hits ?? []).compactMap { id in
            records[id].flatMap { $0.isHeld && $0.item.state != .trashed ? $0.item : nil }
        })
    }

    /// A view the copy cannot answer, such as one asking for a type it does not hold, keeps what it last listed
    /// and says why once, rather than at every change; it is not asked again until the items change.
    private func startViewRead(_ id: ItemID, at revision: Int) {
        viewed[id, default: Search(revision: revision, hits: [], running: true)].running = true
        let generation = viewsGeneration
        Task { [weak self, source] in
            let found: Result<[ItemID], any Error>
            do {
                found = .success(try await source.items(inView: id))
            } catch {
                found = .failure(error)
            }
            // The views changed while it ran, so what it read may be of a view since changed.
            guard let self, viewsGeneration == generation else { return }
            switch found {
            case .success(let hits):
                viewed[id] = Search(revision: revision, hits: hits, running: false)
                viewsFailing.remove(id)
            case .failure(let error):
                viewed[id] = Search(revision: revision, hits: viewed[id]?.hits ?? [], running: false)
                if viewsFailing.insert(id).inserted {
                    notices.tell(String(localized: "Can’t Show This View"), error.localizedDescription)
                }
            }
            viewRevision += 1
        }
    }

    // MARK: Files

    /// A file's bytes come from the server's blobs, so they are never at hand without asking.
    func fileURL(of id: ItemID) async throws -> URL? {
        guard item(id)?.isFile == true else { return nil }
        return try await source.fileURL(of: id)
    }

    func attachments(of id: ItemID) -> [ItemID] {
        // The index is not observed. A file attached or taken off changes an edge; a change to the file itself is
        // followed through its own record, which a reader of the list reads with `item(_:)`.
        _ = linksRevision
        return index.links(to: id, type: MarfaMapping.attachmentEdge).map(\.source)
    }
}
