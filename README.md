# MAPP

<img src="Design/AppIcon.png" width="128" alt="">

A native macOS markdown notes app: a sidebar, a list and a page, in the manner of Notes and Mail.

Requires macOS 27 and Xcode 27. Open `MAPP.xcodeproj` and run the `MAPP` scheme, or see `AGENTS.md` for the command line.


## Item interface

The sidebar keeps Inbox and All Notes above a collapsible Favorites section with shortcuts to individual items. Favorites disappears when it has no items. Under Library, native disclosure groups show Projects, item types and files under Items, and Folders. Details in the toolbar reveals the item's native inspector; View > Show Details provides the same action. New Item in the toolbar or File menu opens an Untitled page. Choose its type and optional parent, then press Return in the title or click the content area to start writing. Draft input stays in that window when you navigate away; New Item resumes it. File > Import Files creates a separate file item, while Add Attachment opens the image chooser to embed an image in a Markdown document. Property and relationship edits are saved to the selected folder. Markdown uses InkKit through its public editor API; photos, PDFs, and other files use native viewing or opening.

The native title and property chips scroll with the note's body. When the header scrolls away, a compact title appears at the leading edge of the toolbar. The trailing group contains New Item (plus), Format (Aa), Details and More. Format includes lists and table insertion; More contains Share and Add Attachment. Selecting a note opens it at the top. Format commands reflect the active text selection; source editing shows the Markdown syntax. An empty list leaves the content pane blank; a populated list with no selection shows “Select an item”. Search List (⌥⌘F) expands across the list column, with a trailing close button that also works when the search is empty.

More > Gallery View replaces the list and page with a grid beside the sidebar, as Photos does. Cards show a local embedded image when one is available, or a text preview. More > List View restores the three-column workspace. View and the command palette offer the same choices. Click to select; Command-click toggles an item and Shift-click extends the selection. Arrow keys move through the grid, Shift-arrow extends selection, and Command-A selects all visible items. Double-click or Return opens one item in the same window; Back to Gallery (⌘[) returns. Search, sorting, favorites, folder navigation, item actions, and drafts use the same browser state in both views. Each window restores its view mode.

The note list defaults to 340 points and can be resized. Settings (⌘, or the gear in the sidebar toolbar) fills the main window using a native two-column navigation split view, sidebar search, and grouped preference controls. Back to MAPP in the sidebar toolbar returns to the selected item and preserves an unsubmitted draft and the note-list width. The command palette opens the same Settings page. Appearance > Base Text Size scales interface text, including the sidebar, list, and inspector. Editor > Text Size controls note text separately. Search Settings finds categories by their names and preference labels, including font size, spelling, page width, and the notes folder.

File-backed items use the workbench definitions as interim input. Files without a Markdown envelope expose their file information, but do not claim editable properties that the folder cannot persist.

## Editing and export

View and the command palette switch between formatted and source editing. Native Find and Replace work with the active editor. Local images, audio, and video preview inline with the existing file-access protections. PDFs show a card with Open to view the document in its native app, because WebKit cannot display them in the protected editor frame. Note references open source editing; they do not embed the referenced note.

Typing `/` on an empty line opens a menu of blocks, such as headings, lists, a table, a quote and a code block, and Link to Note, which asks which note to link to and writes a link that names that note and no other. Typing `[[` offers the titles of the library's notes, leaving out a title that more than one note goes by. Typing a row such as `| Name | Date |` and pressing Return or Tab makes a table, and Option-Up and Option-Down move the block at the caret. The page makes no smart quotes or dashes of its own; the system's Substitutions setting applies as it does in any Mac text field.

Print and Export as PDF render a complete snapshot of the note, including local images. Other attachments use readable descriptions. PDF export is limited to 200 pages or 64 MB; a failed export leaves an existing destination unchanged.

## Reviewing components in Xcode

Open `MAPP.xcodeproj`, choose the `MAPP` scheme, and open `MAPP/Views/ItemPreviewFixtures.swift`. Enable Editor > Canvas and resume a named preview. These previews use fixed sample items and an in-memory library; they do not read or write a person's working folder.

- **Grouped Sidebar** in `Sidebar.swift` shows the native disclosure groups and favorite shortcuts.
- **Settings** in `SettingsView.swift` shows the full-page preferences using isolated defaults.
- **Editable Page Header** and **Long Title and Narrow Page** in `ItemPageHeader.swift` show inline title editing and status/parent controls.
- **Ticket Details** and **Project and Related Work** show dynamic properties and relationships.
- **Missing and Unfamiliar Values** shows unresolved targets and preserved unfamiliar properties.
- **Relationship Selection** and **New Item** expose the native editing flows.
- **Complete Item Window** renders the actual split view, toolbar, editor, and inspector against the in-memory library.
- **Unsaved Property Input** lets a rejected save be exercised by editing the field and committing it.

`MAPP/Views/ItemProperties.swift` also previews the individual property controls. `MAPP/Views/FileItemContent.swift` contains the file-view previews. Review the real app for editor behavior, window resizing, keyboard navigation, and saved-file persistence; the component canvas is for iterating on each piece.
