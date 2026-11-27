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

`docs/look.md` has the window's areas; `docs/commands.md`, every command.

## Places

- **A window shows a place and one of its views** (`PlaceView`, `Place`, `ViewChoice`), each stored as a word. An unknown word is kept as written; an unknown view reads as the place's own.
- **A window left in a place this copy cannot read** opens where a new window would, and keeps it until the person moves (`Browser.laterPlace`).
- **A window follows its view to a new place** with what it keeps (`PlaceMemory`).
- **A window's snapshot and Start With have slots of their own** (`window`, `opening`, `openingLastPlace`), with its open item and scroll position. Files is no place: the person is told once.

## Sidebar

- **Search and New, Library and Feed, then Pinned, Types and custom sections** (`SidebarLayout`). Missing items keep their rows.
- **Pinned holds views, collections and items.** Saved views stay until unpinned.
- **Five types show, then "N More".** Counts include kinds.
- **Hover highlights rows,** swaps counts for Add and shows Add and More on headings. Sections stay open. The chosen row stays soft gray, focused or not.
- **Customize Sidebar** uses a menu on each faded place.
- **Go lists sidebar places, views and types, plus Archive** (`GoMenu`).

### A layout an earlier copy stored

- **An earlier Library or Views section is kept, drawn as nothing;** `places` and `pinned` stand there.
- **What was put under them is pinned; what a hidden one held stays hidden, row by row.** `views` in `hidden` hides every saved view; one shown again goes in `shown`. The Library and the Feed stay fixed.
- **A row whose section is gone shows under Pinned, a page under the Library;** its home is kept.
- **The later arrangement wins whole,** also when two Macs change what is hidden before syncing.
- **Open Trash in Settings** to see recently deleted items.

## Foot

- **The foot is one button that opens the Marfa's panel** (`SidebarFoot`, `MarfaPanel`), with no hover fill. Refresh, Settings and a warning line are buttons; the line opens Settings › Connection.

## Toolbar

- **The top row is drawn in the content under a title the window hides** (`TopRowFrame`); a plain `toolbar` holds only the buttons.
- **The views are a radio group;** VoiceOver reads every view, folded or not.
- **The first pill's text aligns with the title's text** (`TopRowMetrics.pillInset`).
- **The row folds by its room** (`ToolbarRoomProbe`) into N More, with hidden pills and New View…, and holds no width. One view makes no row.
- **An on button is gray, never the accent.** An item that cannot act dims.
- **Trap:** hide the title on the window (`hidesWindowTitle`), or it returns in full screen. Read the row's line from `TopRowSpace`, never a safe area: full screen hides the toolbar.

## Sidebar closed

- **The title opens the sidebar's rows as a menu** (`PlacesMenu`); place, views and buttons share one row; in a list column, or beside a page under 800 wide, title and views go below.

## Smallest window

- **The main window's minimum is 760 by 520,** set on its content. The panel folds below 1000 and the sidebar below 900. The app reopens only what it folded. Below 800, views share one pill.
- **The panel starts at 300 points** and can be widened (`PanelWidth`).
- **The page beside a layout starts at 440 points,** and its divider drags between 300 and 600 (`BesideWidth`). It gives way to the layout's 600, down to 300 (`BesideColumn`).

## Corner

- **The corner holds only controls for viewing** the page or list in front (`WindowCorner`, `PageCorner`): formats, text size, focus, zoom, pages. A control turned off in Settings is in More.
- **Labels on content glass dim with the window** (`windowGlass`).
- **The modal has no corner,** and the column beside a layout has Open as Page alone.

## Menus and palettes

- **Every menu of items is one menu** (`ItemRowMenu`), in every layout.
- **The palette has the menu bar's commands under its headings, then items and places** (`CommandPalette`). Search Items' filters are tokens (`PaletteTokens`).
- **Trap:** Actions grows out of the palette's bar with an ordinary transition: a Liquid Glass morph hung the app.
- **A command that takes the keyboard says so** (`takesFocus`), so the palette does not take it back.

## Opening an item

- **Open, Return, double-click, and links follow Open items in** (`ItemOpening`) unless the place sets Open Items.
- **Beside the List is the standard:** a layout that spans the window shows the chosen item's page beside it, and a new row replaces it once the selection rests (`BesideSettler`).
- **A column, a modal and a full page show one item** with the window's one editor, one at a time. New Window takes several and asks first above a limit (`ItemWindows`).
- **The modal** (`ItemModal`) has Close, Up and Down, Keep on a Feed item, Favorite, Share, More and Open as Page, and no panel. Escape, Close and a click outside save and close it. Up and down follow the list behind it (`ListNeighbors`); Keep moves on once queued, and a followed link stays in it.
- **An item's window has the modal's controls and the panel** (`ItemWindowToolbar`); Back and Forward walk its links (`ItemWindow.go`).
- **A full page's Back returns to the layout**, without view options.

## Item links

- **An item's app link is `marfa://`, its Marfa's id, then its own,** both exact and lowercase (`ItemAppLink`). Any other form is refused.
- **A link only opens,** never writes, signs in, changes a setting or calls the server: any page can send one.
- **It opens only when** the Marfa it names is the connected one, the copy holds the item, and the item is not in Recently Deleted. Otherwise the person is told why (`ItemLinkRoute`).
- **It opens in the last active main window** (`ItemLinkOpener`), as a full page for Full Page and over the list otherwise.
- **The newest link wins** over one that waits for the library or a window.
- **Copy Link copies the server's `https` address**, and the `marfa://` one where the server gives none. Copy Wiki Link copies the text form.
- **Trap:** a Debug test build registers another scheme (`ITEM_LINK_SCHEME`), so it never takes the installed app's links.
