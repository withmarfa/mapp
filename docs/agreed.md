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
| Places | The sidebar's places are Library, Feed, a type, a collection, a source, the Library's own lists, and an item. Recents, Favorites, Inbox and Files stop being places: Recents is the Library sorted by Edited, and Favorites is a view the Library starts with. A chosen view is part of a place, not a place. | `SidebarItem`, `Browser`, `SidebarLayout` | `Rethink-Library`, `Rethink-Item-Places` |
| The two fixed zones | Search and New, then Library with its count and Feed with none. The Feed's symbol is `water.waves`. Search opens the Command Palette. | `SidebarGroups.swift`, `SidebarTypeRow.swift` | `Rethink-Sidebars`, `Rethink-Library` |
| Under the pointer | A plus takes the place of the count on a type, a kind and a collection. Search and New show their shortcuts. A section's heading shows Add and More. Nothing in a row moves. | `SidebarTypeRow.swift`, `SidebarGroups.swift` | `Rethink-Sidebar-Pointer`, `Rethink-Sidebar-Sections` |
| Pinned and Types | Pinned holds views, collections and items. Types list their kinds under them. A person's arrangement is read into the new sidebar: views they placed keep their sections, the rest go to Pinned, and an unknown group is ignored. | `SidebarLayout`, `SidebarGroups.swift` | `Rethink-Sidebars` |
| Customize Sidebar | Dashed places (Tab, Command, a Library list, Pinned, Type, Section) each open a menu of what can go there. One tabs row shows while customizing. | `CustomizeSidebar.swift` | `Rethink-Customize-Sidebar`, `Rethink-Customize-Sidebar-Add` |
| Sidebar closed | The title gets an arrow that opens the sidebar's rows as a menu. Back and Forward stay. The control after the count follows the title. | `SidebarToolbar.swift`, `MainView.swift` | `Rethink-Sidebar-Closed`, `Rethink-Sidebar-Closed-Menu` |
| The top row | Title and count on one baseline, the Library or Feed control, the place's views, then the buttons. At rest the views have their own row; scrolled, they sit beside the title. Types, Collections and Sources fold into one menu first, then views into N More, then one pill. **The main risk:** prototype it in the system toolbar and in the content under a hidden title, and choose by folding, full screen, dragging, VoiceOver, text size and customizing. | `WindowToolbar.swift`, `ListToolbar.swift`, `IndexScrollAway.swift` | `Rethink-Library-Scrolled`, `Rethink-Top-Row-Columns`, `Rethink-Top-Row-Lists` |
| Customize Toolbar goes | Its commands stay in the menus and the palette. | `WindowToolbarLayout` | `Rethink-Library` |
| Smallest window | The window goes down to 760 by 520. The panel folds first, then the sidebar by itself under 900 wide, then the control, the views, and a table's columns from the last. | `MarfaMacApp.swift`, `MainView.swift` | `Rethink-Small-Window`, `Rethink-Panel-Sizes` |
| The Marfa's panel | The foot opens a panel: the Marfa's name and count, its latest sources, and the Marfas the app has signed in to, with a tick and a plus on the heading. Switching signs out of nothing. Pages flush first, and changes that were not sent stay queued. | `SidebarFoot.swift`, `MarfaHost` | `Rethink-Marfa` |
| Sidebar color | Gray or White, in Appearance, synced. | `Sidebar.swift`, `PreferencesMap` | `Rethink-Sidebars` |

## Library and its places

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Library | Lists active library items in the one table every place uses, with a row of views and, at its end, Types, Collections, Sources and Archive. Its first view is named All. It opens as a table, and as a list with ten items or fewer. Its off-main arrangement of rows (`ItemIndexModel`) moves into the shared list and is not lost. | `ItemsIndex.swift`, `IndexPage.swift`, `ItemTable.swift` | `Rethink-Library`, `Rethink-Library-New`, `Rethink-Library-Heavy` |
| Types | A table of Name (nested), Items, Views, Made By, Latest. Its row menu has Open, Open in New Window, New, New View…, Add to Sidebar, Copy Link, Edit Type…. Made By waits for the package to give a type's provenance, and Copy Link for a link form (`ItemLinkRoute` has only items). | `SidebarIndex.swift`, `ItemLinkRoute` | `Rethink-Types`, `Rethink-Types-Ordinary`, `Rethink-Types-Agents` |
| Collections | Name, Items, Source, Edited. The tabs, the source filter and the index's sidebar go. A collection can be archived, and cannot be moved to the Feed. | `SidebarIndex.swift`, `IndexInspector.swift` | `Rethink-Collections`, `Rethink-Collections-Full` |
| Sources | Name, Items, Latest, and the types a source writes as marks and names, three and a count. Its page's panel has the facts. A source's Kind can be read by any app today: `GET /plugins` names each connector's source and the direction of its kinds, and an app's source starts with `oauth:`. Only New Items Go To waits, because it needs the owner's permission and the main window makes no owner calls. | `SidebarIndex.swift`, `SourceLook.swift` | `Rethink-Sources`, `Rethink-Sources-Full`, `Rethink-Source`, `Rethink-Sources-Waiting` |
| Index pages go | The tabs, the New tiles, the index's own toolbar and filters. | `IndexPage.swift`, `NewTiles.swift`, `IndexToolbar.swift` | `Rethink-Library` |
| A type counts its kinds | A type's place lists and counts its own items and its kinds' items. There is one count, the same beside its title, in the sidebar and in Types. Include Kinds is a switch in the View panel's Types. | `MarfaItemIndex`, `IncludeSubtypes.swift` | `Rethink-Types`, `Rethink-View-Types` |

## Feed, and moving between the two

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Feed | A place like the Library: any layout, its own views, no count on its row, no words of waiting. Its first view is named All. | `SidebarItem`, `Browser` | `Rethink-Inbox`, `Rethink-Inbox-View`, `Rethink-Inbox-Page`, `Rethink-Inbox-Modal` |
| Library or Feed control | After the count on a type, a collection and a source that has Feed items: All Items, Library, Feed, each with its count. It is quiet while it says what the setting says. With Library or Feed chosen, the title's count is of what is listed and the sidebar's stays. It is the first to give way for room. | `ListToolbar.swift`, `ItemTableOptions`, `PlaceDefault` | `Rethink-Scope-Menu`, `Rethink-Type-Inbox` |
| What a type opens on | A setting in Lists: All Items (the default) or Library. | `PreferencesMap` | `Rethink-Scope-Menu` |
| Feed's mark | In every list of all items, after a Feed item's name, in each layout that shows a name. | `ItemRow.swift`, `ItemTableCells.swift`, `GalleryCards.swift` | `Rethink-Type-Inbox`, `Rethink-Archive` |
| Keep and Move to Feed | Commands on one item or several, with a toast that names the item or the count (`ItemLibrary.movedMessage`). Views and tables have neither. | `ItemActions.swift`, `ItemRowMenu.swift` | `Rethink-Keep-Toast`, `Rethink-Item-Menu`, `Rethink-Item-Menus` |
| A table stays in the Library | A table item is offered no Move to Feed, as a collection and a view are not. **Waits for the package:** its catalogue does not say which types hold a table, and the app names no type (marfa-swift#561). | `ItemMoves.swift`, `Catalogue` | `Rethink-Item-Menus` |
| Quick Actions | Keep, Archive and Delete on the row under the pointer, a choice of each view, with the default that `docs/concepts.md` gives. | `ItemRow.swift`, `ViewMacSettings` | `Rethink-Inbox-Actions`, `Rethink-View-Quick-Actions` |
| In | A value on the panel's Info for every item, Library or Feed, that a person changes there. | `ItemInspector.swift` | `Rethink-Feed-Page-In` |
| Leaves the Feed | A date beside In, only where the type has a limit and the item is active in the Feed. Move to Feed asks first only where the limit would remove the item at once. **Waits for Marfa:** the limit in the type's catalogue. | `ItemInspector.swift` | `Rethink-Feed-Limit`, `Rethink-Feed-Limit-Move` |
| Who else keeps an item | One line in Info: "Read only. RSS keeps this item, so a change made here would be overwritten." or "Synced with GitHub. A change made here is sent there." | `ItemInspector.swift` | `Rethink-Kept-By` |

## Archiving

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Archive and Unarchive | ⌃⌘A, in the item menu after Keep or Move to Feed and before Delete. | `ItemActions.swift` | `Rethink-Archive-Toast`, `Rethink-Item-Menu` |
| Undo of state and tier where the copy cannot be sure | **Waits for Marfa:** an expected state on a transition (marfa#3523) and an update that refuses a stale version (marfa#3528). Until then, Undo does nothing and says so when the copy shows a change, and a change the copy has not yet learned of can still be overwritten. | `MarfaEngine+Writing.swift`, `MarfaLibrary+Bin.swift`, `MarfaLibrary+Moves.swift` | `Rethink-Archive-Toast` |
| With sub-items | It asks: Archive All, Archive Only This Item, Cancel. The count is what `archivePlan` puts beneath. | `LibraryDialogs.swift` | `Rethink-Archive-Sub-Items` |
| Library's Archive | The one list of everything archived, from both the Library and the Feed, with its own count and its own layout choice. One type's archived items are this place narrowed by a token in Search. | `SidebarIndex.swift`, `MarfaItemIndex` | `Rethink-Archive`, `Rethink-Type-Archive` |
| An archived item's page | Says Archived over its title, and edits as any other. | `ItemPageHeader.swift`, `BatchSkips` | `Rethink-Archived-Page` |
| Archived Items in a view | Hidden, Shown or Only Archived. A view that names no state lists both, so it reads Shown. | `ViewPanel`, `ViewDraft` | `Rethink-View-Panels` |

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
| A view belongs to a place | To its one type; else its one collection; else its one source; else the Feed, where From is Feed and nothing else narrows it; else the Library. Changing its Types moves it, and the window follows. | `SidebarItem`, `LibraryView` | `Rethink-Item-Places`, `Rethink-Library` |
| The row of views | Pills in an order the app keeps for each place; a pill is dragged, and its menu has Hide. Past the room, N More, whose menu ends with New View…. A place with one view has no row. | `ListToolbar.swift`, `ViewMacSettings` | `Rethink-Top-Row-Lists`, `Rethink-View-Menu` |
| The View panel | One panel replaces View Options, View As, Edit View and the filter row. Each part is one level in: Layout, Properties, Filter, Sort, Group, Types, From, Archived Items, Open Items, then the layout's own. | `ViewEditPanel.swift`, `ItemViewOptions.swift`, `FilterRow.swift` | `Rethink-View-Panels`, `Rethink-View-Filter`, `Rethink-View-Filter-Add`, `Rethink-View-Sort`, `Rethink-View-Group`, `Rethink-View-Properties`, `Rethink-View-Types`, `Rethink-View-From` |
| Where it is kept | The foot of the View panel says "Kept for Marfa for Mac." for a place's first view, and "Saved in Marfa for every app." for a saved view alone. | `PlaceDefaults`, `ViewEditPanel.swift` | `Rethink-View-Panels` |
| A changed view | A change is written as it is made. The pill's dot shows while the view differs from how it was when last opened on the Mac. Revert View puts that back; Save as New View… makes another. | `Browser+ViewWrites.swift`, `Browser+SavedViews.swift` | `Rethink-View-Changed` |
| Offline | A change to a view waits, and the pill says so on hover. A new view waits too. | `Browser+ViewWrites.swift` | `Rethink-Offline` |
| Plain filters first | Filter groups, and dates relative to the day, are offered only when Marfa can save them. | `ViewDraft`, `FilterOp` | `Rethink-View-Filter-Group` |
| Set, Not Set and status groups | A saved view keeps them; Marfa and the package take them. | `ViewDraft`, `GroupMode` | `Rethink-View-Group` |
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
| Tokens | Under the field, offers of fields and values that match what is typed, then Search for the text. Return makes a token and Delete takes the last away. Nothing is saved. | `SearchViews.swift`, `SearchNarrowing` | `Rethink-Search`, `Rethink-Search-Offers`, `Rethink-Search-Where` |
| Palette | Plain type marks, filters as tokens, no results with New Item on the field's line, the words Feed and Archived, one row for Settings. | `CommandPalette` | `Rethink-Palette`, `Rethink-Palette-Typed`, `Rethink-Palette-Actions`, `Rethink-Search-Items`, `Rethink-Search-Items-None` |

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
| The head | A grey line over the title: the type, then Read Only, Feed or Archived where true. Clicking the type opens Change Type. One head for every kind, in the web page and in the app's own pages. | `ItemPageHeader.swift`, `PageHeader.swift`, `editor/src/header.ts` | `Rethink-Task-Page`, `Rethink-Long-Page` |
| Rows | Under the title, one row for each property with a value, six, then Show N More. A type with no text shows its first six, empty ones too. Boxes, strips and the pinned header's looks go. Pinned properties are a setting, off. | `PagePins`, `PagePlacements`, `editor/src/header.ts` | `Rethink-Properties-Rule`, `Rethink-Properties-Sizes` |
| A row's menu | Show When It Has a Value, Always Show, Hide on every page of the type, Move Up and Down, then the field's own menu. Customize Layout goes. | `FieldMenu`, `PagePlacements`, `CustomizeLayout.swift` | `Rethink-Item-Menus` |
| Scrolled | The title sits in the toolbar on one line. | `ItemDetail.swift`, `WindowToolbar.swift` | `Rethink-Page-Scrolled`, `Rethink-White-Page` |
| Foot | Sub-Items with nesting on any item that has them; a Timeline of mentions on a person and a place; more after 30. | `LinkedFromPlace`, `editor/src/header.ts` | `Rethink-Sub-Items`, `Rethink-Person`, `Rethink-Place` |
| Corner | Formats, text size and Focus on a written page; size and Focus otherwise; Open on a file. | `PageCorner` | `Rethink-Formats`, `Rethink-Focus` |
| Blocks | A callout as a tinted block without a rail. A code block's actions in its corner; the place of its language is open. | `editor/src/style.css` | `Rethink-Blocks`, `Rethink-Blocks-Code` |
| Beside the list | Open Items gains Beside the List: the page in a column, one editor to a window. | `ItemOpening`, `EditorSlot` | `Rethink-Notes`, `Rethink-Library-New` |
| Modal | Close, Up and Down lead; Favorite, Share and More trail, with Keep first on a Feed item; Open as Page in the corner. | `ItemModal.swift` | `Rethink-Modal`, `Rethink-Inbox-Modal` |
| Own window | An item's window has the same page, panel and controls. | `ItemWindow.swift` | `Rethink-Item-Window` |

## The panel beside it

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The panel | White, closed by default, with pills: Outline, Links, Info. It remembers the pill for each type. One part has no pills. | `ItemInspector.swift` | `Rethink-Panel-Sizes`, `Rethink-Task-Page` |
| Outline | Reading Time and Words, or a PDF's Pages, then the headings. | `ItemInspectorRows.swift` | `Rethink-Long-Page`, `Rethink-PDF` |
| Links | In Collection, Referenced By, Links in the Text, Excerpts, Thread, Attachments. | `ItemRelationships.swift` | `Rethink-Highlight`, `Rethink-Message` |
| Info | Source, version, created, edited, a file's facts, In, Leaves the Feed, who keeps it, History. The history is asked for when Info shows. | `ItemInspectorFields.swift` | `Rethink-Feed-Page-In`, `Rethink-Kept-By` |
| What goes | Properties, Tags, Relationships, From Apps and the sidebar's own arrangement, once the rows carry them. Fields the type does not declare are the last rows, under Other. A sync problem is a page notice. | `ItemProperties.swift`, `ItemTags.swift`, `SidebarArrangement` | `Rethink-Properties-Rule` |

## Editing and links

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Value panels | Gray highlight, chips in the field, counts beside tags and choices, Add for a new word. A parent shows its mark and its status. | `MarfaMac/Views/ValueEditing/` | `Rethink-Edit-Values`, `Rethink-Edit-Status`, `Rethink-Edit-Tags`, `Rethink-Edit-Text`, `Rethink-Edit-Location` |
| Lists with labels | Email and phone entries are edited in one panel, with a label column. | `ListEditing.swift` | `Rethink-Edit-Lists` |
| An event's time | One panel: start, end, all day and zone, one write. | `EventHeader`, `ValueEditKind` | `Rethink-Edit-Event` |
| Edges as rows | Each edge field a type may hold gets a row and a value panel: filled ones in place, the rest under Show More, and inverses where Marfa allows. The panel obeys Marfa's answer. One commit is one undo. Only a reference in the text is not editable. An item in no collection has an empty In Collection row. | `ValueEditKind`, `ItemRelationshipPicker`, `PropertyRow` | `Rethink-Properties-Rule`, `Rethink-Edit-Values` |
| Conflict | A calm line with Keep My Edit and Use Current Value. | `ValueEditModel` | `Rethink-Edit-Conflict` |
| Status where it is seen | A click on a status in a row or a lane opens its panel; the row stays until it is left. | `StatusSymbol`, `ItemRow.swift` | `Rethink-Status-In-List` |
| Change Type | From the page's head, the same panel, with what each type asks for. | `CommandValuePanels.swift`, `TypeValuesSheet` | `Rethink-Change-Type`, `Rethink-Change-Type-Values` |
| Every link follows Open Items | In the text, rows, foot and panel, through one function of the browser. A picture in the text has Open Item and Copy Link on its menu. | `Browser`, `EditorController` | – |
| Link card | After a pause on a linked item, a small card with its type, name and two lines. No keyboard focus, no server call. | new files in `MarfaMac/Views/`, `editor/src/` | `Rethink-Link-Card` |

## Page notices

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| One notice | One line in the page's column for a deleted item, a copy saved beside it, text that cannot be read, pictures not loaded, a held write or a missing file. It replaces the banners and the picture bar. Its one action has no fill. | `DeletedItemBanner`, `SavedAsCopyBanner`, `UnreadableItemBanner`, `PicturesWaitingCallout`, `editor/src/pictures.ts` | `Rethink-Page-Notice`, `Rethink-Page-Notices` |

## Each kind of item

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Task, project | Status, priority and due as rows, sub-items at the foot. | `TypeLooks`, `editor/src/header.ts` | `Rethink-Task-Page`, `Rethink-Project`, `Rethink-Project-Full` |
| Event | When is a row with how far off it is; attendees' answers in gray. | `EventHeader` | `Rethink-Event`, `Rethink-Event-Full` |
| Bookmark, article, web page | The description is a row; Reader or Original in the corner, the original at full width. The reading header goes. | `ReadingHeader`, `WebPageItemPage.swift` | `Rethink-Bookmark`, `Rethink-Bookmark-Full`, `Rethink-Web-Page-Reader`, `Rethink-Web-Page-Original` |
| Highlight | The passage is its text, in a leading style and edited as text. Its note is a row of two lines. It has no title. | `TypeLooks`, `editor/src/header.ts` | `Rethink-Highlight`, `Rethink-Highlight-Full`, `Rethink-Highlights` |
| Person, place | The first six rows. A place has a map on its page. | `PersonHeader`, `FileItemContent` | `Rethink-Person`, `Rethink-Person-Full`, `Rethink-Place`, `Rethink-Place-Full` |
| Message | No title field, so its text leads. From is a mark and a name. | `TypeLooks` | `Rethink-Message`, `Rethink-Message-Full` |
| Image | Fit in the corner, its facts, rows that can be edited. | `FileItemContent`, `FileCorner.swift` | `Rethink-Image`, `Rethink-Image-Full` |
| PDF | Paper on a gray or white ground, by a setting; contents in Outline. The PDF keeps its own scroller, with the head as its first inset; so do a video and a picture. | `FileItemContent`, `FileCorner.swift` | `Rethink-PDF`, `Rethink-PDF-Full`, `Rethink-PDF-White`, `Rethink-PDF-Full-White` |
| Audio, video | A playback bar at the window's foot, with a waveform, speed, skip and the place kept; nothing plays by itself. **Waits for Marfa:** a transcript. | `FileItemContent` | `Rethink-Audio`, `Rethink-Audio-Transcript`, `Rethink-Video`, `Rethink-Playback` |
| Table item | A sheet of its own rows, without properties or margins, row numbers off. The app keeps the order and a column's menu sets it. The last piece, and it may be cut. | new files in `MarfaMac/Views/` | `Rethink-Table-Item`, `Rethink-Table-Item-Full`, `Rethink-Table-Item-Numbers`, `Rethink-Table-Item-Column`, `Rethink-Table-Preview` |
| Read only | Read Only with a lock over the title, no Aa, and one line in Info. | `ItemPageHeader.swift` | `Rethink-Read-Only`, `Rethink-Read-Only-Full` |

## Version history

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Version History | The thread takes the sidebar's place. It shows text, title, type and property changes only, because a version holds no tags or links. Additions in green, Copy Text, no Show in Finder. The loading, failed, offline and thinned states stay. | `VersionHistoryWorkspace.swift`, `VersionThreadColumn.swift`, `VersionPageColumn` | `Rethink-History` |

## Sync and offline

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| The sync line | A warning mark on the two states that ask for action; the whole foot is one button. | `SidebarFoot.swift` | `Rethink-Sync-Lines`, `Rethink-Offline` |
| Settings the design adds | Each goes through `PreferencesMap`, optional when read, so an older copy of the app loses none. | `PreferencesMap` | – |

## Looks

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Areas, glass, measures | Three areas, where glass is used, and one set of measures, radii and type sizes. Dark values are in one table before they are used. | `InterfaceStyle`, `MarfaMac/Views/Looks/` | `Rethink-Found-Areas`, `Rethink-Found-Glass`, `Rethink-Found-Measures`, `Rethink-Found-Measures-Page`, `Rethink-Found-Radii`, `Rethink-Found-Type`, `Rethink-Found-Selection` |
| Buttons | Small is a rounded rectangle, larger is a capsule. A text action has a fill, but for a page notice's. | `AppButton.swift` | `Rethink-Page-Notices` |
| Messages | A toast is a symbol, what happened and Undo; a second replaces the first. An alert with a red button has a gray Cancel. | `ToastView.swift`, `LibraryDialogs.swift` | `Rethink-Keep-Toast`, `Rethink-Delete-Toast`, `Rethink-Delete-Alert` |

## Small ideas

| Part | What it is | Lands in | Boards |
| --- | --- | --- | --- |
| Follow a chip | A click on a chip that is not being edited lists everything that shares its value, as a search token. | `PageChip`, `SearchNarrowing` | `Rethink-Follow-Chip` |
| Drag onto a collection | A drop on a collection's row in the sidebar adds the items. Nothing else takes a drop there, and nothing springs open. | `SidebarGroups.swift` | `Rethink-Drag-To-Collection` |
| Board lanes | Lanes are dragged into an order. | `ItemBoard.swift` | – |
| Edit the type | A field's menu opens the type in Settings. | `FieldMenu` | – |
| Settings' parts | A connector's Files row in its mapping. **Waits for Marfa.** | `MarfaMac/Settings/Marfa/` | – |
