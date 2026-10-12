import Foundation
import Observation

/// Everything the views, the commands and the editor use of a library, so none of them knows which kind holds the
/// items. `NoteLibrary` is the folder of markdown files; `MarfaLibrary` is a Marfa server's working copy.
///
/// Members that only make sense for files answer nil, or nothing, in a library whose items are not files, and a
/// write a library cannot make is left out of its `capabilities`, so a view dims the command rather than asking.
@MainActor
protocol ItemLibrary: AnyObject, Observable {
    // MARK: State

    /// Whether the items have been read, so a window restores what it showed only once there is something to find.
    var isLoaded: Bool { get }
    /// Something the library could not do, to tell the person; the window in front takes it and clears it.
    var failure: (title: String, message: String)? { get set }
    /// Items a person has asked to erase for good, until a window asks them to confirm.
    var notesToPurge: Set<ItemID> { get set }
    var folders: [Folder] { get }
    var catalogue: Catalogue { get }
    var capabilities: SourceCapabilities { get }
    /// How many days an item stays in Recently Deleted, where the library sets it.
    var trashDays: Int? { get }
    /// What the library has yet to send, and each write that needs the person. An item's own state is its `sync`.
    var syncReport: SyncReport { get }
    /// False where the action is not offered for the problem.
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool
    var completedImports: [UUID: ItemID] { get }
    var now: () -> Date { get }

    // MARK: Reading

    func item(_ id: ItemID) -> Item?
    func items(in place: SidebarItem) -> [Item]
    /// Every item not deleted whose title or text has the query.
    func items(matching query: String) -> [Item]
    func count(in place: SidebarItem) -> Int
    func name(of place: SidebarItem) -> String
    func folder(_ id: ItemID) -> Folder?
    /// Nil for an item in no folder.
    func folder(of item: Item) -> Folder?
    /// Whether a window kept for this item has nothing left to show, which is known only once the items are read.
    func isGone(_ id: ItemID?) -> Bool
    /// The items to open in windows of their own, each left first so its name is current.
    func idsForWindows(_ ids: some Collection<ItemID>) -> [ItemID]
    /// Nil for an item with no text, such as a file.
    func body(of id: ItemID) -> ItemBody?
    func relationships(for id: ItemID) -> [ItemRelationship]
    func relationshipCandidates(for id: ItemID, field: String) -> [Item]
    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget]
    func creationParentCandidates(typeID: String) -> [Item]
    func isItemTitleTaken(_ title: String) -> Bool
    func isNoteNameTaken(_ name: String, for id: ItemID) -> Bool
    func isFolderNameTaken(_ name: String, except id: ItemID?) -> Bool

    // MARK: Files, nil where the items are not files

    /// The folder relative links in a note resolve within.
    var folderURL: URL? { get }
    /// A file item's file, to show, share or open, where it is at hand.
    func fileURL(for id: ItemID) -> URL?
    /// A file item's file, fetched first where it is not at hand.
    func fileURL(of id: ItemID) async throws -> URL?
    /// Where the item is kept, relative to `folderURL`.
    func path(of id: ItemID) -> String?
    /// The name Rename Note offers; only where `capabilities` has `renameFiles`.
    func fileName(of id: ItemID) -> String?
    /// Where a note's relative links start, relative to `folderURL`.
    func imageBase(of id: ItemID) -> String?

    // MARK: Writing

    /// Nil when the item cannot be made, for which `failure` says why.
    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID?
    /// Text typed on the page, over the text `body(of:)` gave at `readAt`. An edit typed on text older than the
    /// library now holds was made without seeing what replaced it, so it never silently overwrites that. Typing is
    /// undone by the page that holds it, so this registers nothing.
    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion)
    /// The note is no longer on the page.
    func leave(_ id: ItemID)
    /// Every note being written is left and every change handed over, as the app quits or the library changes:
    /// returns once each is kept on this Mac, never waiting on a server.
    func finish() async
    /// Whether the create of `id` was refused before the library held the item, so the draft it came from is the
    /// person's to send again. A library that refuses a create at once answers nil from `createItem` instead.
    func wasRefused(creating id: ItemID) -> Bool
    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool
    @discardableResult
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager?) -> Bool
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?)
    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?)
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?)
    /// Not undoable, so the views confirm it first, and only where `capabilities` has `purge`.
    func deletePermanently(_ ids: Set<ItemID>)
    /// Into a folder, or out of every folder with nil; only where `capabilities` has `move`.
    func move(_ ids: Set<ItemID>, to folderID: ItemID?, undoManager: UndoManager?)
    /// Names the item's file; only where `capabilities` has `renameFiles`. A title is edited with `setItemProperty`.
    func renameNote(_ id: ItemID, to name: String, undoManager: UndoManager?)
    /// Files the note points at, such as pasted images, with the links the page writes for them. A library that
    /// sends them elsewhere may have to wait, and may fail.
    /// A failure means nothing was inserted into the note, though files already stored may remain; the editor's
    /// alert says so plainly.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed]
    /// Only where `capabilities` has `importFiles`.
    func importFiles(_ sources: [URL], folderID: ItemID?, requestID: UUID)
    func consumeImportCompletion(_ requestID: UUID)

    // MARK: Folders, only where `capabilities` has `folders`

    @discardableResult
    func newFolder(undoManager: UndoManager?) -> Folder
    func rename(_ id: ItemID, to name: String, undoManager: UndoManager?)
    func deleteFolder(_ id: ItemID, undoManager: UndoManager?)
    func moveFolders(_ ids: [ItemID], before target: ItemID?, undoManager: UndoManager?)
}

extension ItemLibrary {
    /// Erases what the person confirmed, if the library still can: a Marfa library cannot while its server is out
    /// of reach, which may have begun while the dialog was open. Otherwise nothing is erased, and the person is told.
    func deletePermanentlyOnConfirm(_ ids: Set<ItemID>) {
        guard capabilities.contains(.purge) else {
            failure = (
                String(localized: "Can’t Delete Immediately"),
                String(localized: "Notes can’t be deleted immediately right now. They’re still in Recently Deleted."))
            return
        }
        deletePermanently(ids)
    }

    /// Whether the person can give the item a title. A library with files names the file after any title; one
    /// without keeps a title only as a property, so an item titled by its first line takes its title from its text.
    func canSetTitle(of item: Item) -> Bool {
        guard item.isEditable else { return false }
        if case .firstLine = item.titleRule { return capabilities.contains(.renameFiles) }
        return true
    }

    /// Why the library refused a title, in the person's words.
    var titleRefusal: String {
        capabilities.contains(.renameFiles)
            ? String(localized: "The title could not be saved. Use a unique file name without slashes or line breaks.")
            : String(localized: "The title could not be saved. Enter a title.")
    }

    /// Whether Rename Note applies: it names a file, which a deleted note keeps as it is.
    func canRenameFile(of item: Item?) -> Bool {
        capabilities.contains(.renameFiles) && item?.isWritable == true
    }
}
