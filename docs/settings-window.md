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

One window holds the app's pages and, under them, the Marfa's, which `docs/owner-settings.md` covers. `docs/settings-sync.md` says where each setting is kept.

## The window

- **Settings is a `Window` scene, not the system's `Settings` scene**, because that one is sized to its content, with no toolbar of ours and no frame the person keeps.
- **There is one instance, and every route names a page in it** (`SettingsLauncher`, `SettingsNavigation`).
- **A page is listed once it exists** (`SettingsPage`, `MarfaSettingsPage`): a case, its group, its search words and its view in `SettingsDetail`.
- **A page is one column of sections, and what has settings of its own is a page pushed on it**, so Back returns.
- **Back and Forward are the View menu's commands** while the window is key.

## Parts

- **A page draws with the parts in `Parts/`** and never its own row, button, section or sheet. The parts know nothing of the app's model.
- **Every measure, color and font is in `SettingsTokens`.**
- **A row is a lead, a title, one line and one trailing control** (`SettingsRow`), two lines at most. A problem row may hold two buttons, as may the release row of Updates.
- **A value that a button acts on goes in the row's line.** A problem's words are told whole.
- **A refused input keeps what was typed**, with one line under the title that says why.
- **Adding is the last row of the card it adds to** (`SettingsAddRow`).
- **Something new with several fields is a `SettingsSheet`** in the middle of the window, shown with `settingsSheet`, never `.sheet`, which drops from under the toolbar. What it shows is read from an `@Observable` model, because the window draws it.
- **A sheet's confirm button is `SettingsButton` with `role: .confirm`**, which also takes Return. A sheet's destructive button is alone at the leading edge, and reads Remove or Delete.
- **Buttons that act on one setting sit in its row.** Buttons that act on the page are a `SettingsBar` at its end.
- **A page that cannot be shown is a `SettingsPageState`**, never a row.
- **The button that asks for more permission is Allow More…**, never Try Again, because trying again cannot help.
- **What is typed and not saved is handed over** when the window closes or the app quits (`AppSettingsHost.handOverDrafts`).

## The app's pages

| Page | What to know before a change |
| --- | --- |
| General | Reopen Windows follows the Mac until the person changes it, and only then writes `NSQuitAlwaysKeepsWindows`. Send Error Reports and Updates show only in a build that carries a destination or a feed. Sync with This Marfa chooses which groups to share with the connected Marfa |
| Appearance | A color is stored as a name or a hex value. Installed fonts are listed when the page appears, never before |
| Keyboard | Every menu command with its shortcut, and the any-app ones (`docs/commands.md`) |
| Editor | Each change reaches an open page. Inkkit's options go as one set (`EditorOptions`), because each of its calls replaces the whole set. Edit Pages As applies to items opened next, never to the page shown |
| Lists | The starting density, sort and group of a place, until a view or the place chooses its own |
| Layouts | How each type looks, through the stores of `docs/type-looks.md`. Only what differs from the type's preset is kept, so a better preset still reaches it. Page pins properties and holds the one Linked From row, which reads and writes the type's stored choice (`PagePlacements.linkedFrom`) |
| Search | What searches of the whole library leave out (`SearchLeaveOuts`). A search in one place leaves nothing out. A type or source that would pass a query's ten conditions is dimmed, with the reason |
| On This Mac | The copy, downloaded files and exports, below |
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
