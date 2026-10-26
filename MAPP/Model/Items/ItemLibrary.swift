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
    /// Every item not deleted whose title or text has the query.
    func items(matching query: String) -> [Item]
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
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?)
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

    /// What a flat list of items, such as the palette or the link picker, says beside a title: Inbox for an item
    /// waiting there, otherwise its type.
    func placeLabel(of item: Item) -> String {
        item.tier == .feed ? String(localized: "Inbox") : TypeSymbol.label(for: item.type, in: catalogue)
    }
}
