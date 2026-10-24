# MAPP

<img src="Design/AppIcon.png" width="128" alt="">

A native macOS markdown notes app: a sidebar, a list and a page, in the manner of Notes and Mail.

Requires macOS 27 and Xcode 27. Open `MAPP.xcodeproj` and run the `MAPP` scheme, or see `AGENTS.md` for the command line.


## Item interface

The sidebar keeps Inbox, Recents (the items edited most recently), All Items and, when the library holds any, Files at the top. For a Marfa library, Types lists the types in the library's catalogue that hold items, nested by their identifiers: Task and Bug fold open under Ticket, and Session and Log under Agent. A notes folder shows its Folders instead. Collections lists, two levels deep, every item that other items are filed under, whatever its type. Favorites follows, with shortcuts to individual items, and disappears when it has no items. Settings is a row at the foot of the sidebar, with a line above it that appears only when the server has something to say. Settings > Sidebar lists every place with a switch to show or hide it and drag, Move Up or Move Down to reorder, and a row's menu offers Hide from Sidebar; each library keeps its own choices, a hidden place stays in the command palette, and a type the catalogue gains shows by default. Details (the right sidebar button) in the page toolbar reveals the item's native inspector; View > Show Details provides the same action. New Item in the list column's toolbar or the File menu opens an Untitled page. Choose its type and optional parent, then press Return in the title or click the content area to start writing. Draft input stays in that window when you navigate away; New Item resumes it. File > Import Files creates a separate file item, while Add Attachment opens the image chooser to embed an image in a Markdown document. Property and relationship edits are saved to the selected folder. In Details, a field that recommends values is a menu of them with Other… for any value of your own, and a date field has a calendar button that appears under the pointer or the keyboard and offers Today. A Marfa item also shows Made by. Markdown uses InkKit through its public editor API; photos, PDFs, and other files use native viewing or opening.

The title and the pinned properties under it (type, status and parent) scroll with the note's body. When the header scrolls away, a compact title appears at the leading edge of the toolbar. The list column's toolbar holds View Options and Search together, then New Item. The page toolbar has Back and Forward at the leading edge of the page column, which move through the items this window has opened (⌘[ and ⌘]), and Details and More on the right. While the inspector is open, Details and More sit above the inspector column and the page toolbar keeps only Back and Forward. Format is out of the default toolbar but stays in the Format menu and the command palette, and Customize Toolbar can add it back. More holds Open in New Window, Share, Add to Favorites, Move To, Add Attachment (⇧⌘A), Rename, Page Width, Show Markdown Source, Print (⌘P), Export as PDF and Delete. Selecting a note opens it at the top. Format commands reflect the active text selection; source editing shows the Markdown syntax. An empty list leaves the content pane blank; a populated list with no selection shows “Select an item”. Search List (⌥⌘F) expands across the list column, with a trailing close button that also works when the search is empty.

View Options > Gallery (⌘2) replaces the list and page with a grid beside the sidebar, as Photos does. Cards show a local embedded image when one is available, or a text preview. View Options > List (⌘1) restores the three-column workspace. View Options also sorts by Date Edited, Date Created or Title and groups by date. The View menu (View as List and View as Gallery) and the command palette offer the same choices. The gallery's own toolbar holds View Options and Search, then Details and More, then New Item; Details and More appear once a card is selected. Click to select; Command-click toggles an item and Shift-click extends the selection. Arrow keys move through the grid, Shift-arrow extends selection, and Command-A selects all visible items. Double-click or Return opens one item in the same window; Back to Gallery (⌘[) returns. Search, sorting, favorites, folder navigation, item actions, and drafts use the same browser state in both views. Each window restores its view mode.

The note list defaults to 340 points and can be resized. Settings (⌘, or the Settings row at the foot of the sidebar) is a place in the main window: the sidebar stays, the list column shows the pages (Appearance, Editor, Sidebar, Library, Recently Deleted and About) and the page shows in the detail column, in grouped forms. Choosing any other place returns to the window as it was, with an unsubmitted draft and the note-list width kept. The command palette lists each page as Settings: followed by its name. Library holds the server connection, the notes folder and the changes that need you; Recently Deleted restores or erases deleted items. Appearance > Base Text Size scales interface text, including the sidebar, list, and inspector. Editor > Text Size controls note text separately.

File-backed items use the workbench definitions as interim input. Files without a Markdown envelope expose their file information, but do not claim editable properties that the folder cannot persist.

## Editing and export

Plain-text file items open as selectable, read-only pages using the note text-size and reading-width settings. Their content stays literal, including Markdown punctuation and line breaks, and opening them never rewrites their bytes. UTF-8 and BOM-marked UTF-16/32 are supported. Files larger than 4 MiB, unknown encodings, and binary content use the system preview with Open instead of showing a truncated document. Editing a file's stored bytes is not yet supported.

View and the command palette switch between formatted and source editing. Native Find and Replace work with the active editor. Local images, audio, and video preview inline with the existing file-access protections. PDFs show a card with Open to view the document in its native app, because WebKit cannot display them in the protected editor frame. Note references open source editing; they do not embed the referenced note.

Typing `/` on an empty line opens a menu of blocks, such as headings, lists, a table, a quote and a code block, and Link to Note, which asks which note to link to and writes a link that names that note and no other. Typing `[[` offers the titles of the library's notes, leaving out a title that more than one note goes by. Typing a row such as `| Name | Date |` and pressing Return or Tab makes a table, and Option-Up and Option-Down move the block at the caret. The page makes no smart quotes or dashes of its own; the system's Substitutions setting applies as it does in any Mac text field.

Print and Export as PDF render a complete snapshot of the note, including local images. Other attachments use readable descriptions. PDF export is limited to 200 pages or 64 MB; a failed export leaves an existing destination unchanged.

## Reviewing components in Xcode

Open `MAPP.xcodeproj`, choose the `MAPP` scheme, and open `MAPP/Views/ItemPreviewFixtures.swift`. Enable Editor > Canvas and resume a named preview. These previews use fixed sample items and an in-memory library; they do not read or write a person's working folder.

- **Grouped Sidebar** in `Sidebar.swift` shows the native disclosure groups and favorite shortcuts.
- **Settings: Appearance** and its five siblings in `SettingsPreviews.swift` show each Settings page in the window, on the in-memory library.
- **Editable Page Header** and **Long Title and Narrow Page** in `ItemPageHeader.swift` show inline title editing and status/parent controls.
- **Ticket Details** and **Project and Related Work** show dynamic properties and relationships.
- **Missing and Unfamiliar Values** shows unresolved targets and preserved unfamiliar properties.
- **Relationship Selection** and **New Item** expose the native editing flows.
- **Complete Item Window** renders the actual split view, toolbar, editor, and inspector against the in-memory library.
- **Unsaved Property Input** lets a rejected save be exercised by editing the field and committing it.

`MAPP/Views/ItemProperties.swift` also previews the individual property controls. `MAPP/Views/FileItemContent.swift` contains the file-view previews. Review the real app for editor behavior, window resizing, keyboard navigation, and saved-file persistence; the component canvas is for iterating on each piece.
