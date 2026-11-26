---
summary: The agreed design that is not on main, one row for each part, with the code area it lands in and the boards that show it.
paths:
  - MarfaMac/**/*.swift
  - editor/src/*.ts
---

# Agreed and not on `main`

Read only the row you are building. A row says what was agreed; the boards it names show it, and a build's brief says where they are. Where a board and a row disagree, the row wins.

- **The pull request that builds a row deletes it** and writes the rule it leaves behind in the page for that area. Part of a row built leaves the rest of the row.
- **A row is not a promise of order.** `docs/concepts.md` has the model under all of them, and `docs/rejected.md` what was refused on the way.
- **"Waits for Marfa"** means the server must change first. Build nothing that pretends otherwise.
- **Not here, because they are being designed:** Settings' frame, Folders, connecting and the first run.

## Window and sidebar

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |

## Feed, and moving between the two

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Feed | No count on its row, no words of waiting. Its first view is named All. | `SidebarGroups.swift`, `Browser` | `Rethink-Inbox`, `Rethink-Inbox-View`, `Rethink-Inbox-Page`, `Rethink-Inbox-Modal` |
| Default From | Settings > Lists offers All Items (the default) and Library. | `PreferencesMap`, Settings > Lists | `Rethink-Scope-Menu` |
| A table stays in the Library | A table item is offered no Move to Feed, as a collection and a view are not. The package now says which types hold a table; the app does not use that yet. | `ItemMoves.swift`, `Catalogue` | `Rethink-Item-Menus` |
| Quick Actions | Keep, Archive and Delete on the row under the pointer, a choice of each view, with the default that `docs/concepts.md` gives. | `ItemRow.swift`, `ViewMacSettings` | `Rethink-Inbox-Actions`, `Rethink-View-Quick-Actions` |

## Archiving

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Undo of state and tier where the copy cannot be sure | **Waits for Marfa:** an expected state on a transition (marfa#3523) and an update that refuses a stale version (marfa#3528). Until then, Undo does nothing and says so when the copy shows a change, and a change the copy has not yet learned of can still be overwritten. | `MarfaEngine+Writing.swift`, `MarfaLibrary+Bin.swift`, `MarfaLibrary+Moves.swift` | `Rethink-Archive-Toast` |
| An archived item's page | Says Archived over its title, and edits as any other. | `ItemPageHeader.swift`, `BatchSkips` | `Rethink-Archived-Page` |

## Layouts

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| A collection's place | Lists its items as any place does, with its description and facts in Info. | `Browser`, `ItemInspector.swift` | `Rethink-Collection`, `Rethink-Collection-Full` |
| Empty places | Words for each case, and a New button only for a place of one type or an empty collection. A type with nothing kept says where its items are and offers Show All Items. Search offers Clear Search. | `PlaceEmpty` | `Rethink-Empty-Type`, `Rethink-Empty-View`, `Rethink-Empty-Collection`, `Rethink-Empty-Search`, `Rethink-Empty-Inbox`, `Rethink-Type-Nothing-Kept`, `Rethink-Type-Nothing-Kept-Library`, `Rethink-Type-Waiting` |

## Views and the View panel

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Groupings to come | By collection and by tag, with the order of a date's groups following the sort. | `GroupOffer`, `GroupMode` | `Rethink-View-Group` |

## The item's page

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Stored `rows` | A page placement is stored with `rows` beside `shows`, because a copy from before `shows` sets the whole map aside without `rows`. Removed after the first v0.1 release: write `shows` only and keep reading an old `rows` once. | `PagePlacements.swift` | – |
| Outline | The heading being read has a dark bar and dark text. The page does not report which it is yet. | `editor/src/bridge.ts`, `PanelOutlineView.swift` | `Rethink-Long-Page` |
| Scrolled | The title sits in the toolbar on one line. | `ItemDetail.swift`, `WindowToolbar.swift` | `Rethink-Page-Scrolled`, `Rethink-White-Page` |
| Blocks | A callout as a tinted block without a rail. A code block's actions in its corner; the place of its language is open. | `editor/src/style.css` | `Rethink-Blocks`, `Rethink-Blocks-Code` |

## Editing and links

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Undo of a link in one call | Undo checks a link's id, type and ends, then deletes it by id in a second package call, so a move synced between the two is lost, as with state moves. **Waits for Marfa:** one package call that checks and deletes. | `MarfaEngine+Writing.swift` | – |
| Conflict | A calm line with Keep My Edit and Use Current Value. | `ValueEditModel` | `Rethink-Edit-Conflict` |
| Status where it is seen | The mark before a task's name, in place of a Status column. | `Browser`, `ItemTable.swift` | `Rethink-Status-In-List` |

## Each kind of item

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Bookmark, article, web page | Reader or Original in the corner, the original at full width. | `WebPageItemPage.swift` | `Rethink-Bookmark`, `Rethink-Bookmark-Full`, `Rethink-Web-Page-Reader`, `Rethink-Web-Page-Original` |
| Audio, video | A playback bar at the window's foot, with a waveform, speed, skip and the place kept; nothing plays by itself. **Waits for Marfa:** a transcript. | `FileItemContent` | `Rethink-Audio`, `Rethink-Audio-Transcript`, `Rethink-Video`, `Rethink-Playback` |
| File title in the head | Edited in place, through every flush, on the version typed on. | `FilePageHead`, `EditorController+Flushing.swift` | `Rethink-Image`, `Rethink-PDF` |
| Table item | A sheet of its own rows, without properties or margins, row numbers off. The app keeps the order and a column's menu sets it. The last piece, and it may be cut. | new files in `MarfaMac/Views/` | `Rethink-Table-Item`, `Rethink-Table-Item-Full`, `Rethink-Table-Item-Numbers`, `Rethink-Table-Item-Column`, `Rethink-Table-Preview` |

## Sync and offline

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Settings the design adds | Each goes through `PreferencesMap`, optional when read, so an older copy of the app loses none. | `PreferencesMap` | – |

## Looks

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Areas, glass, measures | Three areas, where glass is used, and one set of measures, radii and type sizes. Dark values are in one table before they are used. | `InterfaceStyle`, `MarfaMac/Views/Looks/` | `Rethink-Found-Areas`, `Rethink-Found-Glass`, `Rethink-Found-Measures`, `Rethink-Found-Measures-Page`, `Rethink-Found-Radii`, `Rethink-Found-Type`, `Rethink-Found-Selection` |
| Messages | A toast is a symbol, what happened and Undo; a second replaces the first. An alert with a red button has a gray Cancel. | `ToastView.swift`, `LibraryDialogs.swift` | `Rethink-Keep-Toast`, `Rethink-Delete-Toast`, `Rethink-Delete-Alert` |

## Small ideas

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Follow a chip | A click on a chip that is not being edited lists everything that shares its value, as a search token. | `PageChip`, `SearchNarrowing` | `Rethink-Follow-Chip` |
| Edit the type | A field's menu opens the type in Settings. | `FieldMenu` | – |
| Settings' parts | A connector's Files row in its mapping. **Waits for Marfa.** | `MarfaMac/Settings/Marfa/` | – |
