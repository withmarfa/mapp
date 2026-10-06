import Foundation
import Observation

/// Everything the views, the commands and the editor use of a library, so none of them knows which kind holds the
/// items. `NoteLibrary` is the folder of markdown files; a Marfa library is to be another.
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
    /// A file item's file, to show, share or open.
    func fileURL(for id: ItemID) -> URL?
    /// Where the item is kept, relative to `folderURL`.
    func path(of id: ItemID) -> String?
    /// The name Rename Note offers.
    func fileName(of id: ItemID) -> String?
    /// Where a note's relative links start, relative to `folderURL`.
    func imageBase(of id: ItemID) -> String?

    // MARK: Writing

    /// Nil when the item cannot be made, for which `failure` says why.
    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID?
    /// Typing is undone by the page that holds it, so this registers nothing.
    func updateBody(of id: ItemID, to body: String)
    /// The note is no longer on the page.
    func leave(_ id: ItemID)
    /// Every note being written is left and every change handed over, as the app quits or the library changes.
    func finish()
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
    func renameNote(_ id: ItemID, to name: String, undoManager: UndoManager?)
    /// Files the note points at, such as pasted images, with the links the page writes for them.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) -> [Embed]
    func importFiles(_ sources: [URL], folderID: ItemID?, requestID: UUID)
    func consumeImportCompletion(_ requestID: UUID)

    // MARK: Folders

    @discardableResult
    func newFolder(undoManager: UndoManager?) -> Folder
    func rename(_ id: ItemID, to name: String, undoManager: UndoManager?)
    func deleteFolder(_ id: ItemID, undoManager: UndoManager?)
    func moveFolders(_ ids: [ItemID], before target: ItemID?, undoManager: UndoManager?)
}

extension ItemLibrary {
    /// A library that sends nothing has nothing waiting.
    var syncReport: SyncReport { SyncReport(queueRead: true) }
}
