import Foundation
import Observation

/// Everything the views, the commands and the editor use of a library, so none of them knows what holds the items:
/// `MarfaLibrary`, over a Marfa server's working copy, in the app, and `FakeItemLibrary` in tests.
///
/// Deleting permanently, writing a view and choosing a type's icon need the server, so a view dims them while
/// `reachesServer` is false rather than asking.
@MainActor
protocol ItemLibrary: AnyObject, Observable {
    // MARK: State

    /// Whether the items have been read, so a window restores what it showed only once there is something to find.
    var isLoaded: Bool { get }
    /// Where the library tells the person what it could not do or keep.
    var notices: Notices { get }
    /// Items a person has asked to erase for good, until a window asks them to confirm.
    var itemsToPurge: Set<ItemID> { get set }
    var catalogue: Catalogue { get }
    /// The views saved on the server, by title, each a place of its own (`SidebarItem.view`). Empty where there are
    /// none or they cannot be read.
    var views: [LibraryView] { get }
    /// Whether the server can be reached now, which is what every write that is never queued needs: deleting items
    /// in Recently Deleted for good, saving, changing and deleting a view, and choosing a type's icon, and changing a type's fields.
    var reachesServer: Bool { get }
    /// How many days an item stays in Recently Deleted, where the server says; nil where it does not.
    var trashDays: Int? { get }
    /// What the library has yet to send, and each write that needs the person. An item's own state is its `sync`.
    var syncReport: SyncReport { get }
    var downloadedFiles: (any DownloadedFiles)? { get }
    /// Hydrates the library's copy again, keeping every write not yet sent.
    func downloadEverythingAgain()
    /// False where the action is not offered for the problem.
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool
    var now: () -> Date { get }

    // MARK: Reading

    /// Counts the changes to the items and the catalogue. Reading it is observed, so a view that works something out
    /// from the items, and keeps it, is told when to work it out again.
    var contentRevision: Int { get }
    /// Counts only the changes that move an item between places or change the catalogue: an item coming, going, or
    /// changing its state, tier, tags, type or links. What a place holds, and so what its counts and layouts are, can
    /// change only when this does. Reading it is observed.
    var membershipRevision: Int { get }
    /// Counts changes to an item's title or the name the core gives it. A link shows that name, so a page follows
    /// this and `membershipRevision` rather than `contentRevision`, which a published keystroke moves. A library that
    /// bumps `membershipRevision` for every item change may leave this as that.
    var namesRevision: Int { get }
    func item(_ id: ItemID) -> Item?
    /// The instance id of the Marfa the library's copy holds, as its `GET /` names it, which an item's `marfa://` link
    /// is checked against; nil until the copy has read it. Reads only the copy.
    func instanceID() async -> String?
    /// The link Copy Link copies, which every place that copies it asks for: the server's `https` link where a library
    /// can read it, else the `marfa://` link built from the IDs alone (`ItemAppLink`), nil where neither can be given yet.
    func itemLink(_ id: ItemID) async -> ItemLinkCopy?
    /// The item as a page header shows it. A change to only its version, preview, sync or bound embeds is not one.
    func headerItem(_ id: ItemID) -> Item?
    /// The item's version alone. It changes only when the version does, not when the text, preview, sync or embeds do.
    func itemVersion(_ id: ItemID) -> ItemVersion?
    func items(in place: SidebarItem) -> [Item]
    /// What Recently Deleted holds, newest first. It is a page of Settings, not a place, so no window lists it.
    var deletedItems: [Item] { get }
    var deletedCount: Int { get }
    /// The items the saved view `view` would list with `query` in place of its own, which a window shows while it
    /// has changed the view's filters and not saved them. It reads the library's own copy, so it works offline, and
    /// writes nothing. Two windows on one view ask for their own queries and never share an answer.
    func previewItems(ofView view: ItemID, query: LibraryViewQuery) -> [Item]
    /// What the library's own search finds for `query` in `scope`, best match first: the items not deleted, the
    /// excerpt of each that has one, and whether the search may be missing items because the copy is still filling.
    /// Nothing is found for a query with no words.
    func search(_ query: String, in scope: SearchScope) -> SearchResults
    /// The same over every item, with the types and sources `narrowing` keeps and leaves out applied inside the
    /// search, so what it lists is counted after them rather than narrowed once listed.
    func search(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults
    /// What that search finds among the items `narrowing` leaves out, at most `SearchResults.leftOutLimit`; nothing
    /// where nothing is left out. A library asks the copy only when this is read.
    func searchLeftOut(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults
    func count(in place: SidebarItem) -> Int
    /// The catalogue's types that hold items, with their labels and counts, for a sidebar that lists them. The
    /// default is built from `catalogue` and `count(in:)`, so a library answers it without a view asking what kind
    /// of library it is.
    var itemTypeCounts: [ItemTypeCount] { get }
    func name(of place: SidebarItem) -> String
    /// Whether a window kept for this item has nothing left to show, which is known only once the items are read.
    func isGone(_ id: ItemID?) -> Bool
    /// The items to open in windows of their own: those the library holds.
    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID]
    /// Nil for an item with no text, such as a file.
    func body(of id: ItemID) -> ItemBody?
    /// Whether the item has no text. It changes only when the text becomes empty or not, so an edit that leaves text
    /// in the item does not count. Missing text counts as empty.
    func textIsEmpty(_ id: ItemID) -> Bool
    /// The item's text for a check that depends on what it says, such as whether the item can change type. It changes
    /// when the text arrives, goes, or becomes empty or not, and not when text that stays non-empty is edited.
    func bodyText(_ id: ItemID) -> String?
    /// The copy's bound embeds of the item. It changes only when those do.
    func boundEmbeds(of id: ItemID) -> [BoundEmbed]
    /// Whether text saved to the item has not yet been sent or read back from the library's copy, so what the copy
    /// bound in the text (`Item.boundEmbeds`) may not cover it yet.
    func hasUnreadSave(_ id: ItemID) -> Bool
    /// The `[[link]]` that the text of `itemID` can hold and the core binds, from that item, to this item and no
    /// other, or nil when no spelling does.
    func bodyLink(to id: ItemID, in itemID: ItemID?) async -> String?
    /// What the core says each link target names, read as a link in `itemID` when given (`Items.linkCandidates`):
    /// bound to one item, ambiguous with its candidates, or unresolved. Nil where the library cannot ask, such as
    /// for an item it does not hold; the answer is never guessed from the titles held.
    func linkAnswers(of targets: [String], in itemID: ItemID?) async -> [LinkAnswer]?
    /// The property keys of the item that the inspector never lists: what the page shows as the title and the text,
    /// and any a library keeps for its own use.
    func hiddenPropertyKeys(of item: Item) -> Set<String>
    /// The counts of what an item holds, worked out when read and never stored (`CountFact`): its children, a collection's
    /// members, a table's rows. Reading an answer is observed, so a view is drawn again when one comes or changes.
    var counts: ItemCounts { get }
    func relationships(for id: ItemID) -> [ItemRelationship]
    /// The items filed directly under `id` (`parent-of`), in no order, held or not. Observed, so a view that works
    /// something out from them is told when one comes or goes.
    func childIDs(of id: ItemID) -> [ItemID]
    func relationshipCandidates(for id: ItemID, field: String) -> [Item]
    /// What the core says of linking `id` through `field` to `other`, judged on what is held, with nothing queued and
    /// no server: taken, refused in its words, or unknown where it could not be asked.
    func relationshipVerdict(for id: ItemID, field: String, to other: ItemID) async -> EdgeVerdict
    /// What the core says of filing a new item under `parent`, asked before the item exists: a parent in the bin or of a
    /// type that cannot be one is refused, as is nesting under a flat type. The new item has no id the copy holds, so
    /// the core does not judge its type here; `creationParentCandidates` keeps to the types the parent end admits.
    func newChildVerdict(under parent: ItemID) async -> EdgeVerdict
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget]
    func creationParentCandidates(typeID: String) -> [Item]
    /// Whether `creationParentCandidates` would list anything: a cheap check that sorts and builds nothing, for a
    /// view that is evaluated at every keystroke.
    func canHaveParent(typeID: String) -> Bool

    // MARK: History

    /// Where an item's earlier versions are read, or nil where the library keeps none. Reading them can fail while
    /// the rest of the library works, as when the server is out of reach.
    var history: (any ItemHistorySource)? { get }

    // MARK: Collections

    /// The active collections, by title: items whose type plays Marfa's `container` role (`Catalogue.isCollection`).
    var collections: [Item] { get }
    /// Files each item in the collection with one `in-collection` edge, in one undoable change, leaving out those
    /// already in it. An item that can't be a member, as a collection can't, or can't be changed, is skipped and the
    /// library tells the person how many and why. False where nothing was filed because every item was skipped.
    @discardableResult
    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool
    /// Removes the items' `in-collection` edges to the collection in one undoable change; false when none of them is
    /// in it. An item in it that can't be changed is skipped and told.
    @discardableResult
    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool

    // MARK: Files

    /// A file item's file, fetched first; nil for an item that is not a file.
    func fileURL(of id: ItemID) async throws -> URL?

    /// The file items attached to `id`, in any state: those with an `attached-to` edge to it. Observed, so a file
    /// attached or taken off is told to whoever read this. It follows changes to links only, not to the files
    /// themselves, so read each file with `item(_:)` to follow those.
    func attachments(of id: ItemID) -> [ItemID]

    // MARK: Writing

    /// Nil when the item cannot be made, and the library tells the person why. The properties go in the create
    /// itself, so a type whose fields are required is made whole in one write.
    func createItem(
        typeID: String, title: String, body: String, properties: [String: PropertyValue], parentID: ItemID?,
        in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID?
    /// Adds the file at `file` as an item of its own, of the file type its media type calls for, titled `title` or by its name, under `parentID`
    /// where one is given. The file is read where it is while this runs. Nil when it could not be added, and the
    /// library tells the person why.
    func addFile(_ file: URL, title: String?, parentID: ItemID?, in place: SidebarItem) async -> ItemID?
    /// Text typed on the page, over the text `body(of:)` gave at `readAt`. An edit typed on text older than the
    /// library now holds was made without seeing what replaced it, so it never silently overwrites that. Typing is
    /// undone by the page that holds it, so this registers nothing.
    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion)
    /// Every item being written is left and every change handed over, as the app quits or the library changes:
    /// returns once each is kept on this Mac, never waiting on a server.
    func finish() async
    /// Sends at once any typed text the library holds back to send fewer writes, as every hand-over of the pages
    /// ends with, so nothing typed before a hand-over still waits after it.
    func sendWaitingText()
    /// Whether the create of `id` was refused before the library held the item, so the window has no item to open and the
    /// library has told the person. A library that refuses a create at once answers nil from `createItem` instead.
    func wasRefused(creating id: ItemID) -> Bool
    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool
    /// Several properties of one item in one edit and one undo step named `actionName`, each given its value or, where
    /// the change is nil, taken away. Nothing is sent unless every one can be: the item takes edits and each key is a
    /// property of its type that takes the value. A change to what the item already holds is left out, so a call that
    /// changes nothing sends nothing and is still taken, except while an edit of the item is on its way
    /// (`isWritingProperties(of:)`): then every change goes, since one may reverse that edit.
    @discardableResult
    func setItemProperties(_ id: ItemID, changes: [String: PropertyValue?], actionName: String, undoManager: UndoManager?) -> Bool
    /// Whether an edit of the properties of `id` is still on its way into the library, so the item does not show it
    /// yet. False once the library holds the edit or has refused it. A library that writes at once is never writing.
    func isWritingProperties(of id: ItemID) -> Bool
    /// A mark for the last property edit the library made, of any item, read right after making one: nil for a
    /// library that writes at once. `tookPropertyWrite(_:)` says later whether the library took that edit, so an
    /// editor can tell a write that landed and was changed again before it drew, as by Undo, from one refused.
    var lastPropertyWrite: Int? { get }
    func tookPropertyWrite(_ mark: Int) -> Bool
    /// Links `adding` to `id` and unlinks `removing` in the field, once the library has judged the change. A caller
    /// sends what the person changed, never the list the screen showed, so a change made since is not undone. True
    /// means the library accepted it and holds it, or there was nothing to change; false means it refused, told the
    /// person, and left the field as it was.
    @discardableResult
    func changeItemRelationship(_ id: ItemID, field: String, adding: [ItemID], removing: [ItemID], undoManager: UndoManager?) async -> Bool
    /// Moves each item to `type`, its title and text to the new type's keys in the same edit, with `filling` for
    /// the required fields an item lacks (`TypeChange`). Fields the new type does not use stay on the item. An item
    /// that cannot become `type`, or cannot be changed, is skipped and the library tells the person how many and why;
    /// the rest change in one undoable step that moves them back. False where nothing is sent, as when every item is
    /// skipped or a required value is missing, and the library tells the person why.
    @discardableResult
    func changeType(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?) -> Bool
    /// Puts the text and title of an earlier version (`restoreCheck`) on the item as a new edit, made on the version
    /// the library holds now, so what it replaces stays in the item's history. Undo puts back what it replaced, if the
    /// item still holds what the restore wrote. False where nothing is sent, and the library tells the person why
    /// unless there was nothing to change.
    @discardableResult
    func restoreVersion(_ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?) -> Bool
    /// In one undoable change. An item in the bin is skipped and told.
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?)
    /// The tags the library sets itself, which the person neither adds nor removes by hand: the favorite tag, which
    /// the Favorite command owns, and any a library keeps for its own use.
    var reservedTags: Set<String> { get }
    /// Every tag the active items carry, reserved ones left out, the most used first and then by name, for
    /// suggesting a tag the person has used.
    var knownTags: [String] { get }
    /// Tags `tag` to each of the items that can take it and do not hold it, in one undoable change, and answers nil.
    /// An item that can't be changed, or already has the most tags, is skipped and the library tells the person how
    /// many and why. Nothing is sent, and the refusal is given back, where `tag` is not a tag Marfa takes, is
    /// reserved, or no item can take it (`checkedTag`). The caller keeps what the person typed.
    @discardableResult
    func addTag(_ tag: String, to ids: Set<ItemID>, undoManager: UndoManager?) -> ItemTag.Refusal?
    /// Removes `tag` from each of the items that hold it. An item that no longer holds it, as when another device
    /// removed it first, is left alone.
    func removeTag(_ tag: String, from ids: Set<ItemID>, undoManager: UndoManager?)
    /// To Recently Deleted, in one undoable change. An item already there has nothing to change.
    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?)
    /// For the question before moving several items: how many more items than `ids` the server says moving them also
    /// takes, only where the library is online and `ids` are 2 to 20; nil otherwise and whenever it can't be read.
    /// Reads only, and never blocks the move, which is each item's queued delete whatever this answers.
    func moreItemsTaken(with ids: Set<ItemID>) async -> Int?
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?)
    /// Not undoable, so the views confirm it first, and only where `reachesServer`.
    func deletePermanently(_ ids: Set<ItemID>)
    /// Files the item points at, such as pasted images, with the links the page writes for them. A library that
    /// sends them elsewhere may have to wait. Each file is attached on its own, so one that fails leaves the
    /// others attached, and the report names it.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async -> AttachReport
    /// Attaches the file at `file` to the item, read where it is while this runs, and says what the item's text
    /// writes to show it. A failure means the file is not attached.
    func attach(file: URL, to id: ItemID) async throws -> Embed

    // MARK: Tier and state

    // Each registers its undo step at once and calls `moved` once the copy has queued or skipped every write, with
    // what it queued, so a toast never names a move the copy did not make.

    /// Moves each of `ids` that `tierPlan` changes to `tier`, each its own queued write, in one undoable change named
    /// for the command. What it leaves alone is told. An Undo moves back only an item still in the tier this left.
    func setTier(_ ids: Set<ItemID>, to tier: Tier, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?)
    /// Archives what `archivePlan` gives for `ids`, and the items beneath them where `beneath`, in one undoable change.
    /// An Undo makes active again only what this archived and is still archived; an item archived before stays so.
    func archive(_ ids: Set<ItemID>, beneath: Bool, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?)
    /// Makes each archived item among `ids` active, in one undoable change. Items beneath them stay as they are.
    func unarchive(_ ids: Set<ItemID>, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?)

    // MARK: Views

    // Each tells the person why a write failed, in the server's reason, and nothing else changes.
    /// Chooses the icon of `type` for every app, or the type's own default where `icon` is nil, and draws the answer at
    /// once. Nil on success; otherwise why not, in words for the person.
    func setIcon(_ icon: String?, ofType type: TypeID) async -> TypeIconFailure?
    /// Changes one field of a type for every item of it, and shows the change at once. Never queued: it needs the
    /// server, which is asked for the type as it stands before anything is sent. Nil on success; otherwise why not, in
    /// words for the person, and nothing has changed.
    func editField(_ plan: FieldEditPlan) async -> TypeSchemaFailure?
    /// The names, marks and counts of sources the server last gave. Empty before it answers, so a view falls back to the
    /// code (`SourceDirectory.info`); a rename shows at once, and a refresh follows the server.
    var sources: SourceDirectory { get }
    /// Asks the server for the sources' names, marks and counts again; a failed ask keeps what was read before.
    func refreshSources() async
    /// Renames the source `code` or changes its mark, for every app; a field left nil stays. Nil on success; otherwise
    /// why not, in words for the person.
    func updateSource(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async -> SourceEditFailure?
    /// The view as the server saved it, or nil.
    func createView(_ settings: LibraryViewSettings) async -> LibraryView?
    /// Sent at `baseVersion`, the version of the view the window read.
    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure>
    /// For good and for every app, since a view has no bin, so the views confirm it first.
    func deleteView(_ view: ItemID) async -> Bool
}

extension ItemLibrary {
    var namesRevision: Int { membershipRevision }
    func headerItem(_ id: ItemID) -> Item? { item(id) }
    func itemVersion(_ id: ItemID) -> ItemVersion? { item(id)?.version }
    func textIsEmpty(_ id: ItemID) -> Bool { body(of: id)?.text.isEmpty ?? true }
    func bodyText(_ id: ItemID) -> String? { body(of: id)?.text }
    func boundEmbeds(of id: ItemID) -> [BoundEmbed] { item(id)?.boundEmbeds ?? [] }
    var downloadedFiles: (any DownloadedFiles)? { nil }
    func downloadEverythingAgain() {}
    func instanceID() async -> String? { nil }
    func itemLink(_ id: ItemID) async -> ItemLinkCopy? { await appLink(id) }
    /// The item's `marfa://` link (`ItemAppLink`), once the copy knows its instance id.
    func appLink(_ id: ItemID) async -> ItemLinkCopy? {
        guard let instance = await instanceID(), let link = ItemAppLink(instanceID: instance, item: id) else { return nil }
        return ItemLinkCopy(url: link.url)
    }
    func isWritingProperties(of id: ItemID) -> Bool { false }
    func sendWaitingText() {}
    var lastPropertyWrite: Int? { nil }
    func tookPropertyWrite(_ mark: Int) -> Bool { false }
    var history: (any ItemHistorySource)? { nil }
    func newChildVerdict(under parent: ItemID) async -> EdgeVerdict { .taken }

    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        createItem(typeID: typeID, title: title, body: body, properties: [:], parentID: parentID, in: place, undoManager: undoManager)
    }
    func hiddenPropertyKeys(of item: Item) -> Set<String> { catalogue.pageKeys(of: item) }

    /// The title as a link only where, from `itemID`, the core binds it to this item (`LinkAnswer.names`). The copy holds
    /// a slice and cannot tell that an item it holds is the only one by its title, so a title the core has not bound is
    /// not enough. Otherwise the item's identity with its title as the label (`[[identity|Title]]`). Each spelling is
    /// read back through `linkParts` so it is the link it was meant to be.
    func bodyLink(to id: ItemID, in itemID: ItemID?) async -> String? {
        guard let target = item(id), !target.isFile else { return nil }
        let title = target.title
        let identity = id.rawValue
        let label = ItemLinks.label(title)
        let spellings = [
            ItemLinks.spells(title, as: title) ? title : nil,
            label.isEmpty ? nil : ItemLinks.spells("\(identity)|\(label)", as: identity, alias: label) ? "\(identity)|\(label)" : nil,
            ItemLinks.spells(identity, as: identity) ? identity : nil,
        ].compactMap { $0 }
        guard let answers = await linkAnswers(of: spellings, in: itemID) else { return nil }
        for (spelling, answer) in zip(spellings, answers) where answer.names(id) {
            return "[[\(spelling)]]"
        }
        return nil
    }

    /// Erases what the person confirmed, if the library still can: a Marfa library cannot while its server is out
    /// of reach, which may have begun while the dialog was open. Otherwise nothing is erased, and the person is told.
    func deletePermanentlyOnConfirm(_ ids: Set<ItemID>) {
        guard reachesServer else {
            tellCannotPurge()
            return
        }
        deletePermanently(ids)
    }

    /// Says why items in Recently Deleted can't be erased now, which is that `reachesServer` is false.
    func tellCannotPurge() {
        notices.tell(
            String(localized: "Can’t Delete Immediately"),
            String(localized: "Deleting permanently needs the server, which can’t be reached right now. The items are still in Recently Deleted."))
    }

    /// Whether the person can give the item a title. A title is kept only as a property, so an item titled by its
    /// first line takes its title from its text.
    func canSetTitle(of item: Item) -> Bool {
        guard item.allows(.title) else { return false }
        if case .firstLine = item.titleRule { return false }
        return true
    }

    /// Why the library refused a title, in the person's words.
    var titleRefusal: String { String(localized: "The title could not be saved. Enter a title.") }

    var reservedTags: Set<String> { [ItemTag.favorite] }

    /// The item's tags the person manages, by name as the Finder sorts.
    func tags(of item: Item) -> [String] {
        item.tags.subtracting(reservedTags).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The tags `knownTags` offers that start or contain what was typed, less those the item already holds.
    func tagSuggestions(matching typed: String, excluding held: [String]) -> [String] {
        let typed = ItemTag.normalized(typed)
        return knownTags.filter { tag in
            !held.contains(tag) && (typed.isEmpty || tag.localizedStandardContains(typed)) && tag != typed
        }
    }

    /// The tag as it would be kept, the items it would be added to and why the others won't take it, or why it can't
    /// be added at all: what Marfa refuses (`items/tag-text`, `items/tag-dot-segment`, `items/tags-count`), a tag the
    /// library sets itself, and a set none of whose items can take it. An item that can't be changed or already has
    /// the most tags is skipped, not a reason to refuse the others.
    func checkedTag(_ text: String, adding ids: Set<ItemID>) -> Result<(tag: String, ids: Set<ItemID>, skips: BatchSkips), ItemTag.Refusal> {
        let tag = ItemTag.normalized(text)
        if let refusal = ItemTag.refusal(of: tag) { return .failure(refusal) }
        if tag == ItemTag.favorite { return .failure(.favorite) }
        if reservedTags.contains(tag) { return .failure(.reserved) }
        var skips = BatchSkips()
        var lacking: Set<ItemID> = []
        var holding = 0
        for id in ids {
            guard let item = item(id) else {
                skips.skip(.gone)
                continue
            }
            if let reason = item.obstacle(to: .tags) {
                skips.skip(reason)
            } else if item.tags.contains(tag) {
                holding += 1
            } else if item.tags.count >= ItemTag.maxPerItem {
                skips.skip(.fullOfTags)
            } else {
                lacking.insert(id)
            }
        }
        guard !lacking.isEmpty else {
            if skips.counts[.fullOfTags] != nil { return .failure(.full) }
            return .failure(holding > 0 ? .alreadyHas : .cantEdit)
        }
        return .success((tag, lacking, skips))
    }

    /// Whether the item can be filed in a collection: one not in the bin, of a type the catalogue lets join one. A
    /// collection can't.
    func canJoinCollection(_ item: Item) -> Bool {
        item.allows(.collections) && catalogue.canJoinCollection(item.type)
    }

    /// The items of the selection that can be filed in a collection, files too: Add to Collection and Remove from
    /// Collection are offered while there is one. The commands themselves take the whole selection and tell the
    /// person about the items they skip.
    func collectionMembers(_ ids: Set<ItemID>) -> Set<ItemID> {
        Set(ids.compactMap { item($0) }.filter(canJoinCollection).map(\.id))
    }

    /// The collections any of the items is in, by title.
    func collections(holding ids: Set<ItemID>) -> [Item] {
        let held = Set(ids.compactMap { item($0) }.flatMap(\.collectionIDs))
        return collections.filter { held.contains($0.id) }
    }

    /// What a flat list of items, such as the palette or the link picker, says beside a title: Inbox for an item
    /// waiting there, otherwise its type.
    func placeLabel(of item: Item) -> String {
        item.tier == .feed ? String(localized: "Inbox") : catalogue.label(for: item.type)
    }
}
