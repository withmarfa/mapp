# MAPP

<img src="Design/AppIcon.png" width="128" alt="">

A native macOS markdown notes app for a Marfa library: a sidebar, a list and a page, in the manner of Notes and Mail. MAPP reads and writes only through a Marfa server. Until you set one, the window asks you to connect to your Marfa, and Connect opens Settings > Library.

Requires macOS 27 and Xcode 27. Open `MAPP.xcodeproj` and run the `MAPP` scheme, or see `AGENTS.md` for the command line.

## Signing

A checkout builds and runs without a developer account: Xcode signs it to run locally. To sign with your own team, create `Config/Local.xcconfig`, which git ignores, with your team ID:

```
DEVELOPMENT_TEAM = <your team ID>
```

`Config/Signing.xcconfig` includes it when it exists. Don't commit a team ID.

## Item interface

The sidebar starts with Inbox, Recents (the items edited most recently) and Favorites, then a Browse section with Items, Sources and Collections. Items includes files. Sources and Collections open indexes, without expanding inside the sidebar. Sources lists the identifiers observed on readable active items; Collections lists, two levels deep, items that other items are filed under. Favorites remains available when empty. Types follows, nested by identifier: Task and Bug fold open under Ticket, and Session and Log under Agent. Edit, shown while the pointer is over the heading, opens a picker for which types appear, with Show All. Views follows, listing the views saved on the instance by title; selecting one lists the items it matches that this Mac holds. MAPP reads views but does not create or change them, and the section is hidden when the instance has none.

The instance sits in a row pinned at the foot of the sidebar: its name (the one the server gave itself, or its host until one has been read), a dot after it that is orange while connecting and red while the server cannot be reached, and three buttons for the Console in the browser, Settings and Recently Deleted. A click on the name opens Settings at Library, where the server is changed or left. The list starts with Inbox, Recents and Favorites, then a Browse section with Items, Sources and Collections, then Types, whose Edit control shows while the pointer is over the heading, then Views. Search is on ⌘K and ⇧⌘P and in each list. New shares the sidebar toggle's toolbar row. Settings > Sidebar controls visibility and order per library; hidden destinations remain in the command palette, and new types appear by default.

Details in the page toolbar opens the native inspector; View > Show Details provides the same action. New opens a type menu, and choosing a type makes the item at once and opens it in the page with its title selected, as Notes does. When the sidebar is hidden, the content toolbar offers the same menu. File > New Item makes an item of the type the list shows, or a note. Type to name it, press Return to start writing, and set its optional parent from the Parent pin in the page. The type cannot change after the item is made. An item left completely empty is moved to Recently Deleted when you select another item, close the window or quit; an item with a changed title, text, tags, connections or other properties stays. Add Attachment embeds an image in a Markdown document. In Details, a field that recommends values offers those values and Other…, and a date field offers a calendar and Today. Details also shows Made by. Markdown uses Inkkit; plain-text files use a readable native page, and other files use native viewing or opening.

The title and the pinned properties under it (type, status and parent) scroll with the note's body. When the header scrolls away, a compact title appears at the leading edge of the toolbar. The list column's toolbar groups Search and View Options; New Item appears separately when the sidebar is hidden. Back and Forward remain in the View menu and shortcuts (⌘[ and ⌘]), without toolbar buttons. The system sidebar toggle shows and hides the sidebar. Share and More are grouped on the right, with Details separate at the far edge. These actions move above the inspector column while it is open. Format remains in the Format menu and command palette, and Customize Toolbar can add it back. More holds Open in New Window, Share, Add to Favorites, Add Attachment (⇧⌘A), Page Width, Show Markdown Source, Print (⌘P), Export as PDF and Delete. Selecting a note opens it at the top. Format commands reflect the active text selection; source editing shows Markdown syntax. An empty view says so in a short title with no icon, and an empty list leaves the content pane blank; a populated list with no selection shows “Select an item”. Search List (⌥⌘F) expands into a glass search field across the list column. The field has a clear button once it holds text; Escape, or leaving it empty, puts the Search button back.

View Options > Gallery (⌘2) replaces the list and page with a grid beside the sidebar, as Photos does. Cards show a text preview. View Options > List (⌘1) restores the three-column workspace. View Options also sorts by Date Edited, Date Created or Title and groups by date. The View menu (as List, as Gallery, as Table, as Board and as Agenda, worded as the Finder's View menu is) and the command palette offer the same choices. The gallery's toolbar has View Options, Search (its own item, which grows leftwards into a field and collapses again) and View As, with New Item available when the sidebar is hidden. Details and More stay in place and are disabled when nothing is selected. Click to select; Command-click toggles an item and Shift-click extends the selection. Arrow keys move through the grid, Shift-arrow extends selection, and Command-A selects all visible items. Double-click or Return opens one item in the same window; Back to Gallery (⌘[) returns. Search, sorting, favorites, sidebar places, item actions, and new items use the same browser state in both views. Each window restores its view mode.

The item list defaults to 350 points and can be resized. Settings (⌘, or the sidebar's Settings button) opens in the main window: the sidebar stays, the list column shows Appearance, Editor, Sidebar, Library and About, and the chosen page occupies the detail column. Leaving Settings preserves the selection and list width. The command palette lists each page as Settings: followed by its name. Library holds the server connection and changes that need attention. Recently Deleted is a separate destination with List, Gallery and Table layouts, plus restore and permanent-delete actions. Appearance > Base Text Size scales interface text, including the sidebar, list and inspector. Editor > Text Size controls page text separately.

## Offline library and downloads

The library fills automatically with every non-system type in both tiers. Items appear as they arrive, and Settings > Library shows the number listed and the expected total, when known. Interrupted fills resume automatically. An out-of-date copy remains readable and editable while it refills; edits wait in its queue.

Settings > Library > Downloaded Files shows the space used, the current limit, and attachment availability. Choose Automatic, a size, or Keep All Downloads. Remove Downloaded Files clears expendable downloads, preserving attachments, pending uploads, and files currently being read. Closing the library waits for removal to restore the chosen limit. Attachments are fetched separately after every fill and catch-up, retried when the server reconnects and when replay brings an attachment, and stay outside the limit. Downloads do not hold up queued edits or a flush. Missing attachments are counted with their reasons. A file larger than the limit can still open while disk space allows.

## Editing and export

Plain-text file items open as selectable, read-only pages using the note text-size and reading-width settings. Their content stays literal, including Markdown punctuation and line breaks, and opening them never rewrites their bytes. UTF-8 and BOM-marked UTF-16/32 are supported. Files larger than 4 MiB, unknown encodings, and binary content use the system preview with Open instead of showing a truncated document. Editing a file's stored bytes is not yet supported.

View and the command palette switch between formatted and source editing. Native Find and Replace work with the active editor. Embedded images, audio, and video don't show yet: MAPP doesn't read a note's attachments from the library, so each embed shows as missing. Note references open source editing; they do not embed the referenced note.

Typing `/` on an empty line opens a menu of blocks, such as headings, lists, a table, a quote and a code block, and Link to Note, which asks which note to link to and writes a link that names that note and no other. Typing `[[` offers the titles of the library's notes, leaving out a title that more than one note goes by. Typing a row such as `| Name | Date |` and pressing Return or Tab makes a table, and Option-Up and Option-Down move the block at the caret. The page makes no smart quotes or dashes of its own; the system's Substitutions setting applies as it does in any Mac text field.

Print and Export as PDF render a complete snapshot of the note. Attachments use readable descriptions. PDF export is limited to 200 pages or 64 MB; a failed export leaves an existing destination unchanged.

## Reviewing components in Xcode

**Board** (⌘4) and **Agenda** (⌘5) are available in View As where the place can use them: View As, the View menu and the palette leave out Board when the place's items have no choice or recommended-text field, and Agenda when they have no date field, and a window left on one that its place cannot show returns to List. Board groups by a choice or recommended-text field from the items' catalogue, supports validated moves and undo, and offers comfortable and compact cards. Agenda groups a selected date field into days and keeps undated or invalid values visible; rescheduling is not implemented. Both open an item in place and return to the same collection. They use temporary per-window layout choices, not shared saved Views.

For a disposable sample tour, launch a Debug build with `-MAPPSampleLibrary -MAPPCollectionSample`. It starts on eight sample tasks in Board. Select the Event type and choose as Agenda in View As to see dated and undated sessions. The sample library is held in memory for the run; it connects to no server.

Open `MAPP.xcodeproj`, choose the `MAPP` scheme, and open `MAPP/Views/ItemPreviewFixtures.swift`. Enable Editor > Canvas and resume a named preview. These previews use fixed sample items and an in-memory library; they do not read or write a person's library.

- **Sample Sidebar** and **Sidebar Without Favorites** in `Sidebar.swift` show the native disclosure groups with and without the Favorites destination. **Sidebar: 100 Collections** exercises long labels, scrolling, the header, and footer in a native split view.
- **Settings: Appearance** and its four siblings in `SettingsPreviews.swift` show each Settings page in the window, on the in-memory library.
- **Ticket Details** and **Project and Related Work** show dynamic properties and relationships.
- **Missing and Unfamiliar Values** shows unresolved targets and preserved unfamiliar properties.
- **Relationship Selection** exposes the native editing flow for connections.
- **Complete Item Window** renders the actual split view, toolbar, editor, and inspector against the in-memory library.
- **Unsaved Property Input** lets a rejected save be exercised by editing the field and committing it.

`MAPP/Views/ItemProperties.swift` also previews the individual property controls. `MAPP/Views/FileItemContent.swift` contains the file-view previews. Review the real app for editor behavior, window resizing, keyboard navigation, and saving; the component canvas is for iterating on each piece.

## License

MAPP is licensed under the Apache License 2.0. See [LICENSE](LICENSE). `editor/src/style.css` is adapted from another project and keeps its own MIT license notice.
