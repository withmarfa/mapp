# MAPP

<img src="Design/AppIcon.png" width="128" alt="">

A native macOS items app: a sidebar, a list and a page, in the manner of Notes and Mail.

Requires macOS 27 and Xcode 27. Open `MAPP.xcodeproj` and run the `MAPP` scheme, or see `AGENTS.md` for the command line.


## Item interface

The sidebar starts with Inbox, Recents (the items edited most recently), Items, Sources, Collections and Favorites. Items includes files. Sources and Collections open indexes, without expanding inside the sidebar. Sources lists the identifiers observed on readable active items; Collections lists, two levels deep, items that other items are filed under. Favorites remains available when empty. Types follows for a Marfa library, nested by identifier: Task and Bug fold open under Ticket, and Session and Log under Agent. Edit opens a picker for which types appear. A notes folder shows its Folders instead. Views follows as an unwired interface pending shared-view support in the SDK; it stores no views locally.

The header has a profile icon and instance menu, with Search beside it. New shares the sidebar toggle's toolbar row. Until the SDK exposes the instance name, the header displays the configured host. The menu opens Settings, Recently Deleted and the Console in the browser. Search opens the library search palette. The footer shows Offline while disconnected and takes no space while connected. Settings > Sidebar controls visibility and order per library; hidden destinations remain in the command palette, and new types appear by default.

Details in the page toolbar opens the native inspector; View > Show Details provides the same action. New opens a type menu, then an Untitled page. When the sidebar is hidden, the content toolbar offers the same menu. File > New Item opens the draft directly. Choose its optional parent, then press Return in the title or click the content area to start writing. Draft input stays in that window when you navigate away; Continue Draft retains its type and text. File > Import Files creates a separate file item, while Add Attachment embeds an image in a Markdown document. Property and relationship edits use the selected library. In Details, a field that recommends values offers those values and Other…, and a date field offers a calendar and Today. A Marfa item also shows Made by. Markdown uses InkKit; plain-text files use a readable native page, and other files use native viewing or opening.

The title and the pinned properties under it (type, status and parent) scroll with the note's body. When the header scrolls away, a compact title appears at the leading edge of the toolbar. The list column's toolbar groups Search and View Options; New Item appears separately when the sidebar is hidden. Back and Forward remain in the View menu and shortcuts (⌘[ and ⌘]), without toolbar buttons. The system sidebar toggle shows and hides the sidebar. Share and More are grouped on the right, with Details separate at the far edge. These actions move above the inspector column while it is open. Format remains in the Format menu and command palette, and Customize Toolbar can add it back. More holds Open in New Window, Share, Add to Favorites, Move To, Add Attachment (⇧⌘A), Rename, Page Width, Show Markdown Source, Print (⌘P), Export as PDF and Delete. Selecting a note opens it at the top. Format commands reflect the active text selection; source editing shows Markdown syntax. An empty list leaves the content pane blank; a populated list with no selection shows “Select an item”. Search List (⌥⌘F) expands across the list column, with a trailing close button that also works when the search is empty.

View Options > Gallery (⌘2) replaces the list and page with a grid beside the sidebar, as Photos does. Cards show a local embedded image when one is available, or a text preview. View Options > List (⌘1) restores the three-column workspace. View Options also sorts by Date Edited, Date Created or Title and groups by date. The View menu (View as List and View as Gallery) and the command palette offer the same choices. The gallery's toolbar groups Search, View As and View Options, with New Item available when the sidebar is hidden. Details and More stay in place and are disabled when nothing is selected. Click to select; Command-click toggles an item and Shift-click extends the selection. Arrow keys move through the grid, Shift-arrow extends selection, and Command-A selects all visible items. Double-click or Return opens one item in the same window; Back to Gallery (⌘[) returns. Search, sorting, favorites, folder navigation, item actions, and drafts use the same browser state in both views. Each window restores its view mode.

The item list defaults to 350 points and can be resized. Settings (⌘, or the instance menu) opens in the main window: the sidebar stays, the list column shows Appearance, Editor, Sidebar, Library and About, and the chosen page occupies the detail column. Leaving Settings preserves the draft and list width. The command palette lists each page as Settings: followed by its name. Library holds the server connection, notes folder and changes that need attention. Recently Deleted is a separate destination with List, Gallery and Table layouts, plus restore and permanent-delete actions. Appearance > Base Text Size scales interface text, including the sidebar, list and inspector. Editor > Text Size controls page text separately.

File-backed items use the workbench definitions as interim input. Files without a Markdown envelope expose their file information, but do not claim editable properties that the folder cannot persist.

## Editing and export

Plain-text file items open as selectable, read-only pages using the note text-size and reading-width settings. Their content stays literal, including Markdown punctuation and line breaks, and opening them never rewrites their bytes. UTF-8 and BOM-marked UTF-16/32 are supported. Files larger than 4 MiB, unknown encodings, and binary content use the system preview with Open instead of showing a truncated document. Editing a file's stored bytes is not yet supported.

View and the command palette switch between formatted and source editing. Native Find and Replace work with the active editor. Local images, audio, and video preview inline with the existing file-access protections. PDFs show a card with Open to view the document in its native app, because WebKit cannot display them in the protected editor frame. Note references open source editing; they do not embed the referenced note.

Typing `/` on an empty line opens a menu of blocks, such as headings, lists, a table, a quote and a code block, and Link to Note, which asks which note to link to and writes a link that names that note and no other. Typing `[[` offers the titles of the library's notes, leaving out a title that more than one note goes by. Typing a row such as `| Name | Date |` and pressing Return or Tab makes a table, and Option-Up and Option-Down move the block at the caret. The page makes no smart quotes or dashes of its own; the system's Substitutions setting applies as it does in any Mac text field.

Print and Export as PDF render a complete snapshot of the note, including local images. Other attachments use readable descriptions. PDF export is limited to 200 pages or 64 MB; a failed export leaves an existing destination unchanged.

## Reviewing components in Xcode

The native view preview adds **Board** (⌘4) and **Agenda** (⌘5) to View As. Board groups by a choice or recommended-text field from the items' catalogue, supports validated moves and undo, and offers comfortable and compact cards. Agenda groups a selected date field into days and keeps undated or invalid values visible; rescheduling is not implemented. Both open an item in place and return to the same collection. They use temporary per-window layout choices, not shared saved Views.

Debug builds include **Window > Interface Studies**, with fictional reading, highlight, search and collection pages. See [Native view studies](Design/Native%20view%20studies.md) for controls, limitations and the disposable sample tour.

Open `MAPP.xcodeproj`, choose the `MAPP` scheme, and open `MAPP/Views/ItemPreviewFixtures.swift`. Enable Editor > Canvas and resume a named preview. These previews use fixed sample items and an in-memory library; they do not read or write a person's working folder.

- **Grouped Sidebar** in `Sidebar.swift` shows the native disclosure groups and the Favorites destination. **Sidebar: 100 Collections** exercises long labels, scrolling, the header, and footer in a native split view.
- **Settings: Appearance** and its five siblings in `SettingsPreviews.swift` show each Settings page in the window, on the in-memory library.
- **Editable Page Header** and **Long Title and Narrow Page** in `ItemPageHeader.swift` show inline title editing and status/parent controls.
- **Ticket Details** and **Project and Related Work** show dynamic properties and relationships.
- **Missing and Unfamiliar Values** shows unresolved targets and preserved unfamiliar properties.
- **Relationship Selection** and **New Item** expose the native editing flows.
- **Complete Item Window** renders the actual split view, toolbar, editor, and inspector against the in-memory library.
- **Unsaved Property Input** lets a rejected save be exercised by editing the field and committing it.

`MAPP/Views/ItemProperties.swift` also previews the individual property controls. `MAPP/Views/FileItemContent.swift` contains the file-view previews. Review the real app for editor behavior, window resizing, keyboard navigation, and saved-file persistence; the component canvas is for iterating on each piece.
