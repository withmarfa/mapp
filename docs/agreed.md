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
| Feed's mark | In every list of all items, after a Feed item's name, in each layout that shows a name. The table of both tiers has it; the list and gallery do not yet. | `ItemRow.swift`, `GalleryCards.swift` | `Rethink-Type-Inbox`, `Rethink-Archive` |
| A table stays in the Library | A table item is offered no Move to Feed, as a collection and a view are not. The package now says which types hold a table; the app does not use that yet. | `ItemMoves.swift`, `Catalogue` | `Rethink-Item-Menus` |
| Quick Actions | Keep, Archive and Delete on the row under the pointer, a choice of each view, with the default that `docs/concepts.md` gives. | `ItemRow.swift`, `ViewMacSettings` | `Rethink-Inbox-Actions`, `Rethink-View-Quick-Actions` |

## Archiving

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Undo of state and tier where the copy cannot be sure | **Waits for Marfa:** an expected state on a transition (marfa#3523) and an update that refuses a stale version (marfa#3528). Until then, Undo does nothing and says so when the copy shows a change, and a change the copy has not yet learned of can still be overwritten. | `MarfaEngine+Writing.swift`, `MarfaLibrary+Bin.swift`, `MarfaLibrary+Moves.swift` | `Rethink-Archive-Toast` |
| An archived item's page | Says Archived over its title, and edits as any other. | `ItemPageHeader.swift`, `BatchSkips` | `Rethink-Archived-Page` |

## Several items

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The capsule | Several chosen items are one capsule of symbols at the foot of the window, in glass: Keep leads in the Feed, then Archive, Add Tag, Add to Collection, Change Type and More, and Delete stands apart at the end. The count is the control that lets them go. Beside a list, the same stands under the pile of cards in the page's column. | `MainView.swift`, `ItemActions.swift` | `Rethink-Selection-Table`, `Rethink-Selection-List`, `Rethink-Selection-States` |
| Undo | Each link and new row is one undo, however many items. | `StepUndo`, `ItemWrite` | `Rethink-Archive-Toast` |

## Layouts

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Gate | A list of 50,000 items stays quick to change. Nesting, Digest and Map come after it. | `Browser`, `ItemTable.swift` | `Rethink-Library-Heavy` |
| Digest | Items read in place: a white card each, with its type, source, title and some lines. What belongs together (a thread, one book's highlights) is a pile under its newest. An older copy of the app reads an unknown layout as a list. | `ItemViewMode`, a new file in `MarfaMac/Views/` | `Rethink-Inbox`, `Rethink-Inbox-View` |
| Map | The app's own markers, grouping, a card for the chosen one, Style and Group Nearby, No Location with a count, and the system's stepper in the corner. MapKit joins what may connect out. | `ItemViewMode`, a new file in `MarfaMac/Views/` | `Rethink-Map`, `Rethink-Map-Light-Full`, `Rethink-Map-View` |
| Table | Sub-items nest under their parent. A column takes its content. A last row, New, is the row a person types in. Every date column reads one way. | `ItemTable.swift`, `ItemTableCells.swift` | `Rethink-Library`, `Rethink-Library-Heavy` |
| List beside a page | The entries of every list beside a page, the same in every place. | `ItemList.swift`, `ItemRow.swift` | `Rethink-Notes`, `Rethink-Highlights` |
| Board | Its columns are its groups, so Hide Empty Groups is the one switch. A lane has a plus. Rows: Properties, Card Size, Sub-Items. | `ItemBoard.swift` | `Rethink-Tasks-Board` |
| Calendar | A choice of the date field, No Date with a count, Weekends, a gray chosen event, and a one-line header on the week. | `ItemCalendar.swift`, `CalendarWeekView.swift` | `Rethink-Calendar`, `Rethink-Calendar-Month`, `Rethink-Calendar-Light`, `Rethink-Calendar-Light-Full` |
| Gallery | Preview, Card Size, Shape and Fit Picture. A card without a picture fills with its opening lines, or its type's mark. | `ItemGallery.swift`, `GalleryCards.swift` | `Rethink-Gallery`, `Rethink-Gallery-Full`, `Rethink-Gallery-View` |
| Timeline | Stays, an agenda by day at the window's full width; the type leads only where types mix. | `ItemTimeline.swift` | `Rethink-Timeline`, `Rethink-Timeline-Full` |
| A collection's place | Lists its items as any place does, with its description and facts in Info. | `Browser`, `ItemInspector.swift` | `Rethink-Collection`, `Rethink-Collection-Full` |
| Empty places | Words for each case, and a New button only for a place of one type or an empty collection. A type with nothing kept says where its items are and offers Show All Items. Search offers Clear Search. | `PlaceEmpty` | `Rethink-Empty-Type`, `Rethink-Empty-View`, `Rethink-Empty-Collection`, `Rethink-Empty-Search`, `Rethink-Empty-Inbox`, `Rethink-Type-Nothing-Kept`, `Rethink-Type-Nothing-Kept-Library`, `Rethink-Type-Waiting` |

## Views and the View panel

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The row of views | Pills in an order the app keeps for each place; a pill is dragged, and its menu has Hide. Past the room, N More, whose menu ends with New View…. A place with one view has no row. | `ListToolbar.swift`, `ViewMacSettings` | `Rethink-Top-Row-Lists`, `Rethink-View-Menu` |
| A changed view | A change is written as it is made. The pill's dot shows while the view differs from how it was when last opened on the Mac. Revert View puts that back; Save as New View… makes another. | `Browser+ViewWrites.swift`, `Browser+SavedViews.swift` | `Rethink-View-Changed` |
| Offline | A change to a view waits, and the pill says so on hover. A new view waits too. | `Browser+ViewWrites.swift` | `Rethink-Offline` |
| Groupings to come | By collection and by tag, with the order of a date's groups following the sort. | `GroupOffer`, `GroupMode` | `Rethink-View-Group` |

## Making a view

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The plus | Opens one panel where the View panel stands; the view is its pill at once, and the list shows what it will list. Starting points that fit the place, then one sentence of values, a suggested name, Add to Sidebar and Quick Actions, and Create View. | `ViewDraft`, `SavedViews.swift` | `Rethink-New-View`, `Rethink-New-View-First`, `Rethink-New-View-Chosen`, `Rethink-New-View-Types`, `Rethink-New-View-Value`, `Rethink-New-View-Inbox` |
| Starting points | Recently Added, Favorites, a layout that fits the fields, In the Feed, Blank. One a person already has opens theirs. | `ViewDraft` | `Rethink-New-View-First` |
| While searching | The new view starts from the search: its tokens are the filter, and its first starting point is This Search. | `SearchNarrowing`, `ViewDraft` | `Rethink-Search-Items` |
| Naming | A pill is renamed in place, and its menu has Rename…, Duplicate, Hide and Delete View…. | `SavedViewCommands.swift` | `Rethink-View-Menu` |

## Search

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |

## Making an item

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The new-item line | One line with rows for its keys: Tab a kind, # a tag, @ a parent, / a property, and In at the foot. Before typing it offers the most recent. It stays open after Add with the same kind; ⇧↩ opens the text form. | `QuickAdd`, `QuickAddPanel.swift` | `Rethink-New`, `Rethink-New-Line`, `Rethink-New-Line-Kinds`, `Rethink-New-Line-Task`, `Rethink-New-Line-Bookmark`, `Rethink-New-Kinds`, `Rethink-New-Filled` |
| In place | A table's last row, a board lane's plus, a calendar's drag. The item stays where it was typed until the row is left. In a nested table it is top-level; in a grouped one it joins the group under the pointer, or the first. Escape drops an empty row and keeps typed text; leaving adds. | `ItemTable.swift`, `ItemBoard.swift`, `CalendarWeekView.swift` | `Rethink-New-In-Table`, `Rethink-New-In-Board`, `Rethink-New-In-Calendar` |
| From any app | The same panel in the screen's upper third, with a drop of files. | `QuickAddPanel.swift` | `Rethink-New-Anywhere`, `Rethink-New-Drop` |
| New Opens | A setting, One Line or the text form. | `PreferencesMap` | `Rethink-New-Line` |

## The item's page

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Stored `rows` | A page placement is stored with `rows` beside `shows`, because a copy from before `shows` sets the whole map aside without `rows`. Removed after the first v0.1 release: write `shows` only and keep reading an old `rows` once. | `PagePlacements.swift` | – |
| Scrolled | The title sits in the toolbar on one line. | `ItemDetail.swift`, `WindowToolbar.swift` | `Rethink-Page-Scrolled`, `Rethink-White-Page` |
| Foot | Sub-Items with nesting on any item that has them; a Timeline of mentions on a person and a place; more after 30. | `LinkedFromPlace`, `editor/src/header.ts` | `Rethink-Sub-Items`, `Rethink-Person`, `Rethink-Place` |
| Blocks | A callout as a tinted block without a rail. A code block's actions in its corner; the place of its language is open. | `editor/src/style.css` | `Rethink-Blocks`, `Rethink-Blocks-Code` |

## Editing and links

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Undo of a link in one call | Undo checks a link's id, type and ends, then deletes it by id in a second package call, so a move synced between the two is lost, as with state moves. **Waits for Marfa:** one package call that checks and deletes. | `MarfaEngine+Writing.swift` | – |
| Conflict | A calm line with Keep My Edit and Use Current Value. | `ValueEditModel` | `Rethink-Edit-Conflict` |
| Status where it is seen | A click on a status in a row or a lane opens its panel; the row stays until it is left. | `StatusSymbol`, `ItemRow.swift` | `Rethink-Status-In-List` |
| Every link follows Open Items | In the text, rows, foot and panel, through one function of the browser. A picture in the text has Open Item and Copy Link on its menu. | `Browser`, `EditorController` | – |
| Link card | After a pause on a linked item, a small card with its type, name and two lines. No keyboard focus, no server call. | new files in `MarfaMac/Views/`, `editor/src/` | `Rethink-Link-Card` |

## Each kind of item

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Task, project | Sub-items at the foot. | `TypeLooks`, `editor/src/header.ts` | `Rethink-Task-Page`, `Rethink-Project`, `Rethink-Project-Full` |
| Event | Attendees' answers in gray. | `EventHeader` | `Rethink-Event`, `Rethink-Event-Full` |
| Bookmark, article, web page | Reader or Original in the corner, the original at full width. | `WebPageItemPage.swift` | `Rethink-Bookmark`, `Rethink-Bookmark-Full`, `Rethink-Web-Page-Reader`, `Rethink-Web-Page-Original` |
| Highlight | The passage is its text, in a leading style and edited as text. Its note is a row of two lines. It has no title. | `TypeLooks`, `editor/src/header.ts` | `Rethink-Highlight`, `Rethink-Highlight-Full`, `Rethink-Highlights` |
| Person, place | A place has a map on its page. | `FileItemContent` | `Rethink-Person`, `Rethink-Person-Full`, `Rethink-Place`, `Rethink-Place-Full` |
| Message | No title field, so its text leads. From is a mark and a name. | `TypeLooks` | `Rethink-Message`, `Rethink-Message-Full` |
| Image | Fit in the corner, its facts, rows that can be edited. | `FileItemContent`, `FileCorner.swift` | `Rethink-Image`, `Rethink-Image-Full` |
| PDF | Paper on a gray or white ground, by a setting; contents in Outline. The PDF keeps its own scroller, with the head as its first inset; so do a video and a picture. | `FileItemContent`, `FileCorner.swift` | `Rethink-PDF`, `Rethink-PDF-Full`, `Rethink-PDF-White`, `Rethink-PDF-Full-White` |
| Audio, video | A playback bar at the window's foot, with a waveform, speed, skip and the place kept; nothing plays by itself. **Waits for Marfa:** a transcript. | `FileItemContent` | `Rethink-Audio`, `Rethink-Audio-Transcript`, `Rethink-Video`, `Rethink-Playback` |
| Table item | A sheet of its own rows, without properties or margins, row numbers off. The app keeps the order and a column's menu sets it. The last piece, and it may be cut. | new files in `MarfaMac/Views/` | `Rethink-Table-Item`, `Rethink-Table-Item-Full`, `Rethink-Table-Item-Numbers`, `Rethink-Table-Item-Column`, `Rethink-Table-Preview` |
| Read only | No Aa, and one line in Info. | `PageCorner`, `ItemInspector.swift` | `Rethink-Read-Only`, `Rethink-Read-Only-Full` |

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
| Drag onto a collection | A drop on a collection's row in the sidebar adds the items. Nothing else takes a drop there, and nothing springs open. | `SidebarGroups.swift` | `Rethink-Drag-To-Collection` |
| Board lanes | Lanes are dragged into an order. | `ItemBoard.swift` | – |
| Edit the type | A field's menu opens the type in Settings. | `FieldMenu` | – |
| Settings' parts | A connector's Files row in its mapping. **Waits for Marfa.** | `MarfaMac/Settings/Marfa/` | – |
