# Model

The data model, free of SwiftUI: the `ItemLibrary` protocol and its two libraries, `NoteLibrary` over a notes folder and `MarfaLibrary` over a Marfa server, and `Libraries`, which chooses between them. Views reach a library only through `ItemLibrary`: what a view needs to know about an item comes from the protocol, such as `hiddenPropertyKeys(of:)` (the keys an item's page already shows elsewhere, so Properties leaves them out) and `Item.source` (what made the item; nil where the library does not know, as a folder does not). Before changing `Marfa/`, also read `MAPP/Model/Marfa/AGENTS.md`.

## The notes folder

The folder is shaped so Marfa's folder device can sync it. Keep it readable by Marfa.

- Notes are `.md` files. Each directory at the top of the folder is a folder, and the files at the top are the Inbox. A name starting with a dot, such as `.marfa`, and the `Attachments` folder are not notes. The folder is remembered as a security-scoped bookmark.
- `NoteFile` keeps each file's envelope: front matter, byte-order mark, and Windows line endings. The page only ever sees the body.
- Front matter is found by Marfa's rule (`NoteFile.frontMatterLength`), edited line by line, and never re-emitted. Every property is kept as written, `marfa_id` among them.
- A note's title is its `title` property, otherwise its file name.
- A favorite is Marfa's ordinary `favorite` tag in `tags`, read by Marfa's rule (`NoteFile.tags`). `NoteFile.setFavorite` changes it in the form already there, reads the result again, and refuses tags Marfa cannot read or an edit that would change anything but that one tag; the person is told.
- A note's file is named after its first line. `NoteText.name(for:)` is the one place a file name is made safe. The file follows the line, but is renamed only once the person leaves the note, so Marfa sees one rename rather than one per word. A name given with Rename Note stops the following. A first line with characters a file name cannot hold is also kept whole as the `title` property.
- The trash and the identity ledger live in the app's own storage, never in the folder, since a file moved within the folder reads to Marfa as a rename.

## Identity

- `IdentityLedger` gives each note, file, and folder an `ItemID` that lasts across launches and renames, including renames made while the app is closed. An item is known again by its file's identity, then by its path. A copy is a new item.
- A lost ledger is rebuilt from the folder, which changes the identifiers once and costs only what windows restore. Never name an item by path in windows, selections, or drags.

## Writing files

- `NoteLibrary` decides every path and hands `FolderStore` one change at a time, which the store makes in order, off the main thread, coordinated with `NSFileCoordinator`, and whole.
- An edit typed on text the note no longer holds, because another app or window changed it, is kept beside the note as `<name> (Conflicted Copy).md`, and the person is told. Never write it over the other change.

## Library capabilities

- What only files have, such as a file's URL or the folder a note's links resolve in, answers `nil` in a library without files.
- A write a library cannot make is left out of its `capabilities` (`SourceCapabilities`), and the views dim or hide the command and refuse the drop. Moving, permanent deletion, renaming files, editing folders, and importing files each have one. Add a capability for a new write that only one library can make.
- Rename Note names a note's file, which only files have. A title is a property, which any library edits.

## The sidebar

- The sidebar starts with Inbox, Recents, Items, Sources, Collections and Favorites, followed by Types (a Marfa library) or Folders (a notes folder), then the unwired Views section. Items includes files. Favorites remains visible when empty unless hidden in the sidebar layout. Recents lists the `ItemLibrary.recentLimit` items edited last, so its row has no count. Sources and Collections open indexes without disclosure toggles. Types has an Edit popover using the existing per-library visibility settings. `SidebarLayout.collapsed` remembers folded sections and type rows. A row is a label and a symbol, never a sentence.
- The header's instance menu opens Settings, Recently Deleted and the browser Console, beside Search. New sits in the sidebar's toolbar row. Recently Deleted uses the ordinary item layouts and the library's restore and purge operations. Sources lists source identifiers observed on active readable items, not a complete registry of connected sources. Shared Views storage remains pending SDK support; do not add a local saved-view store.
- A collection is any item other items are filed under (`child-of`), whatever its type, so no type is special (`ItemLibrary.collectionTree`). The collection index shows two levels, by title. A collection's place lists what is below it, not itself. A list names an item's collection as the ancestor just below the top of its chain (`ItemLibrary.collection(of:)`).
- A library says what its sidebar holds, so no view tests for a library type: `ItemLibrary.itemTypeCounts` lists the catalogue's types that directly hold active items, file types aside, and `capabilities.contains(.folders)` says whether the sidebar shows Folders or Types. A type counts only its own items, never its subtypes, and its place lists exactly those, so the count is the list's length (`MarfaItemIndex.activeByType`; only Files takes subtypes). Labels come from the catalogue, symbols from `TypeSymbol`.
- Types nest by their identifiers below the vendor segment (`TypeNode.tree`): `aic.ticket.task` under Ticket, `aic.agent.session` under a group named Agent. A group of one gives way to its row; a nested row drops the words it repeats ("Session"). Siblings go by their branch's items, then label. A group, or a type with no items of its own, only folds open. Flat lists, such as the command palette and the toolbar's New menu (`ItemLibrary.creatableTypes`), tell two types with one label apart by their parent's, "Task (Ticket)" (`Catalogue.displayLabels`). A type whose last item goes has no row, so `Browser.folderRemoved` moves a window on its place to All Items. `WorkbenchSchema` is the notes folder's own schema and nothing else reads it for the sidebar or the type menus.
- `SidebarLayouts` keeps what the person hid, collapsed or moved, one `SidebarLayout` for each library (`Libraries.sidebarLayoutKey`). A place a layout does not mention, such as a new type, is shown after the placed ones. `SidebarPlan` is what the sidebar and Settings > Sidebar both read.

## The table

- The table view (`ItemTableLayout`) is worked out from the items a place shows, never stored: a column for each field their types declare, not the title or the text, leading with status, priority and assignee, then where each item is filed (Parent, Collection), then the rest, and Edited. A field few items fill, and the quiet ones (notes, url, place, precision), start hidden. A mixed table's column holds one type's field, so a cell offers its own type's values.
- A status sorts, groups and colors by its tone (`StatusTone`), so every type's word for it reads alike; the page header's ring follows the same tone (`PageHeader.Mark`). A place with statuses starts grouped by status with finished work folded, and ordered by priority, highest first. Empty cells sort last either way.
- What the person chooses (grouping, sort, filters, folded groups) is the window's, for each place (`Browser.tableOptions`); which columns show, in what order and width, is kept for each place in the defaults.

## Changing libraries and quitting

- `Libraries` owns the notes folder, the `MarfaHost`, and the library the windows read: the host's `MarfaLibrary` while its copy is open, otherwise the folder's `NoteLibrary`. With no server set, nothing about Marfa shows.
- A server whose copy is not open (a refused key, a copy that cannot be opened) is never answered with the folder. The window says so and points to Settings, and windows wait while a copy reopens.
- Before the host changes which library the windows read, and before the app quits, `Libraries.flushEditors` has every open page hand over its last edit, and each library keeps its writes on this Mac: on disk, or in the Marfa copy's queue (`ItemSource.queueSubmitted`). It never waits on the server, so quitting offline is not held up. Every window's unsaved titles are saved first, and a title still refused cancels the quit or the library change and names the item (see `MAPP/Editor/AGENTS.md`). Quitting waits a few seconds at most; a flush that fails or runs out of time cancels the quit. Choosing another notes folder in Settings flushes the open pages first in the same way (`EditorController.flushAll`).
- A main window's `Browser` sits above the library, in `RootView`. A change of library resets the window (`Browser.adopt`: selection, place, search, renaming, new items being followed, and the window's undo), since they name items the other library may not hold.
- New makes the item at once (`Browser.startNewItem`, the one path for the toolbar menu, ⌘N and the palette) through `ItemLibrary.createItem`, like any create, and opens it in the page with the title focused. It opens when its library says it holds it, not when the create is sent (`finishNewItem`); a Marfa library may take a moment, and a second New waits meanwhile. A create the library refuses is given up and the library tells the person. `Browser.newItems` follows each item New made until the person leaves it. When the page lets go of it (another item is selected, the window closes, or the app quits or changes library), `leaveNewItem` moves it to Recently Deleted if it still holds nothing the person put there (`NewItem.isUntouched`). An item counts as touched once the library has made any write to it after the create, or another item points at it (`ItemLibrary.wasTouched`: `MarfaLibrary` records the item each write names in `submit`, since its copy shows a title, a tag or a link only when the source reports it, and reads the connections held by other items; `NoteLibrary` takes each write into its copy at once, so it asks only for notes that link to the item). Whatever else changed the item shows in the copy, which is compared with the baseline taken when the library first showed it: the title it was made with, a blank body, and no tags, properties, connections or parent beyond it. A window closed by its button decides with `closing: true` like a quit, so an empty item goes at once. It is never purged. A create still queued cannot be withdrawn, since the working copy only withdraws blocked or refused writes, so an empty item is deleted after its create, and offline both writes wait in the queue.

## Code Review Rules

- **Folder Marfa cannot read.** Flag a change that re-emits front matter, drops or reorders a property, writes a tag form Marfa reads differently, or puts app data inside the notes folder.
- **Path as identity.** Flag code that stores or restores an item by path instead of `ItemID`.
- **Write that skips the store's order.** Flag a file write outside `FolderStore`'s ordered, coordinated changes.
- **Unflushed switch.** Flag a change of library or a quit that does not first flush the open pages (`Libraries.flushEditors`, or `EditorController.flushAll` for a notes folder change), or that goes ahead when the flush fails. A window close waits for its editor's flush the same way (`EditorCloseDelegate`).
