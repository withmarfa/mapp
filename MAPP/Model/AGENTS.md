# Model

The data model, free of SwiftUI: the `ItemLibrary` protocol and its two libraries, `NoteLibrary` over a notes folder and `MarfaLibrary` over a Marfa server, and `Libraries`, which chooses between them. Before changing `Marfa/`, also read `MAPP/Model/Marfa/AGENTS.md`.

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

## Changing libraries and quitting

- `Libraries` owns the notes folder, the `MarfaHost`, and the library the windows read: the host's `MarfaLibrary` while its copy is open, otherwise the folder's `NoteLibrary`. With no server set, nothing about Marfa shows.
- A server whose copy is not open (MAPP is signed out, or the copy cannot be opened) is never answered with the folder. The window says so and points to Settings, and windows wait while a copy reopens.
- Before the host changes which library the windows read, and before the app quits, `Libraries.flushEditors` has every open page hand over its last edit, and each library keeps its writes on this Mac: on disk, or in the Marfa copy's queue (`ItemSource.queueSubmitted`). It never waits on the server, so quitting offline is not held up. Every window's unsaved titles are saved first, and a title still refused cancels the quit or the library change and names the item (see `MAPP/Editor/AGENTS.md`). Quitting waits a few seconds at most; a flush that fails or runs out of time cancels the quit. Choosing another notes folder in Settings flushes the open pages first in the same way (`EditorController.flushAll`).
- A main window's `Browser` sits above the library, in `RootView`. A change of library resets the window (`Browser.adopt`: selection, place, search, renaming, and the window's undo), since they name items the other library may not hold. A draft the person was writing is kept; once the new library has loaded, `Browser.fitDraft` removes a parent or item type it lacks and tells the person.
- A new item appears when its library says so, not when the create is sent. `Browser.createDraft` holds the draft, read-only, until `finishCreation` finds the item. A refused create gives the draft back to edit and send again.

## Code Review Rules

- **Folder Marfa cannot read.** Flag a change that re-emits front matter, drops or reorders a property, writes a tag form Marfa reads differently, or puts app data inside the notes folder.
- **Path as identity.** Flag code that stores or restores an item by path instead of `ItemID`.
- **Write that skips the store's order.** Flag a file write outside `FolderStore`'s ordered, coordinated changes.
- **Unflushed switch.** Flag a change of library or a quit that does not first flush the open pages (`Libraries.flushEditors`, or `EditorController.flushAll` for a notes folder change), or that goes ahead when the flush fails. A window close waits for its editor's flush the same way (`EditorCloseDelegate`).
