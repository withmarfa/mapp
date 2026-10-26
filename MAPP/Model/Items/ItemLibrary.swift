import Foundation
import Observation

/// Everything the views, the commands and the editor use of a library, so none of them knows what holds the items:
/// `MarfaLibrary`, over a Marfa server's working copy, in the app, and `FakeItemLibrary` in tests.
///
/// Deleting for good needs the server, so a view dims it while `canPurge` is false rather than asking.
@MainActor
protocol ItemLibrary: AnyObject, Observable {
    // MARK: State

    /// Whether the items have been read, so a window restores what it showed only once there is something to find.
    var isLoaded: Bool { get }
    /// Where the library tells the person what it could not do or keep.
    var notices: Notices { get }
    /// Items a person has asked to erase for good, until a window asks them to confirm.
    var notesToPurge: Set<ItemID> { get set }
    var catalogue: Catalogue { get }
    /// The views saved on the server, by title, each a place of its own (`SidebarItem.view`). Empty where there are
    /// none or they cannot be read.
    var views: [LibraryView] { get }
    /// Whether items in Recently Deleted can be deleted for good now.
    var canPurge: Bool { get }
    /// Whether views can be saved, changed and deleted now. A view is written to the server at once, never queued.
    var canEditViews: Bool { get }
    /// How many days an item stays in Recently Deleted, where the library sets it.
    var trashDays: Int? { get }
    /// What the library has yet to send, and each write that needs the person. An item's own state is its `sync`.
    var syncReport: SyncReport { get }
    var downloadedFiles: (any DownloadedFiles)? { get }
    /// False where the action is not offered for the problem.
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool
    var now: () -> Date { get }

    // MARK: Reading

    func item(_ id: ItemID) -> Item?
    func items(in place: SidebarItem) -> [Item]
    /// What the library's own search finds for `query` in `scope`, best match first: the items not deleted, the
    /// excerpt of each that has one, and whether the search may be missing items because the copy is still filling.
    /// Nothing is found for a query with no words.
    func search(_ query: String, in scope: SearchScope) -> SearchResults
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
    /// The `[[link]]` that the text of `source` can hold and the library resolves, from that note, to this item and
    /// no other, or nil when no spelling does. A name `source` already links keeps its first target, so it is not
    /// used for another item.
    func bodyLink(to id: ItemID, in source: ItemID?) -> String?
    /// What `link` written in the note `source` names. Its name may be a title, a path or an identity. The library
    /// answers as it reads links itself, by what the copy bound that very link to, so the app and the library never
    /// disagree about which note a link opens. A link names a note only when the answer is `resolved`; `missing` is
    /// the one that names none at all.
    func resolveLink(_ link: NoteLink, in source: ItemID) -> NoteReferenceResolution
    /// The property keys of the item that the inspector never lists: what the page shows as the title and the text,
    /// and any a library keeps for its own use.
    func hiddenPropertyKeys(of item: Item) -> Set<String>
    func relationships(for id: ItemID) -> [ItemRelationship]
    func relationshipCandidates(for id: ItemID, field: String) -> [Item]
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget]
    func creationParentCandidates(typeID: String) -> [Item]

    // MARK: History

    /// Where an item's earlier versions are read, or nil where the library keeps none. Reading them can fail while
    /// the rest of the library works, as when the server is out of reach.
    var history: (any ItemHistorySource)? { get }

    // MARK: Collections

    /// The active collections, by title: items whose type plays Marfa's `container` role (`Catalogue.isCollection`).
    var collections: [Item] { get }
    /// Files each item in the collection with one `in-collection` edge, skipping those already in it. Nothing is
    /// written when any item can't be a member, as a collection can't, and the library tells the person why.
    @discardableResult
    func addToCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool
    /// Removes the items' `in-collection` edges to the collection; false when none of them is in it.
    @discardableResult
    func removeFromCollection(_ ids: Set<ItemID>, _ collection: ItemID, undoManager: UndoManager?) -> Bool

    // MARK: Files

    /// A file item's file, fetched first; nil for an item that is not a file.
    func fileURL(of id: ItemID) async throws -> URL?

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
    /// Every note being written is left and every change handed over, as the app quits or the library changes:
    /// returns once each is kept on this Mac, never waiting on a server.
    func finish() async
    /// Whether the create of `id` was refused before the library held the item, so the window has no item to open and the
    /// library has told the person. A library that refuses a create at once answers nil from `createItem` instead.
    func wasRefused(creating id: ItemID) -> Bool
    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool
    @discardableResult
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool
    /// Moves each item to `type`, its title and text to the new type's keys in the same edit, with `filling` for
    /// the required fields an item lacks (`TypeChange`). Fields the new type does not use stay on the item. A set
    /// any of whose items cannot become `type` is refused whole, and the library tells the person why. Undo moves
    /// them back. False where the set is refused before anything is sent.
    @discardableResult
    func changeType(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?) -> Bool
    /// Puts the text and title of an earlier version (`restoreCheck`) on the item as a new edit, made on the version
    /// the library holds now, so what it replaces stays in the item's history. Undo puts back what it replaced, if the
    /// item still holds what the restore wrote. False where nothing is sent, and the library tells the person why
    /// unless there was nothing to change.
    @discardableResult
    func restoreVersion(_ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?) -> Bool
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?)
    /// The tags the library sets itself, which the person neither adds nor removes by hand: the favorite tag, which
    /// the Favorite command owns, and any a library keeps for its own use.
    var reservedTags: Set<String> { get }
    /// Every tag the active items carry, reserved ones left out, the most used first and then by name, for
    /// suggesting a tag the person has used.
    var knownTags: [String] { get }
    /// Tags `tag` to each of the items that can take it and do not hold it, in one undoable change, and answers nil.
    /// Nothing is sent, and the refusal is given back, where `tag` is not a tag Marfa takes, is reserved, is held
    /// by every item, or would leave an item with too many (`checkedTag`). The caller keeps what the person typed.
    @discardableResult
    func addTag(_ tag: String, to ids: Set<ItemID>, undoManager: UndoManager?) -> ItemTag.Refusal?
    /// Removes `tag` from each of the items that hold it. An item that no longer holds it, as when another device
    /// removed it first, is left alone.
    func removeTag(_ tag: String, from ids: Set<ItemID>, undoManager: UndoManager?)
    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?)
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?)
    /// Not undoable, so the views confirm it first, and only where `canPurge`.
    func deletePermanently(_ ids: Set<ItemID>)
    /// Files the note points at, such as pasted images, with the links the page writes for them. A library that
    /// sends them elsewhere may have to wait, and may fail.
    /// A failure means nothing was inserted into the note, though files already stored may remain; the editor's
    /// alert says so plainly.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed]
    /// Attaches the file at `file` to the item, read where it is while this runs, and says what the item's text
    /// writes to show it. A failure means the file is not attached.
    func attach(file: URL, to id: ItemID) async throws -> Embed

    // MARK: Views

    // Each tells the person why a write failed, in the server's reason, and nothing else changes.
    /// The view as the server saved it, or nil.
    func createView(_ settings: LibraryViewSettings) async -> LibraryView?
    /// Sent at `baseVersion`, the version of the view the window read.
    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure>
    /// For good and for every app, since a view has no bin, so the views confirm it first.
    func deleteView(_ view: ItemID) async -> Bool
}

extension ItemLibrary {
    var downloadedFiles: (any DownloadedFiles)? { nil }
    var history: (any ItemHistorySource)? { nil }

    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        createItem(typeID: typeID, title: title, body: body, properties: [:], parentID: parentID, in: place, undoManager: undoManager)
    }
    func hiddenPropertyKeys(of item: Item) -> Set<String> { catalogue.pageKeys(of: item) }

    /// The title as a link where it is this note's alone, as the library's links compare names, and the note it is
    /// written in has not already bound that name to another. Otherwise the item's identity with its title as the label
    /// (`[[identity|Title]]`), which Marfa reads as naming the identity.
    func bodyLink(to id: ItemID, in source: ItemID?) -> String? {
        guard let target = item(id), !target.isFile else { return nil }
        let established = source.flatMap { item($0)?.establishedLinks } ?? [:]
        if NoteLinks.canName(target.title), established[NoteLinks.nameKey(target.title)].map({ $0 == id }) ?? true {
            let key = NoteLinks.nameKey(target.title)
            let shared = items(in: .allNotes).contains {
                $0.id != id && !$0.isFile && NoteLinks.nameKey(NoteName.trimmed($0.title)) == key
            }
            if !shared { return NoteLinks.link(to: target.title) }
        }
        return NoteLinks.looksLikeIdentity(id.rawValue) ? NoteLinks.identityLink(to: id.rawValue, titled: target.title) : nil
    }

    /// Erases what the person confirmed, if the library still can: a Marfa library cannot while its server is out
    /// of reach, which may have begun while the dialog was open. Otherwise nothing is erased, and the person is told.
    func deletePermanentlyOnConfirm(_ ids: Set<ItemID>) {
        guard canPurge else {
            notices.tell(
                String(localized: "Can’t Delete Immediately"),
                String(localized: "Notes can’t be deleted immediately right now. They’re still in Recently Deleted."))
            return
        }
        deletePermanently(ids)
    }

    /// Whether the person can give the item a title. A title is kept only as a property, so an item titled by its
    /// first line takes its title from its text.
    func canSetTitle(of item: Item) -> Bool {
        guard item.isEditable else { return false }
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

    /// The tag as it would be kept and the items it would be added to, or why it can't be added: what Marfa
    /// refuses (`items/tag-text`, `items/tag-dot-segment`, `items/tags-count`), a tag the library sets itself, and
    /// items that can't be changed. A set where some item can't hold one more tag is refused whole.
    func checkedTag(_ text: String, adding ids: Set<ItemID>) -> Result<(tag: String, ids: Set<ItemID>), ItemTag.Refusal> {
        let tag = ItemTag.normalized(text)
        if let refusal = ItemTag.refusal(of: tag) { return .failure(refusal) }
        if tag == ItemTag.favorite { return .failure(.favorite) }
        if reservedTags.contains(tag) { return .failure(.reserved) }
        let editable = ids.compactMap { item($0) }.filter(\.canEditTags)
        guard !editable.isEmpty else { return .failure(.cantEdit) }
        let lacking = editable.filter { !$0.tags.contains(tag) }
        guard !lacking.isEmpty else { return .failure(.alreadyHas) }
        guard lacking.allSatisfy({ $0.tags.count < ItemTag.maxPerItem }) else { return .failure(.full) }
        return .success((tag, Set(lacking.map(\.id))))
    }

    /// Whether the item can be filed in a collection: an active item the library can write, of a type the catalogue
    /// lets join one. A collection can't.
    func canJoinCollection(_ item: Item) -> Bool {
        item.state == .active && item.problem == nil && catalogue.canJoinCollection(item.type)
    }

    /// What Add to Collection and Remove from Collection act on: the whole selection, files too, less the items that
    /// can't be filed in a collection. They never take only the notes, as the note commands do.
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
        item.tier == .feed ? String(localized: "Inbox") : TypeSymbol.label(for: item.type, in: catalogue)
    }
}
