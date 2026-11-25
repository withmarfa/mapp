---
summary: The rules of the sidebar, toolbar, corner, menus, palettes, opening an item, the modal and item links.
paths:
  - MarfaMac/Model/Place.swift
  - MarfaMac/Model/Sidebar*.swift
  - MarfaMac/Model/ItemOpening.swift
  - MarfaMac/Model/ItemLink*.swift
  - MarfaMac/Model/Palette*.swift
  - MarfaMac/Views/Sidebar*.swift
  - MarfaMac/Views/Window*.swift
  - MarfaMac/Views/ItemModal.swift
  - MarfaMac/Views/ItemBesideColumn.swift
  - MarfaMac/Views/ItemWindow*.swift
  - MarfaMac/Model/ItemWindowHistory.swift
  - MarfaMac/Model/BesideSettler.swift
  - MarfaMac/Views/CommandPalette*.swift
---

# The window

`docs/look.md` has the window's areas. `docs/commands.md` has every command and shortcut.

## Places

- **A window shows a place and one of its views** (`PlaceView`, `Place`, `ViewChoice`), each stored as a word. An unknown word is kept as written; an unknown view reads as the place's own.
- **A window left in a place this copy cannot read** opens where a new window would, and keeps that place until the person moves (`Browser.laterPlace`).
- **A window follows its view to a new place** with what it keeps for the view (`PlaceMemory`). Views sort by the synced `viewOrder` row (`ViewOrders`), then title.
- **A window's snapshot and Start With have slots of their own** (`window`, `opening`, `openingLastPlace`), with its open item and scroll position. Files is no place: the person is told once.

## Sidebar

- **Search and New, the Library and the Feed, then Pinned, Types and the person's sections** (`SidebarLayout`). A row whose thing is gone keeps its place.
- **Pinned holds views, collections and items;** a saved view until taken out.
- **Five types show, then "N More",** each counting its kinds' items too.
- **Under the pointer** a row has a ground, a type, kind or collection a plus for its count, and a heading Add and More. Sections never fold.
- **Customize Sidebar works in place:** each faint place is a menu of what fits.
- **Go lists the same places, views and types** (`GoMenu`), and the Archive.

### A layout an earlier copy stored

- **An earlier Library or Views section is kept, drawn as nothing;** `places` and `pinned` stand there instead.
- **What was put under them is pinned; what a hidden one held stays hidden, row by row.** `views` in `hidden` hides every saved view; one shown again goes in `shown`. The Library and the Feed stay fixed.
- **A row whose section is gone shows under Pinned, a page under the Library;** its home is kept.
- **The later arrangement wins whole,** also when two Macs change what is hidden before syncing.
- **Accepted:** an older copy draws it its own way, and its Views edits miss Pinned, until Sparkle updates it.
- **Recently Deleted is a page of Settings**, never a row.

## Toolbar

- **The top row is drawn in the content under a title the window hides** (`TopRowFrame`); a plain `toolbar` holds only the buttons.
- **The views are a radio group;** VoiceOver reads every view, whatever has folded.
- **The row folds by the room it has** (`ToolbarRoomProbe`) and holds no width.
- **An on button is gray, never the accent.** An item that cannot act dims.
- **Trap:** hide the title on the window (`hidesWindowTitle`), or it returns in full screen. Read the row's line from `TopRowSpace`, never a safe area: full screen hides the toolbar.

## Sidebar closed

- **The title opens the sidebar's rows as a menu** (`PlacesMenu`); place, views and buttons share one row.

## Smallest window

- **The main window goes down to 760 by 520,** set once on its content. The panel folds under 1000 wide, the sidebar under 900, and under 800 the views are one pill beside the title.
- **Only what the window folded opens again,** also after a quit. It folds only as its width crosses a limit, never on opening.
- **The panel is 300 wide** in every window (`PanelWidth`).

## Corner

- **The corner holds only controls for viewing** the page or list in front (`WindowCorner`, `PageCorner`): formats, text size, focus, zoom, pages. A control turned off in Settings is in More instead.
- **The modal has no corner,** and the column beside a layout has Open as Page alone.

## Menus and palettes

- **Every menu of items is one menu** (`ItemRowMenu`), in every layout.
- **The palette has the menu bar's commands under its headings, then items and places** (`CommandPalette`). Search Items is the same panel searching titles and text.
- **Trap:** Actions grows out of the palette's bar with an ordinary transition: a Liquid Glass morph hung the app.
- **A command that takes the keyboard says so** (`takesFocus`), so the palette does not take it back.

## Opening an item

- **Open, Return, a double click and a link follow Open Items** (`ItemOpening`), and the menu offers the other ways.
- **Beside the List is the standard:** a layout that spans the window shows the chosen item's page in a column of 372 (`BesideColumn`), and a new row replaces it once the selection rests (`BesideSettler`).
- **A column, a modal and a full page show one item** with the window's one editor, one at a time. New Window takes several and asks first above a limit (`ItemWindows`).
- **The modal** (`ItemModal`) has Close, Up and Down, Keep on a Feed item, Favorite, Share, More and Open as Page, and no panel. Escape, Close and a click outside save and close it. Up and down follow the list behind it (`ListNeighbors`), Keep moves on once queued, and a followed link stays in it.
- **An item's window has the modal's controls and the panel** (`ItemWindowToolbar`); Back and Forward walk its links (`ItemWindow.go`).
- **A full page's Back returns to the layout**, and the list's view options are not offered.

## Item links

- **An item's app link is `marfa://`, its Marfa's id, then its own,** both exact and lowercase (`ItemAppLink`). Any other form is refused.
- **A link only opens,** never writes, signs in, changes a setting or calls the server: any page can send one.
- **It opens only when** the Marfa it names is the connected one, the copy holds the item, and the item is not in Recently Deleted. Otherwise the person is told why (`ItemLinkRoute`).
- **It opens in the main window last in front** (`ItemLinkOpener`), as a full page where Open Items says so and over the list otherwise.
- **The newest link wins** over one that waits for the library or a window.
- **Copy Link copies the server's `https` address**, and the `marfa://` one where the server gives none. Copy Wiki Link copies the text form.
- **Trap:** a Debug test build registers another scheme (`ITEM_LINK_SCHEME`), so it never takes the installed app's links.
