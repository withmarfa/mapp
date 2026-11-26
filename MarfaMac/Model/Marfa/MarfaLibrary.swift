import Foundation
import Observation

/// One item as the views read it, observed on its own, so a change to one item redraws only what shows it.
///
/// The item and its text are stored whole. A page header does not follow either: it follows `headerStamp` and
/// `textIsEmpty`, which move only when something the header shows changes. A keystroke that leaves the text
/// non-empty, or a publish that moves only the version, preview, sync or bound embeds, does not.
@Observable final class ItemRecord {
    var item: Item {
        get {
            access(keyPath: \.item)
            return listedItem
        }
        set {
            withMutation(keyPath: \.item) {
                let before = listedItem
                listedItem = newValue
                noteShown(before)
            }
        }
    }
    /// Bulk reads already follow the library's content revision.
    @ObservationIgnored private(set) var listedItem: Item
    /// Nil for an item with no text, and until its text is read.
    var body: ItemBody? { didSet { noteText() } }
    /// False once the source no longer holds the item, which tells the views that read only this record.
    var isHeld = true
    /// Changes only when the text becomes empty or not. Missing text counts as empty.
    private(set) var textIsEmpty = true
    /// Changes only when the text arrives or goes, which is not the same as becoming empty.
    private(set) var hasBody = false
    /// Changes when a field the page header shows changes, not when only the version, preview, sync or embeds move.
    private(set) var headerStamp = 0
    /// Changes only when `version` changes. The panel's Version fact follows this, not the whole item.
    private(set) var versionStamp = 0
    /// Changes when an edge touching this item comes, goes or changes, including one another item holds.
    private(set) var linkStamp = 0

    /// An edge this item does not hold itself changed: the other end came, went or moved.
    func noteLink() { linkStamp &+= 1 }
    /// Changes only when the copy's bound embeds of this item change.
    private(set) var embedStamp = 0
    /// The item as `headerStamp` last counted it. Not observed: a reader follows `headerStamp`.
    @ObservationIgnored private(set) var headerSnapshot: Item
    /// The version as `versionStamp` last counted it. Not observed: a reader follows `versionStamp`.
    @ObservationIgnored private(set) var versionSnapshot: ItemVersion
    /// The text as `textIsEmpty` last counted it. Not observed: a reader follows `textIsEmpty` and `hasBody`.
    @ObservationIgnored private(set) var bodySnapshot: ItemBody?
    /// The bound embeds as `embedStamp` last counted them. Not observed: a reader follows `embedStamp`.
    @ObservationIgnored private(set) var embedSnapshot: [BoundEmbed]

    init(_ item: Item) {
        listedItem = item
        headerSnapshot = item
        versionSnapshot = item.version
        embedSnapshot = item.boundEmbeds
    }

    private func noteShown(_ old: Item) {
        if item.edgesOut != old.edgesOut { linkStamp &+= 1 }
        if item.boundEmbeds != old.boundEmbeds {
            embedSnapshot = item.boundEmbeds
            embedStamp &+= 1
        }
        if item.version != old.version {
            versionSnapshot = item.version
            versionStamp &+= 1
        }
        if Self.affectsHeader(old, item) {
            headerSnapshot = item
            headerStamp &+= 1
        }
    }

    private func noteText() {
        bodySnapshot = body
        let present = body != nil
        if present != hasBody { hasBody = present }
        let empty = body?.text.isEmpty ?? true
        if empty != textIsEmpty { textIsEmpty = empty }
    }

    /// Whether the page header can show a difference. The version, the preview, sync and the bound embeds are not
    /// drawn there. `modified` is: Updated is a pin.
    private static func affectsHeader(_ old: Item, _ new: Item) -> Bool {
        old.type != new.type || old.title != new.title || old.name != new.name || old.titleRule != new.titleRule
            || old.properties != new.properties || old.content != new.content || old.state != new.state
            || old.tier != new.tier || old.tags != new.tags || old.created != new.created
            || old.modified != new.modified || old.occurred != new.occurred || old.trashed != new.trashed
            || old.edgesOut != new.edgesOut || old.problem != new.problem || old.readOnly != new.readOnly
            || old.source != new.source
    }
}

/// A library read from a Marfa server's working copy through its source. It holds what the source last said and
/// changes nothing on its own: every write goes to the source, which applies it to its copy at once and says what
/// changed. Undo is kept here, as writes that put back what a write changed, made at the version current when
/// the undo runs.
@Observable final class MarfaLibrary: ItemLibrary {
    var isLoaded = false
    /// Where the library tells the person what it could not do or keep: the host's, for every library it opens.
    @ObservationIgnored let notices: Notices
    /// Has every open page hand over its last edit, then says whether all of them did, so a change that moves an
    /// item's text moves what the person sees.
    @ObservationIgnored var handOverEdits: (@escaping (Bool) -> Void) -> Void = { EditorController.flushAll(leaving: false, then: $0) }
    var itemsToPurge: Set<ItemID> = []
    var catalogue = Catalogue()
    var views: [LibraryView] = []
    private(set) var syncReport: SyncReport
    var downloadedFiles: (any DownloadedFiles)? { source.downloadedFiles }
    func downloadEverythingAgain() { source.downloadEverythingAgain() }
    func instanceID() async -> String? { await source.instanceID() }
    /// The server's `https` link for the item, which is the one to share, or the `marfa://` link where the server gives
    /// none: it can't be reached, answers an error (an item it doesn't hold yet) or there is no server to ask.
    func itemLink(_ id: ItemID) async -> ItemLinkCopy? {
        if let links, let web = try? await links.webLink(of: id) { return ItemLinkCopy(url: web) }
        return await appLink(id)
    }
    /// How the server stands, for the app to show beside the library. The library is the one subscriber to the
    /// source's states; the host reads this while the copy is open.
    private(set) var connection: MarfaConnectionState
    /// Read from the copy each time it is read whole (`readServerKey`), so a server replaced at the same address finds
    /// nothing the old one's library kept (`ItemLibrary.serverKey`).
    var serverKey = ""
    @ObservationIgnored let pictures: WebPictures
    let now: () -> Date
    let calendar: () -> Calendar

    /// Bumped when any item changes, for the lists and search.
    var contentRevision = 0
    /// Which items each step of `contentRevision` changed (`changedItems(since:)`).
    @ObservationIgnored var changeLog = ItemChangeLog()
    /// Bumped only when an item comes, goes or changes which places hold it, or the catalogue changes, for the counts.
    var membershipRevision = 0
    /// Bumped when an item's title or the name the core gives it changes. A link shows that name. A keystroke that
    /// does not change either leaves this still, unlike `contentRevision`, which the copy's publish of the row moves.
    var namesRevision = 0
    var searchRevision = 0
    var viewRevision = 0

    @ObservationIgnored let source: any ItemSource
    @ObservationIgnored let counts: ItemCounts
    /// Reads an item's earlier versions from the server, which the copy does not hold. Nil where there is no server
    /// to ask, as in the sample library.
    @ObservationIgnored let history: (any ItemHistorySource)?
    /// Keeps the owner's choice of a type's icon on the server. Nil where there is no server to ask.
    @ObservationIgnored let typeIcons: (any TypeIconSource)?
    /// Keeps changes to a type's fields on the server. Nil where there is no server to ask.
    @ObservationIgnored let typeSchemas: (any TypeSchemaSource)?
    /// Reads the server's own settings, for the bin's retention; nil where there is no server to ask, as in the sample.
    @ObservationIgnored let config: (any InstanceConfigSource)?
    /// Reads and changes the names, marks and counts of sources, which only the server holds. Nil where there is no
    /// server to ask, as in the sample.
    @ObservationIgnored let sourceNames: (any SourceNameSource)?
    /// Reads an item's `https` link from the server, which only it can give. Nil where there is no server to ask, as
    /// in the sample.
    @ObservationIgnored let links: (any ItemLinkSource)?
    /// The icon each type last showed after the person chose one, until the working copy's own catalogue shows the type
    /// with another icon than it had when the person chose, since the copy takes a schema change only when its stream
    /// reopens. `before` is the icon the copy showed then.
    @ObservationIgnored var chosenIcons: [TypeID: (icon: String?, before: String?)] = [:]
    /// The changes to fields the server took, until the working copy's own catalogue shows the type other than it was
    /// when the server took them, for the same reason as the icons. `before` is the type the copy showed then.
    @ObservationIgnored var chosenFields: [(plan: FieldEditPlan, before: ItemTypeInfo?)] = []
    /// The catalogue the working copy last reported, without the chosen icons and fields.
    @ObservationIgnored var readCatalogue = Catalogue(itemTypes: [])
    @ObservationIgnored var records: [ItemID: ItemRecord] = [:]
    @ObservationIgnored var index = MarfaItemIndex()
    @ObservationIgnored var listed: [ListingKey: Listing] = [:]
    @ObservationIgnored var listedDeleted: Listing?
    @ObservationIgnored var orderedView: (content: Int, hits: [ItemID], items: [Item], isProvisional: Bool)?
    @ObservationIgnored var counted: [Place: (revision: Int, counts: ScopeCounts)] = [:]
    @ObservationIgnored var countedAlone: (revision: Int, counts: StandaloneCounts)?
    @ObservationIgnored var searches: [SearchKey: SearchRun] = [:]
    @ObservationIgnored var searchOrder: [SearchKey] = []
    /// What the latest search to be asked found, once it finishes, shown while the next one runs so the list does not
    /// empty per key. An older search that finishes later does not replace it. Its excerpts are left out, since they
    /// quote another search's words.
    @ObservationIgnored var lastFound: [ItemID] = []
    /// Which run of a search may still be shown. A later search takes the next number, and a late answer is dropped.
    @ObservationIgnored var searchTurn = 0
    @ObservationIgnored var searchTurns: [SearchKey: Int] = [:]
    @ObservationIgnored var searchTasks: [SearchKey: Task<Void, Never>] = [:]
    /// The latest search whose answer may stand in while another has not returned. One that asks what was left out
    /// does not move it.
    @ObservationIgnored var shownEpoch = 0
    /// What each view last listed, read from the copy beside the views as a search is.
    @ObservationIgnored var viewed: [ItemID: Search] = [:]
    /// Views whose list could not be read, told once until one is read again.
    @ObservationIgnored var viewsFailing: Set<ItemID> = []
    /// Bumped when the views change, so a read begun before is dropped.
    @ObservationIgnored var viewsGeneration = 0
    /// What a view's items were last read to be for a query other than its own, which a window asks for while it
    /// shows a filter of the view changed and not saved (`previewItems(ofView:query:)`). Keyed by the query, so two
    /// windows on one view, each with its own changes, never share an answer. The latest few are kept.
    @ObservationIgnored var previews: [PreviewKey: Preview] = [:]
    @ObservationIgnored var previewOrder: [PreviewKey] = []
    /// The latest answer of any preview of a view, listed while another query of it is read.
    @ObservationIgnored var lastPreview: [ItemID: [ItemID]] = [:]
    /// The query of each view whose read began last, so an older read that answers late is not taken for the newest.
    @ObservationIgnored var newestPreviewRead: [ItemID: PreviewKey] = [:]
    /// Views whose preview was refused, told once until one is read again.
    @ObservationIgnored var previewsFailing: Set<ItemID> = []
    /// Text writes the source has not answered, by item. While any wait, the text the person gave is what the
    /// library holds, since a read that raced the write could give older text.
    @ObservationIgnored var unsettledText: [ItemID: Set<WriteID>] = [:]
    /// Each of those writes, until the source answers it.
    @ObservationIgnored var textWrites: [WriteID: TextWrite] = [:]
    /// What the copy holds of each item's text while the person's own text is unsettled, held once it settles: the
    /// text before the first save, the typed text of each save the copy took, or a body the source told after.
    @ObservationIgnored var sourceText: [ItemID: ItemBody] = [:]
    /// From the person's text being submitted to the engine having taken or answered it.
    @ObservationIgnored var textSaves: [WriteID: Telemetry.Interval] = [:]
    /// Text writes the copy has not yet taken and read back, by item, so what it bound in the text may be older.
    @ObservationIgnored var unreadText: [ItemID: Set<WriteID>] = [:]
    /// The version the person's last sent save of each item was typed on. Only the first save sent on a
    /// version is merged against it; the rest follow the person's own.
    @ObservationIgnored var savedOn: [ItemID: ItemVersion] = [:]
    /// Text typed on the text the library holds and not yet sent, by item (`TextPause`). The library holds it at once,
    /// as it holds unsettled text; only the write waits.
    @ObservationIgnored var waitingText: [ItemID: WaitingText] = [:]
    @ObservationIgnored let textPause: TextPause
    /// Whether the source has said its last, so nothing typed waits for a source that will take no write.
    @ObservationIgnored var sourceEnded = false
    /// Links removed only once the source has taken the links added in their place, by the link writes awaited.
    @ObservationIgnored var replacements: [UUID: Replacement] = [:]
    @ObservationIgnored var replacing: [WriteID: UUID] = [:]
    /// The undo or redo whose handler is making writes now, and the one each write that may be held belongs to
    /// (`MarfaLibrary+Undoing`).
    @ObservationIgnored var undoRun: UndoRun?
    @ObservationIgnored var undoRuns: [WriteID: UndoRun] = [:]
    /// What follows the answer to each write of a state change, told what the answer means for the move (`setStates`).
    @ObservationIgnored var stateAnswers: [WriteID: (StateAnswer) -> Void] = [:]
    /// The state writes the engine has not yet judged, and the change each belongs to (`stateWriteJudged`).
    @ObservationIgnored var stateJudging: [WriteID: StateMoves] = [:]
    /// The restores whose item is archived once the server accepts them, and that item (`setStates`).
    @ObservationIgnored var awaitingArchive: [WriteID: ItemID] = [:]
    /// Restores answered blocked or dead whose archive will not follow, told together once no restore waits.
    @ObservationIgnored var archivesDropped = 0
    /// The link step each edge write belongs to, until the copy takes it and the server makes it or not (`LinkStep`).
    @ObservationIgnored var linkSteps: [WriteID: LinkStep] = [:]
    /// What follows when the server does not make each tier write, until its last answer (`setTiers`).
    @ObservationIgnored var tierWrites: [WriteID: () -> Void] = [:]
    /// The command whose skips are gathered now, and the one each write waiting for its first answer belongs to
    /// (`gatheringSkips`).
    @ObservationIgnored var gathering: SkipNotice?
    @ObservationIgnored var skipNotices: [WriteID: SkipNotice] = [:]
    /// What to tell the person if the source refuses each write the library made.
    @ObservationIgnored var refusals: [WriteID: Refusal] = [:]
    @ObservationIgnored private var following: [Task<Void, Never>] = []
    /// The relationship changes asked for and not yet written or refused, and the last of them, which the next waits
    /// for so changes run in the order they were made (`changeLinks`).
    @ObservationIgnored var relationshipChangesInFlight = 0
    @ObservationIgnored var relationshipChain: Task<Void, Never>?
    /// The relationship writes the source took that the copy has not yet taken in or the source has not answered, and
    /// the changes waiting for some of them.
    @ObservationIgnored var unsettled: Set<WriteID> = []
    @ObservationIgnored var waiters: [Waiter] = []

    /// A change waiting until each of `pending` is settled.
    struct Waiter {
        var pending: Set<WriteID>
        let resume: CheckedContinuation<Void, Never>
    }
    /// The item each create names, until the source answers it.
    @ObservationIgnored var creating: [WriteID: ItemID] = [:]
    /// The item each property edit is for, until the copy takes or refuses it. Observed, so an editor holding a list it
    /// wrote can tell a write still on its way from one refused (`isWritingProperties(of:)`).
    var propertyWrites: [WriteID: ItemID] = [:]
    /// The mark of each property edit (`lastPropertyWrite`) until the copy takes or refuses it, and the marks of the
    /// edits it took lately, so an editor can tell a write that landed and was changed again before it drew from one
    /// refused (`tookPropertyWrite(_:)`).
    @ObservationIgnored var propertyMarks: [WriteID: Int] = [:]
    /// This Mac's property edits with no final answer yet (`MarfaLibrary+PropertyEdits`).
    @ObservationIgnored var propertyEdits: [WriteID: PropertyEdit] = [:]
    /// This Mac's newest edit of each key of each item, until it has a final answer and the item has been read since.
    /// The engine publishes an answer before it reads the item again, so until then the copy may still show a refused
    /// edit.
    @ObservationIgnored var newestEdits: [ItemID: [String: PropertyEdit]] = [:]
    @ObservationIgnored var lastPropertyWrite: Int? = 0
    @ObservationIgnored var takenMarks: Set<Int> = []
    /// Creates the source refused, before or after it held the item (`ItemLibrary.refusedCreations`).
    var refusedCreations: Set<ItemID> = []
    /// Why text typed over an item that can no longer be written is not kept.
    static var cantChange: String {
        String(localized: "This item can’t be changed now, so the app couldn’t keep what you typed.")
    }

    /// A place's order changes only with what it holds, so a change to one item maps the items again without
    /// sorting them.
    /// What one listing was asked for: a place with its choices, or the Library's Favorites view.
    nonisolated struct ListingKey: Hashable {
        var place: Place
        var favorites = false
        var scope: ListScope
        var archived: ArchivedItems
        var includingKinds: Bool
    }

    nonisolated struct Listing {
        var membership: Int
        var content = -1
        var ids: [ItemID]
        var items: [Item] = []
        /// Where each id stands in `ids`, kept between patches while the ids stay (`MarfaLibrary.listing`).
        var positions: [ItemID: Int]?
        /// A listing the library outran, kept so a place that keeps changing still opens. Its order is only as good as a
        /// patch makes it, so a whole listing follows (`deferredListing`).
        var isProvisional = false
    }

    /// A text save the source has not answered.
    nonisolated struct TextWrite {
        let item: ItemID
        /// The text the save put on the page, until the copy takes the save. None where the person typed on older
        /// text, which left the page as it was.
        var shown: ItemBody?
        /// What the person typed, so text a closing source refuses can be given back to them. Only the item's last
        /// save keeps it, since that holds everything typed before it.
        var typed: String?
    }

    /// How long typed text waits before the library sends it. The page reports the item's whole text at every change,
    /// so a write per report sends the whole text per key. The library sends the latest text once the person has
    /// paused for `quiet` and no earlier text write of the item is still unanswered, and never holds text longer than
    /// `cap`, so text typed offline, where nothing is answered, still reaches the copy's queue soon. A hand-over, or
    /// any other write naming the item, sends it at once.
    nonisolated struct TextPause: Sendable {
        var quiet: Duration
        var cap: Duration

        static let typing = TextPause(quiet: .milliseconds(500), cap: .seconds(2))
    }

    /// The latest text typed on an item and not yet sent. Every report is the whole text, so it replaces the one before.
    nonisolated struct WaitingText {
        var text: String
        let readAt: ItemVersion
        var title: String
        var reports: Int
        /// When the first report it holds came, which bounds how long it waits.
        let since: ContinuousClock.Instant
        var last: ContinuousClock.Instant
        var timer: Task<Void, Never>?
    }

    nonisolated struct Refusal {
        var title: String
        /// What the write carried, which a closing source would otherwise lose.
        var text: String?
        /// What the person typed into the write, which a refusal before queueing would otherwise lose
        /// (`unqueuedText(_:)`).
        var unqueuedText: String?
    }

    struct Replacement {
        var awaiting: Set<WriteID>
        let unlinks: [EdgeDraft]
        let failing: String
        let step: LinkStep
    }

    nonisolated struct Search {
        var revision: Int
        var hits: [ItemID]
        var running: Bool
    }

    nonisolated struct PreviewKey: Hashable {
        var view: ItemID
        var query: LibraryViewQuery
    }

    nonisolated struct Preview {
        var revision: Int
        var hits: [ItemID]?
        var running: Bool
        /// Whether the copy refused the query the last time it was asked.
        var refused = false
    }

    nonisolated struct SearchKey: Hashable {
        var query: String
        var scope: SearchScope
        var narrowing = SearchNarrowing.none
        /// Whether this asks for what the narrowing leaves out rather than what it keeps.
        var asksLeftOut = false

        var isOfView: Bool {
            if case .view = scope { true } else { false }
        }
    }


    nonisolated struct SearchRun {
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
        typeIcons: (any TypeIconSource)? = nil, typeSchemas: (any TypeSchemaSource)? = nil, config: (any InstanceConfigSource)? = nil,
        sourceNames: (any SourceNameSource)? = nil, links: (any ItemLinkSource)? = nil,
        pictures: WebPictures = .kept(for: "Sample"),
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current },
        textPause: TextPause = .typing,
        cameOnline: @escaping () -> Void = {}) {
        self.source = source
        self.pictures = pictures
        self.textPause = textPause
        counts = ItemCounts { ids, query in try await source.counts(of: ids, query) }
        self.history = history
        self.typeIcons = typeIcons
        self.typeSchemas = typeSchemas
        self.config = config
        self.sourceNames = sourceNames
        self.links = links
        self.notices = notices
        self.now = now
        self.calendar = calendar
        syncReport = source.syncReport
        connection = source.connectionState
        let changes = source.changes()
        let reports = source.syncReports()
        let states = source.connectionStates()
        following = [
            Task { [weak self] in
                for await change in changes {
                    guard let self else { return }
                    await take(change)
                }
                // The source has closed, so text still waiting, and any typed after, goes back to the person at once.
                self?.sourceEnded = true
                self?.sendWaitingText()
                // Nothing more will be taken or answered, so no change waits for it.
                self?.endWaits()
                self?.dropWaitingArchives()
            },
            Task { [weak self] in
                for await report in reports { self?.syncReport = report }
            },
            Task { [weak self] in
                for await state in states {
                    guard let self else { return }
                    let wasOnline = connection == .online
                    connection = state
                    if state == .online, !wasOnline {
                        cameOnline()
                        readTrashDays()
                        Task { await self.refreshSources() }
                    }
                }
            }
        ]
        readTrashDays()
        Task { await refreshSources() }
    }

    isolated deinit {
        for task in following { task.cancel() }
        for task in searchTasks.values { task.cancel() }
    }

    var reachesServer: Bool { connection == .online }

    /// The names, marks and counts the server last gave, kept while it cannot be reached. Before the first answer a
    /// source shows its code, and its count is the loaded items'. It is read again at start, on coming online, when
    /// the Sources page opens and whenever the items change while it is open; a turn counter stops a read that began
    /// before a rename from undoing it. Counts come from `itemCountsBySource(state: "active", filter: "part eq false")`,
    /// both tiers, which leaves out parts (items that live with a host, such as attached files), as the server's own
    /// lists do; the app's lists hide only attached files, so another kind of part would count lower than the list shows.
    /// Once the server has answered, the Sources page and sidebar list its sources that hold items
    /// (`SourceDirectory.listing`), the last answer while offline; before that, the loaded items' sources.
    var sources = SourceDirectory()
    /// What the server's connectors say of the types they write, read once (`readConnectors`).
    var connectors: ConnectorKeepers?
    @ObservationIgnored var isReadingConnectors = false
    @ObservationIgnored var connectorsFailedAt: ContinuousClock.Instant?
    /// Counts the asks as they start, so an answer that comes after a later ask or a rename does not put back what it
    /// found before.
    @ObservationIgnored var sourceTurn = 0
    @ObservationIgnored var appliedNamesTurn = 0
    @ObservationIgnored var appliedCountsTurn = 0

    /// The idempotency key of each write that failed for want of the server, so trying it again cannot make it twice
    /// where the server took it before the answer was lost.
    @ObservationIgnored var viewWriteKeys: [ViewWrite: String] = [:]

    enum ViewWrite: Hashable {
        case create(LibraryViewSettings)
        case change(ItemID, LibraryViewChange, Int64)
        case delete(ItemID)
    }

    /// How long the server keeps an item in the bin, from This Marfa's `trash_retention_days`, read when the library
    /// opens, each time the server is reached again, and after a save in This Marfa. Nil where the server has not set
    /// it (its default then applies, which a key cannot read), keeps items without limit (zero), or the key may not
    /// read its settings; a failed read keeps what was read before.
    var trashDays: Int?
    /// Counts the reads and saves of the settings as they start.
    @ObservationIgnored var settingsTurn = 0
    /// The turn of the answer the retention was last taken from, so a read that answers after a later read or a save
    /// does not put back what it found before, and a later read that fails does not drop an earlier one's answer.
    @ObservationIgnored var appliedTurn = 0
}
