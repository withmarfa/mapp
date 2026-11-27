---
summary: The rules of the Settings window, its parts and each of the app's own pages.
paths:
  - MarfaMac/Settings/Window/*.swift
  - MarfaMac/Settings/Parts/*.swift
  - MarfaMac/Settings/App/*.swift
  - MarfaMac/Model/MacSettings.swift
  - MarfaMac/Model/Marfa/AutomaticExport*.swift
---

# The Settings window

See `docs/owner-settings.md` for Marfa pages and `docs/settings-sync.md` for storage.

## The window

- **Settings is a `Window` scene** with its own toolbar and a remembered frame.
- **There is one instance, and every route names a page in it** (`SettingsLauncher`, `SettingsNavigation`).
- **The sidebar always has both halves.** App: General, Connection, Appearance, Keyboard, then Editor, Lists, Layouts, and Search. Marfa: Account, Activity, Apps and Keys, Sources, Webhooks, then Types, Plugins, Connectors, Folders, Backups, and Trash. Account badges the number of problems.
- **Every route has a sidebar entry** (`SettingsPage.sidebarEntry`, `MarfaSettingsPage.sidebarEntry`). Search includes the words of pages opened through that entry. The Docs link opens Marfa's documentation.
- **A page is one column of sections.** Push a new page for a thing's own settings.
- **Back and Forward are at the top of the sidebar.** The current page's title is above the detail. The View menu's Back and Forward commands use the same history.

## Parts

- **Pages draw with `Parts/`.** Keep app models out of parts.
- **Every measure, color and font is in `SettingsTokens`.**
- **A row is a lead, a title, one line and one trailing control** (`SettingsRow`), two lines at most. A problem row may hold two buttons, as may the release row of Updates.
- **A value that a button acts on goes in the row's line.** A problem's words are told whole.
- **A refused input keeps what was typed**, with one line under the title that says why.
- **Put an add button at the trailing edge of the section title** (`SettingsSection`'s accessory). Use the same slot for header choices or search and a filter when the section needs them. Put a note about the section in its footer.
- **Row controls use the small size** with secondary values, a plain More menu, and pop-ups at least 120 points wide. Pop-ups and header choices fit their text. A disk path or web address can have a folder or link glyph.
- **A page link has a colored tile and a chevron.** A locked link dims the tile and shows a lock with a short reason. A row about a thing uses a plain symbol or no symbol.
- **A section table has no stripes and aligns numbers at the trailing edge.** It shows all rows through 50. For longer lists it previews 20 with the count and Show All, which expands the table or opens the full list. Use text tabs with optional counts for page views.
- **Use title case for page and section titles, buttons, tabs, column headings, sheet titles, and alert titles.** Use sentence case for row labels, switches, and descriptions. An ellipsis marks a button that opens a window to type or choose in.
- **Something new with several fields is a `SettingsSheet`** in the middle of the window, shown with `settingsSheet`, never `.sheet`, which drops from under the toolbar. What it shows is read from an `@Observable` model, because the window draws it.
- **A sheet's confirm button is `SettingsButton` with `role: .confirm`**, which also takes Return. A sheet's destructive button is alone at the leading edge, and reads Remove or Delete.
- **Buttons that act on one setting sit in its row.** Buttons that act on the page are a `SettingsBar` at its end.
- **A page that cannot be shown is a `SettingsPageState`**, never a row.
- **Use Allow More for a missing permission.** Use Try Again when a failed read can be retried.
- **What is typed and not saved is handed over** when the window closes or the app quits (`AppSettingsHost.handOverDrafts`).

## The app's pages

| Page | What to know before a change |
| --- | --- |
| General | Reopen Windows follows the Mac until the person changes it, and only then writes `NSQuitAlwaysKeepsWindows`. Send Error Reports and Updates show only in a build that carries a destination or a feed |
| Appearance | App icon updates the Dock at launch and on change. Sky uses the bundle icon. Alternatives are Cobalt, Sea, Leaf, Marigold, and Adobe. Sidebar color applies to the main window |
| Keyboard | Every menu command with its shortcut, and the any-app ones (`docs/commands.md`) |
| Editor | Fonts load when the page opens. PDF background shares the choice in View › PDF Background. Inkkit replaces `EditorOptions` as a set. Edit pages as applies to items opened next |
| Lists | The starting density, sort and group of a place, until a view or the place chooses its own |
| Layouts | How each type looks, through the stores of `docs/type-looks.md`. Only what differs from the type's preset is kept, so a better preset still reaches it. Page pins properties and holds the one Linked From row, which reads and writes the type's stored choice (`PagePlacements.linkedFrom`) |
| Search | What searches of the whole library leave out (`SearchLeaveOuts`). A search in one place leaves nothing out. A type or source that would pass a query's ten conditions is dimmed, with the reason |
| On This Mac | Opens from Connection. The copy, downloaded files and exports, below |
| Connection | Sign-in, other Marfas and Disconnect, which reads the queue in the same step and asks about changes that wait |

- **A choice whose thing is gone keeps its name, marked as missing** (`MissingChoice`), and the app uses the default meanwhile.
- **Import, restore and reset save a restore point first.** If that fails, nothing changes.

## On This Mac

- **An export is saved only when the app has read it back and checked it whole** (`LibraryExport`): plain tar, the manifest first, every count, and each file's bytes against its name. The server writes exactly that, so anything else is refused and told.
- **It must be the Marfa that the copy names**, by instance id.
- **Its folder must be on a local APFS or HFS+ volume**, because the archive is moved in without replacing a file (`RENAME_EXCL`). Nothing is removed by path.
- **An archive that lacks some files is kept**, and the row says how many.
- **Automatic exports belong to one Marfa and one Mac** (`AutomaticExport`) and run only while the app does. A folder moved or replaced since it was chosen gets nothing.
- **Clear keeps attachments and files that wait to upload. Download Everything Again keeps the queue.**
